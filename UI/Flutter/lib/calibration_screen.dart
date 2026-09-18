import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/decoder.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  FlutterSoundPlayer? _player;
  FlutterSoundRecorder? _recorder;

  bool _isPlayerInitialized = false;
  bool _isRecorderInitialized = false;

  bool _isPlaying = false;
  String? _currentlyPlayingTone;

  bool _isRecording = false;
  StreamSubscription<Uint8List>? _recordingSubscription;
  StreamController<Uint8List>? _recordingStreamController;

  // Rolling buffer for audio samples
  final int _windowSize = (sampleRate * symbolDurationMs / 1000).round();
  final List<double> _rollingBuffer = <double>[];

  // Magnitudes
  double _mag17000 = 0.0;
  double _mag18000 = 0.0;
  double _mag19500 = 0.0;

  DateTime _lastUiUpdateTime = DateTime.now();

  // Playback tone duration (5 seconds per press)
  static const double _testToneDurationMs = 5000.0;
  static const double _testToneAmplitude = 0.5; // Clear volume for speaker test

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    _player = FlutterSoundPlayer();
    _recorder = FlutterSoundRecorder();

    await _player!.openPlayer();
    _isPlayerInitialized = true;

    await _recorder!.openRecorder();
    _isRecorderInitialized = true;

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _stopTone();
    _stopRecording();
    _player?.closePlayer();
    _recorder?.closeRecorder();
    super.dispose();
  }

  Future<void> _playTone(String name, double frequency) async {
    if (!_isPlayerInitialized || _player == null) return;

    await _stopTone();

    final samples = ToneGenerator.generatePureTone(
      frequency,
      _testToneDurationMs,
      amplitude: _testToneAmplitude,
    );

    final wavBytes = WavUtils.writeWavBytes(
      samples,
      sampleRate: sampleRate,
    );

    setState(() {
      _isPlaying = true;
      _currentlyPlayingTone = name;
    });

    await _player!.startPlayer(
      fromDataBuffer: wavBytes,
      codec: Codec.pcm16WAV,
      whenFinished: () {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentlyPlayingTone = null;
          });
        }
      },
    );
  }

  Future<void> _stopTone() async {
    if (!_isPlayerInitialized || _player == null) return;
    if (_player!.isPlaying) {
      await _player!.stopPlayer();
    }
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _currentlyPlayingTone = null;
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized || _recorder == null) return;

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }

    _recordingStreamController = StreamController<Uint8List>();
    _recordingSubscription = _recordingStreamController!.stream.listen((buffer) {
      _processIncomingPcmBytes(buffer);
    });

    await _recorder!.startRecorder(
      toStream: _recordingStreamController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
    );

    setState(() {
      _isRecording = true;
      _rollingBuffer.clear();
      _mag17000 = 0.0;
      _mag18000 = 0.0;
      _mag19500 = 0.0;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecorderInitialized || _recorder == null) return;

    if (_recorder!.isRecording) {
      await _recorder!.stopRecorder();
    }

    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _recordingStreamController?.close();
    _recordingStreamController = null;

    if (mounted) {
      setState(() {
        _isRecording = false;
      });
    }
  }

  void _processIncomingPcmBytes(Uint8List bytes) {
    if (bytes.length < 2) return;

    final byteData = ByteData.sublistView(bytes);
    final sampleCount = bytes.length ~/ 2;

    for (int i = 0; i < sampleCount; i++) {
      final int16 = byteData.getInt16(i * 2, Endian.little);
      final sample = int16 / 32768.0;
      _rollingBuffer.add(sample);
    }

    // Keep rolling window at _windowSize
    if (_rollingBuffer.length > _windowSize) {
      _rollingBuffer.removeRange(0, _rollingBuffer.length - _windowSize);
    }

    if (_rollingBuffer.length == _windowSize) {
      final now = DateTime.now();
      // Throttle UI update to ~15 Hz
      if (now.difference(_lastUiUpdateTime).inMilliseconds >= 65) {
        _lastUiUpdateTime = now;

        final m17 = Decoder.goertzelMagnitude(_rollingBuffer, 0, preambleFreq);
        final m18 = Decoder.goertzelMagnitude(_rollingBuffer, 0, bit0Freq);
        final m195 = Decoder.goertzelMagnitude(_rollingBuffer, 0, bit1Freq);

        if (mounted) {
          setState(() {
            _mag17000 = m17;
            _mag18000 = m18;
            _mag19500 = m195;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxMag = [
      _mag17000,
      _mag18000,
      _mag19500,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage 4 — Audio Calibration'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF121418),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader('1. Tone Emitter (Speaker)'),
              const SizedBox(height: 8),
              _buildToneButton(
                label: 'Play Preamble (17000 Hz)',
                toneName: 'Preamble (17 kHz)',
                frequency: preambleFreq,
                color: Colors.amber.shade700,
              ),
              const SizedBox(height: 8),
              _buildToneButton(
                label: 'Play Bit 0 (18000 Hz)',
                toneName: 'Bit 0 (18 kHz)',
                frequency: bit0Freq,
                color: Colors.cyan.shade700,
              ),
              const SizedBox(height: 8),
              _buildToneButton(
                label: 'Play Bit 1 (19500 Hz)',
                toneName: 'Bit 1 (19.5 kHz)',
                frequency: bit1Freq,
                color: Colors.green.shade700,
              ),
              const SizedBox(height: 8),
              if (_isPlaying)
                ElevatedButton.icon(
                  onPressed: _stopTone,
                  icon: const Icon(Icons.stop, color: Colors.white),
                  label: Text('Stop Tone ($_currentlyPlayingTone)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              const Divider(color: Colors.white24, height: 32),
              _buildSectionHeader('2. Real-time Goertzel Detector (Mic)'),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                ),
                label: Text(
                  _isRecording ? 'Stop Recording' : 'Start Recording',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isRecording ? Colors.red.shade800 : Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              _buildMagnitudeDisplay(
                title: 'Preamble (17000 Hz)',
                magnitude: _mag17000,
                maxMag: maxMag,
                color: Colors.amberAccent,
                isDominant: _mag17000 > _mag18000 * 1.5 &&
                    _mag17000 > _mag19500 * 1.5 &&
                    _mag17000 > 0.5,
              ),
              const SizedBox(height: 10),
              _buildMagnitudeDisplay(
                title: 'Bit 0 (18000 Hz)',
                magnitude: _mag18000,
                maxMag: maxMag,
                color: Colors.cyanAccent,
                isDominant: _mag18000 > _mag17000 * 1.5 &&
                    _mag18000 > _mag19500 * 1.5 &&
                    _mag18000 > 0.5,
              ),
              const SizedBox(height: 10),
              _buildMagnitudeDisplay(
                title: 'Bit 1 (19500 Hz)',
                magnitude: _mag19500,
                maxMag: maxMag,
                color: Colors.greenAccent,
                isDominant: _mag19500 > _mag17000 * 1.5 &&
                    _mag19500 > _mag18000 * 1.5 &&
                    _mag19500 > 0.5,
              ),
              const Divider(color: Colors.white24, height: 32),
              _buildHardwareTips(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildToneButton({
    required String label,
    required String toneName,
    required double frequency,
    required Color color,
  }) {
    final isThisTonePlaying = _isPlaying && _currentlyPlayingTone == toneName;
    return ElevatedButton(
      onPressed: () => _playTone(toneName, frequency),
      style: ElevatedButton.styleFrom(
        backgroundColor: isThisTonePlaying ? Colors.amber : color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isThisTonePlaying ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildMagnitudeDisplay({
    required String title,
    required double magnitude,
    required double maxMag,
    required Color color,
    required bool isDominant,
  }) {
    final ratio = (magnitude / (maxMag > 0 ? maxMag : 1.0)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDominant ? color : Colors.white12,
          width: isDominant ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                'Mag: ${magnitude.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDominant ? color : color.withValues(alpha: 0.5),
              ),
            ),
          ),
          if (isDominant) ...[
            const SizedBox(height: 4),
            const Text(
              '★ DOMINANT SIGNAL DETECTED',
              style: TextStyle(
                color: Colors.yellowAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHardwareTips() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hardware Calibration Checklist:',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '1. Loopback Smoke Test: Tap "Start Recording", then tap "Play Bit 0". Verify Bit 0 magnitude rises significantly above Preamble & Bit 1.\n'
            '2. Two-Phone Test: Phone A plays each tone. Phone B records across air gap at 10-30cm. Verify clear discrimination.\n'
            '3. Record device models and observed magnitudes in docs/stage4_calibration_results.md.',
            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}
