import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import '../dsp/aes_crypto.dart';
import '../dsp/goertzel_decoder.dart';
import '../dsp/protocol.dart';
import '../dsp/tone_generator.dart' hide preambleSampleCount, symbolSampleCount;

class AudioReceiver {
  static FlutterSoundRecorder? _recorder;
  static StreamController<Uint8List>? _streamController;
  static StreamSubscription<Uint8List>? _streamSubscription;
  static Timer? _timeoutTimer;
  static final List<double> _samples = <double>[];
  static Uint8List? _key;
  static void Function(String?)? _onResult;
  static void Function(String)? _onStatus;
  static bool _listening = false;
  static bool _resultDelivered = false;
  static int? _preambleStart;
  static int? _expectedFrameSamples;

  static bool get isListening => _listening;

  static Future<void> startListening(
    Uint8List key,
    void Function(String?) onResult, {
    void Function(String status)? onStatus,
    FlutterSoundRecorder? recorder,
  }) async {
    await stopListening(notifyNull: false);

    final permission = await Permission.microphone.request();
    if (permission != PermissionStatus.granted) {
      onStatus?.call('microphone permission denied');
      onResult(null);
      return;
    }

    _key = key;
    _onResult = onResult;
    _onStatus = onStatus;
    _samples.clear();
    _preambleStart = null;
    _expectedFrameSamples = null;
    _resultDelivered = false;
    _listening = true;

    final activeRecorder = recorder ?? (_recorder ??= FlutterSoundRecorder());
    if (!activeRecorder.isRecording) {
      await activeRecorder.openRecorder();
    }
    _streamController = StreamController<Uint8List>();
    _streamSubscription = _streamController!.stream.listen(_processPcm);

    _onStatus?.call('listening');
    await activeRecorder.startRecorder(
      toStream: _streamController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
    );
  }

  static Future<void> stopListening({
    bool notifyNull = true,
    FlutterSoundRecorder? recorder,
  }) async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final activeRecorder = recorder ?? _recorder;
    if (activeRecorder?.isRecording ?? false) {
      await activeRecorder!.stopRecorder();
    }
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _streamController?.close();
    _streamController = null;

    final wasListening = _listening;
    _listening = false;
    if (wasListening && notifyNull && !_resultDelivered) {
      _onStatus?.call('no message detected');
      _deliver(null);
    }
  }

  static Future<void> dispose([FlutterSoundRecorder? recorder]) async {
    await stopListening(notifyNull: false, recorder: recorder);
    final activeRecorder = recorder ?? _recorder;
    if (activeRecorder != null) {
      await activeRecorder.closeRecorder();
    }
    if (recorder == null) _recorder = null;
  }

  static void _processPcm(Uint8List bytes) {
    if (!_listening || bytes.length < 2) return;
    final data = ByteData.sublistView(bytes);
    for (int offset = 0; offset + 1 < bytes.length; offset += 2) {
      _samples.add(data.getInt16(offset, Endian.little) / 32768.0);
    }
    _tryDecode();
  }

  static void _tryDecode() {
    if (!_listening || _key == null) return;

    if (_preambleStart == null) {
      _preambleStart = detectPreamble(_samples);
      if (_preambleStart == null) return;
      _onStatus?.call('preamble detected; receiving frame');
    }

    final start = _preambleStart!;
    const headerBits = 24;
    final headerEnd = start + preambleSampleCount +
        headerBits * symbolSampleCount;
    if (_samples.length < headerEnd) return;

    if (_expectedFrameSamples == null) {
      final payloadBits = decodeLengthHeader(_samples, start);
      if (payloadBits <= 0 || payloadBits > 255 || payloadBits % 8 != 0) {
        _onStatus?.call('invalid frame length');
        _resetSearch(start + symbolSampleCount);
        return;
      }
      _expectedFrameSamples = preambleSampleCount +
          headerBits * symbolSampleCount + payloadBits * symbolSampleCount;
      final ciphertextBytes = payloadBits ~/ 8;
      final timeoutSeconds = 1.1 + (0.8 * ciphertextBytes);
      _timeoutTimer = Timer(
        Duration(milliseconds: (timeoutSeconds * 1000).ceil()),
        () => stopListening(),
      );
    }

    final requiredEnd = start + _expectedFrameSamples!;
    if (_samples.length < requiredEnd) return;

    _onStatus?.call('decoding and decrypting');
    final payloadStart = start + preambleSampleCount +
        headerBits * symbolSampleCount;
    final payloadBits = <int>[];
    final bitCount = _expectedFrameSamples! -
        preambleSampleCount - headerBits * symbolSampleCount;
    for (int offset = 0; offset < bitCount; offset += symbolSampleCount) {
      final window = _samples.sublist(
        payloadStart + offset,
        payloadStart + offset + symbolSampleCount,
      );
      payloadBits.add(decodeBit(window));
    }

    try {
      final plaintext = decrypt(
        Uint8List.fromList(bitsToBytes(payloadBits)),
        _key!,
      );
      _deliver(plaintext);
      stopListening(notifyNull: false);
    } catch (_) {
      _onStatus?.call('frame detected but decryption failed');
      stopListening();
    }
  }

  static void _resetSearch(int offset) {
    _preambleStart = null;
    _expectedFrameSamples = null;
    if (offset < _samples.length) {
      _samples.removeRange(0, offset);
    }
  }

  static void _deliver(String? message) {
    if (_resultDelivered) return;
    _resultDelivered = true;
    _onResult?.call(message);
  }
}
