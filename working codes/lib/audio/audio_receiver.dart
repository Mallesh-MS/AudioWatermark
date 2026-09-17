import 'dart:async';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import '../dsp/aes_crypto.dart';
import '../dsp/decoder.dart';
import '../dsp/protocol.dart';
import '../dsp/tone_generator.dart';

class AudioReceiver {
  static FlutterSoundRecorder? _recorder;
  static StreamController<Uint8List>? _streamController;
  static StreamSubscription<Uint8List>? _streamSubscription;

  static bool _isListening = false;
  static bool get isListening => _isListening;

  static final List<double> _accumulatedSamples = <double>[];
  static int _searchOffset = 0;
  static void Function(String?)? _onResultCallback;
  static void Function(String)? _onStatusCallback;
  static Key? _activeKey;

  static final int _symbolSamples =
      (sampleRate * symbolDurationMs / 1000).round();
  static final int _preambleSamples =
      (sampleRate * preambleDurationMs / 1000).round();

  /// Starts recording raw PCM via [FlutterSoundRecorder]'s stream API,
  /// accumulating samples into an in-memory buffer and scanning for
  /// incoming watermark preambles and payloads.
  ///
  /// Calls [onResult] with the decoded string as soon as a valid message
  /// is found (and automatically stops recording), or `null` if recording
  /// is stopped without finding a valid message.
  static Future<void> startListening({
    required Key key,
    required void Function(String?) onResult,
    void Function(String)? onStatus,
    FlutterSoundRecorder? recorder,
  }) async {
    await stopListening(notifyNull: false);

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      onStatus?.call('Microphone permission denied');
      onResult(null);
      return;
    }

    _activeKey = key;
    _onResultCallback = onResult;
    _onStatusCallback = onStatus;
    _accumulatedSamples.clear();
    _searchOffset = 0;

    final activeRecorder = recorder ?? (_recorder ??= FlutterSoundRecorder());
    try {
      await activeRecorder.openRecorder();
    } catch (_) {
      // Ignore if already open
    }

    _streamController = StreamController<Uint8List>();
    _streamSubscription = _streamController!.stream.listen((buffer) {
      _processIncomingBytes(buffer);
    });

    _isListening = true;
    _onStatusCallback?.call('Listening for watermark signal...');

    await activeRecorder.startRecorder(
      toStream: _streamController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
    );
  }

  /// Manually stops listening. If no message was decoded yet, calls
  /// [onResult] with `null` unless [notifyNull] is set to false.
  static Future<void> stopListening({
    bool notifyNull = true,
    FlutterSoundRecorder? recorder,
  }) async {
    final activeRecorder = recorder ?? _recorder;
    if (activeRecorder != null && activeRecorder.isRecording) {
      await activeRecorder.stopRecorder();
    }

    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _streamController?.close();
    _streamController = null;

    final wasListening = _isListening;
    _isListening = false;

    if (wasListening && notifyNull) {
      _onStatusCallback?.call('Listening stopped.');
      _onResultCallback?.call(null);
    }
  }

  /// Closes recorder and releases resources.
  static Future<void> dispose([FlutterSoundRecorder? recorder]) async {
    await stopListening(notifyNull: false, recorder: recorder);
    final activeRecorder = recorder ?? _recorder;
    if (activeRecorder != null) {
      try {
        await activeRecorder.closeRecorder();
      } catch (_) {}
    }
    if (recorder == null) {
      _recorder = null;
    }
  }

  /// Converts incoming 16-bit PCM bytes to doubles and appends to the buffer,
  /// then triggers an incremental decode attempt.
  static void _processIncomingBytes(Uint8List bytes) {
    if (bytes.length < 2 || !_isListening) return;

    final byteData = ByteData.sublistView(bytes);
    final sampleCount = bytes.length ~/ 2;

    for (int i = 0; i < sampleCount; i++) {
      final int16 = byteData.getInt16(i * 2, Endian.little);
      _accumulatedSamples.add(int16 / 32768.0);
    }

    _attemptIncrementalDecode();
  }

  /// Attempts to find preamble and decode length-prefixed payload from
  /// the accumulated samples.
  static void _attemptIncrementalDecode() {
    if (_activeKey == null || !_isListening) return;
    if (_accumulatedSamples.length < _preambleSamples) return;

    try {
      // Find preamble starting from _searchOffset
      final preambleEnd = Decoder.findPreambleEndFrom(
        _accumulatedSamples,
        _searchOffset,
      );

      if (preambleEnd == null) {
        // No preamble found yet; advance search offset keeping preamble-length overlap
        if (_accumulatedSamples.length > _preambleSamples) {
          _searchOffset = _accumulatedSamples.length - _preambleSamples;
        }
        return;
      }

      // Preamble found! Check if we have enough samples for the 24-bit header
      final headerSampleCount = 24 * _symbolSamples;
      if (_accumulatedSamples.length < preambleEnd + headerSampleCount) {
        _onStatusCallback?.call('Preamble detected! Receiving header...');
        return;
      }

      // Read header
      final headerSamples = _accumulatedSamples.sublist(preambleEnd);
      final rawHeaderBits = Decoder.readBits(headerSamples, 24);
      final byteLength = Decoder.majorityVoteHeader(rawHeaderBits);

      if (byteLength <= 0 || byteLength > 255) {
        // Invalid header; advance past this false hit and resume searching
        _searchOffset = preambleEnd + _symbolSamples;
        return;
      }

      final totalRequiredSamples =
          preambleEnd + headerSampleCount + (byteLength * 8 * _symbolSamples);

      if (_accumulatedSamples.length < totalRequiredSamples) {
        _onStatusCallback?.call(
          'Receiving payload (${_accumulatedSamples.length}/$totalRequiredSamples samples)...',
        );
        return;
      }

      // We have all payload samples!
      _onStatusCallback?.call('Decoding & decrypting message...');
      final payloadSamples =
          _accumulatedSamples.sublist(preambleEnd + headerSampleCount);
      final payloadBits = Decoder.readBits(payloadSamples, byteLength * 8);
      final ciphertextBytes = ToneGenerator.bitsToBytes(payloadBits);

      final decrypted = WatermarkCrypto.decrypt(
        Uint8List.fromList(ciphertextBytes),
        _activeKey!,
      );

      // Successfully decoded!
      final callback = _onResultCallback;
      stopListening(notifyNull: false);
      _onStatusCallback?.call('Message successfully recovered!');
      callback?.call(decrypted);
    } catch (_) {
      // On parsing anomaly, keep listening for more samples or subsequent frames
    }
  }

  /// In-memory testing helper for simulating incremental buffer reception.
  static String? decodeFromBuffer(List<double> samples, Key key) {
    _accumulatedSamples.clear();
    _accumulatedSamples.addAll(samples);
    _searchOffset = 0;
    _activeKey = key;

    final preambleEnd = Decoder.findPreambleEndFrom(_accumulatedSamples, 0);
    if (preambleEnd == null) return null;

    final headerSampleCount = 24 * _symbolSamples;
    if (_accumulatedSamples.length < preambleEnd + headerSampleCount) {
      return null;
    }

    final headerSamples = _accumulatedSamples.sublist(preambleEnd);
    final rawHeaderBits = Decoder.readBits(headerSamples, 24);
    final byteLength = Decoder.majorityVoteHeader(rawHeaderBits);

    final totalRequiredSamples =
        preambleEnd + headerSampleCount + (byteLength * 8 * _symbolSamples);
    if (_accumulatedSamples.length < totalRequiredSamples) {
      return null;
    }

    final payloadSamples =
        _accumulatedSamples.sublist(preambleEnd + headerSampleCount);
    final payloadBits = Decoder.readBits(payloadSamples, byteLength * 8);
    final ciphertextBytes = ToneGenerator.bitsToBytes(payloadBits);

    return WatermarkCrypto.decrypt(
      Uint8List.fromList(ciphertextBytes),
      key,
    );
  }
}
