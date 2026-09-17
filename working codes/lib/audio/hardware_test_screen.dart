import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import '../dsp/goertzel_decoder.dart';
import '../dsp/protocol.dart';
import '../dsp/tone_generator.dart';
import 'wav_utils.dart';

class HardwareTestScreen extends StatefulWidget {
  const HardwareTestScreen({super.key});

  @override
  State<HardwareTestScreen> createState() => _HardwareTestScreenState();
}

class _MagnitudeReading {
  final double seconds;
  final double preamble;
  final double bit0;
  final double bit1;

  const _MagnitudeReading({
    required this.seconds,
    required this.preamble,
    required this.bit0,
    required this.bit1,
  });
}

class _HardwareTestScreenState extends State<HardwareTestScreen> {
  static const _recordingDuration = Duration(seconds: 5);
  static const _windowDurationMs = 100.0;
  static const _hopDurationMs = 50.0;
  static const _toneAmplitude = 0.5;

  final _readings = <_MagnitudeReading>[];
  final _recordedSamples = <double>[];
  final _windowSamples = (sampleRate * _windowDurationMs / 1000).round();
  final _hopSamples = (sampleRate * _hopDurationMs / 1000).round();

  FlutterSoundPlayer? _player;
  FlutterSoundRecorder? _recorder;
  StreamController<Uint8List>? _recordingController;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingTimer;
  int _nextWindowStart = 0;

  bool _isPlaying = false;
  bool _isRecording = false;
  String _status = 'Ready. Use two separate phones.';

  @override
  void initState() {
    super.initState();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      _player = FlutterSoundPlayer();
      _recorder = FlutterSoundRecorder();
      await _player!.openPlayer();
      await _recorder!.openRecorder();
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Audio initialization error: $error');
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
    _recordingController?.close();
    _player?.closePlayer();
    _recorder?.closeRecorder();
    super.dispose();
  }

  List<double> _buildTestSequence() {
    final silence = List<double>.filled(sampleRate, 0.0);
    return <double>[
      ...ToneGenerator.generatePureTone(
        preambleFreq,
        preambleDurationMs,
        amplitude: _toneAmplitude,
      ),
      ...silence,
      ...ToneGenerator.generatePureTone(
        bit0Freq,
        1000,
        amplitude: _toneAmplitude,
      ),
      ...silence,
      ...ToneGenerator.generatePureTone(
        bit1Freq,
        1000,
        amplitude: _toneAmplitude,
      ),
      ...silence,
    ];
  }

  Future<void> _playTestTones() async {
    final player = _player;
    if (player == null) return;

    if (player.isPlaying) {
      await player.stopPlayer();
    }

    final bytes = WavUtils.writeWavBytes(
      _buildTestSequence(),
      sampleRate: sampleRate,
    );

    setState(() {
      _isPlaying = true;
      _status = 'Playing 17 kHz, 18 kHz, and 19.5 kHz test sequence...';
    });

    await player.startPlayer(
      fromDataBuffer: bytes,
      codec: Codec.pcm16WAV,
      whenFinished: () {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _status = 'Playback complete.';
          });
        }
      },
    );
  }

  Future<void> _startRecording() async {
    final recorder = _recorder;
    if (recorder == null || _isRecording) return;

    final permission = await Permission.microphone.request();
    if (permission != PermissionStatus.granted) {
      setState(() => _status = 'Microphone permission denied.');
      return;
    }

    await _recordingSubscription?.cancel();
    await _recordingController?.close();
    _recordedSamples.clear();
    _readings.clear();
    _nextWindowStart = 0;
    _recordingController = StreamController<Uint8List>();
    _recordingSubscription = _recordingController!.stream.listen(
      _processPcmBytes,
    );

    await recorder.startRecorder(
      toStream: _recordingController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
    );

    setState(() {
      _isRecording = true;
      _status = 'Recording for 5 seconds. Start Phone A playback now.';
    });
    _recordingTimer = Timer(_recordingDuration, _stopRecording);
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final recorder = _recorder;
    if (recorder != null && recorder.isRecording) {
      await recorder.stopRecorder();
    }
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _recordingController?.close();
    _recordingController = null;

    if (mounted) {
      setState(() {
        _isRecording = false;
        _status = 'Recording complete. Review the raw readings below.';
      });
    }
  }

  void _processPcmBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (int index = 0; index + 1 < bytes.length; index += 2) {
      _recordedSamples.add(data.getInt16(index, Endian.little) / 32768.0);
    }

    while (_nextWindowStart + _windowSamples <= _recordedSamples.length) {
      final window = _recordedSamples.sublist(
        _nextWindowStart,
        _nextWindowStart + _windowSamples,
      );
      final reading = _MagnitudeReading(
        seconds: _nextWindowStart / sampleRate,
        preamble: goertzelMagnitude(window, preambleFreq, sampleRate),
        bit0: goertzelMagnitude(window, bit0Freq, sampleRate),
        bit1: goertzelMagnitude(window, bit1Freq, sampleRate),
      );
      _readings.add(reading);
      _nextWindowStart += _hopSamples;
    }

    if (mounted) setState(() {});
  }

  double _maximum(String frequency) {
    if (_readings.isEmpty) return 0;
    return _readings.map((reading) {
      switch (frequency) {
        case '17k':
          return reading.preamble;
        case '18k':
          return reading.bit0;
        default:
          return reading.bit1;
      }
    }).reduce((a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final max18 = _maximum('18k');
    final max195 = _maximum('19.5k');

    return Scaffold(
      appBar: AppBar(title: const Text('Stage 4 - Hardware Test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Raw speaker/microphone frequency check',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'No encryption, framing, or song embedding is used here. Use a second physical phone for playback or recording.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isPlaying ? null : _playTestTones,
              icon: const Icon(Icons.volume_up),
              label: Text(_isPlaying ? 'Playing Test Tones...' : 'Play Test Tones'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop Recording' : 'Record & Analyze'),
            ),
            const SizedBox(height: 12),
            Text(_status),
            const SizedBox(height: 16),
            _buildSummary('17 kHz maximum', _maximum('17k')),
            _buildSummary('18 kHz maximum', max18),
            _buildSummary('19.5 kHz maximum', max195),
            const SizedBox(height: 16),
            const Text(
              'Sliding-window readings (100 ms window, 50 ms hop)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_readings.isEmpty)
              const Text('No readings yet.')
            else
              ..._readings.reversed.take(40).map(_buildReading),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: ${value.toStringAsFixed(2)}'),
    );
  }

  Widget _buildReading(_MagnitudeReading reading) {
    return Text(
      '${reading.seconds.toStringAsFixed(2)}s   '
      '17k=${reading.preamble.toStringAsFixed(2)}   '
      '18k=${reading.bit0.toStringAsFixed(2)}   '
      '19.5k=${reading.bit1.toStringAsFixed(2)}',
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    );
  }
}