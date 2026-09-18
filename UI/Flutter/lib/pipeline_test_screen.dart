import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:dsp/audio/audio_receiver.dart';
import 'package:dsp/audio/audio_transmitter.dart';
import 'calibration_screen.dart';
import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tuning_config.dart';
import 'package:dsp/qr/qr_key_exchange.dart';
import 'qr_scan_screen.dart';

/// In-app log entry capturing empirical two-device test parameters and outcome.
class Stage6TestLog {
  final DateTime timestamp;
  final double amplitude;
  final double threshold;
  final double symbolDurationMs;
  final String distance;
  final String environment;
  final int messageLength;
  final bool isSuccess;
  final String notes;

  const Stage6TestLog({
    required this.timestamp,
    required this.amplitude,
    required this.threshold,
    required this.symbolDurationMs,
    required this.distance,
    required this.environment,
    required this.messageLength,
    required this.isSuccess,
    required this.notes,
  });

  String toMarkdownTableRow() {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final status = isSuccess ? 'PASS' : 'FAIL';
    return '| $timeStr | $distance | $environment | ${amplitude.toStringAsFixed(3)} | ${threshold.toStringAsFixed(1)} | ${symbolDurationMs.toStringAsFixed(0)}ms | $messageLength | $status | $notes |';
  }
}

class PipelineTestScreen extends StatefulWidget {
  const PipelineTestScreen({super.key});

  @override
  State<PipelineTestScreen> createState() => _PipelineTestScreenState();
}

enum HostMode { assetWav, syntheticMusic, quiet }

class _PipelineTestScreenState extends State<PipelineTestScreen> {
  final TextEditingController _messageController =
      TextEditingController(text: 'SECRET_STAGE7_OK');
  final TextEditingController _notesController = TextEditingController();

  late enc.Key _activeKey;
  String _keyHex = '';
  bool _showQrCode = true;

  HostMode _hostMode = HostMode.assetWav;
  List<double>? _assetHostSamples;
  bool _isLoadingAsset = false;

  String _txStatus = 'Idle';
  String _rxStatus = 'Idle';
  String? _decodedMessage;
  bool _isTxActive = false;
  bool _isRxActive = false;

  // DSP Tuning & Test Parameters
  double _amplitude = TuningConfig.amplitude;
  double _threshold = TuningConfig.preambleThreshold;
  double _symbolDuration = TuningConfig.symbolDurationMs;

  String _selectedDistance = '0.5m';
  String _selectedEnvironment = 'Quiet Room';
  final List<Stage6TestLog> _testLogs = [];

  final List<String> _distances = [
    '0.05m (Contact)',
    '0.25m',
    '0.5m',
    '1.0m',
    '1.5m',
    '2.0m',
    '3.0m',
  ];

  final List<String> _environments = [
    'Quiet Room',
    'Office / Low Noise',
    'Noisy / Background Music',
  ];

  @override
  void initState() {
    super.initState();
    _generateNewKey();
    _loadAssetHost();
    _syncTuningConfig();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _notesController.dispose();
    AudioTransmitter.dispose();
    AudioReceiver.dispose();
    super.dispose();
  }

  void _syncTuningConfig() {
    TuningConfig.amplitude = _amplitude;
    TuningConfig.preambleThreshold = _threshold;
    TuningConfig.symbolDurationMs = _symbolDuration;
  }

  void _generateNewKey() {
    _activeKey = WatermarkCrypto.generateKey();
    setState(() {
      _keyHex = WatermarkCrypto.keyToHex(_activeKey);
    });
  }

  Future<void> _scanQrKey() async {
    final scannedKey = await Navigator.push<enc.Key>(
      context,
      MaterialPageRoute(builder: (context) => const QrScanScreen()),
    );
    if (scannedKey != null && mounted) {
      setState(() {
        _activeKey = scannedKey;
        _keyHex = WatermarkCrypto.keyToHex(scannedKey);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AES-128 key successfully imported from QR scanner!'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  void _showManualHexDialog() {
    final textController = TextEditingController(text: _keyHex);
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E222A),
              title: const Text(
                'Manual Hex Key Entry',
                style: TextStyle(color: Colors.tealAccent, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter or paste a 32-character hexadecimal key:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF14171D),
                      hintText: '32 hex characters...',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent),
                  onPressed: () {
                    try {
                      final key = QrKeyExchange.qrPayloadToKey(textController.text);
                      Navigator.pop(dialogContext);
                      setState(() {
                        _activeKey = key;
                        _keyHex = WatermarkCrypto.keyToHex(key);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('AES key updated manually!')),
                      );
                    } catch (e) {
                      setDialogState(() {
                        errorText = 'Must be 32 valid hex characters';
                      });
                    }
                  },
                  child: const Text('Save Key', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadAssetHost() async {
    setState(() => _isLoadingAsset = true);
    try {
      final byteData = await rootBundle.load('assets/host_song.wav');
      final bytes = byteData.buffer.asUint8List();
      final wavData = WavUtils.readWavBytes(bytes);
      _assetHostSamples = wavData.samples;
    } catch (_) {
      _assetHostSamples = null;
    } finally {
      if (mounted) {
        setState(() => _isLoadingAsset = false);
      }
    }
  }

  List<double> _getHostSamples(double requiredSeconds) {
    switch (_hostMode) {
      case HostMode.assetWav:
        if (_assetHostSamples != null &&
            _assetHostSamples!.length >=
                (sampleRate * requiredSeconds).round()) {
          return _assetHostSamples!;
        }
        return _generateSyntheticHost(requiredSeconds + 3.0);

      case HostMode.syntheticMusic:
        return _generateSyntheticHost(requiredSeconds + 3.0);

      case HostMode.quiet:
        final count = (sampleRate * (requiredSeconds + 3.0)).round();
        return List<double>.filled(count, 0.0);
    }
  }

  List<double> _generateSyntheticHost(double durationSeconds) {
    final count = (sampleRate * durationSeconds).round();
    final samples = List<double>.filled(count, 0.0);
    final freqs = [261.63, 329.63, 392.00, 523.25]; // C major chord notes

    for (int i = 0; i < count; i++) {
      final t = i / sampleRate;
      double sum = 0.0;
      for (final f in freqs) {
        sum += 0.08 * sin(2 * pi * f * t);
      }
      samples[i] = sum;
    }
    return samples;
  }

  void _recordLog({required bool isSuccess, required String notes}) {
    final log = Stage6TestLog(
      timestamp: DateTime.now(),
      amplitude: _amplitude,
      threshold: _threshold,
      symbolDurationMs: _symbolDuration,
      distance: _selectedDistance,
      environment: _selectedEnvironment,
      messageLength: _messageController.text.trim().length,
      isSuccess: isSuccess,
      notes: notes.isEmpty
          ? (_notesController.text.trim().isEmpty ? '-' : _notesController.text.trim())
          : notes,
    );
    setState(() {
      _testLogs.insert(0, log);
    });
  }

  Future<void> _startTransmitting() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to transmit')),
      );
      return;
    }

    _syncTuningConfig();

    final ciphertextLength = message.length;
    final totalSymbols = 24 + 8 * ciphertextLength;
    final requiredSec = 0.3 + (totalSymbols * (_symbolDuration / 1000.0)) + 1.0;
    final host = _getHostSamples(requiredSec);

    setState(() {
      _isTxActive = true;
      _txStatus =
          'Preparing transmission (amp: ${_amplitude.toStringAsFixed(3)}, sym: ${_symbolDuration.toStringAsFixed(0)}ms)...';
    });

    await AudioTransmitter.transmit(
      message: message,
      key: _activeKey,
      hostSamples: host,
      onStatus: (status) {
        if (mounted) {
          setState(() => _txStatus = status);
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isTxActive = false;
            _txStatus = 'Playback finished.';
          });
        }
      },
    );
  }

  Future<void> _startListening() async {
    _syncTuningConfig();

    setState(() {
      _isRxActive = true;
      _rxStatus =
          'Listening (thresh: ${_threshold.toStringAsFixed(1)}, sym: ${_symbolDuration.toStringAsFixed(0)}ms)...';
      _decodedMessage = null;
    });

    await AudioReceiver.startListening(
      key: _activeKey,
      onStatus: (status) {
        if (mounted) {
          setState(() => _rxStatus = status);
        }
      },
      onResult: (result) {
        if (mounted) {
          final isSuccess = result != null && result.isNotEmpty;
          final isMatch = isSuccess && result == _messageController.text.trim();
          setState(() {
            _isRxActive = false;
            _decodedMessage = result;
            _rxStatus = isSuccess
                ? 'Message received!'
                : 'Listening stopped (no message).';
          });
          _recordLog(
            isSuccess: isMatch,
            notes: isMatch
                ? 'Decoded exact match'
                : (isSuccess
                    ? 'Decoded mismatch: $result'
                    : 'No preamble / payload detected'),
          );
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await AudioReceiver.stopListening();
  }

  Future<void> _runSimultaneousLoopbackTest() async {
    await _startListening();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted && _isRxActive) {
      await _startTransmitting();
    }
  }

  void _resetTuningToDefaults() {
    setState(() {
      _amplitude = watermarkAmplitude;
      _threshold = defaultPreambleThreshold;
      _symbolDuration = defaultSymbolDurationMs;
      _syncTuningConfig();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('DSP parameters reset to designed protocol defaults')),
    );
  }

  void _copyLogsToClipboard() {
    if (_testLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No test logs to copy')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
        '| Timestamp | Distance | Environment | Amplitude | Threshold | Symbol Duration | Msg Length | Result | Notes |');
    buffer.writeln(
        '| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
    for (final log in _testLogs.reversed) {
      buffer.writeln(log.toMarkdownTableRow());
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test results copied to clipboard as Markdown table')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage 7 — QR Key Exchange & Pipeline'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR Key',
            onPressed: _scanQrKey,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Hardware Calibration',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => const CalibrationScreen(),
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121418),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKeyCard(),
              const SizedBox(height: 14),
              _buildTuningPanel(),
              const SizedBox(height: 14),
              _buildTestEnvironmentCard(),
              const SizedBox(height: 14),
              _buildMessageInput(),
              const SizedBox(height: 14),
              _buildHostSelector(),
              const SizedBox(height: 16),
              _buildActionControls(),
              const SizedBox(height: 16),
              _buildStatusCard(),
              const SizedBox(height: 16),
              _buildResultCard(),
              const SizedBox(height: 16),
              _buildResultsLogSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyCard() {
    final qrPayload = QrKeyExchange.keyToQrPayload(_activeKey);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_2, size: 18, color: Colors.tealAccent),
                  SizedBox(width: 6),
                  Text(
                    'AES-128 Out-of-Band Key',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showQrCode ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                      color: Colors.white70,
                    ),
                    tooltip: _showQrCode ? 'Hide QR Code' : 'Show QR Code',
                    onPressed: () => setState(() => _showQrCode = !_showQrCode),
                  ),
                  TextButton.icon(
                    onPressed: _generateNewKey,
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.tealAccent),
                    label: const Text('New Key', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          // QR Code Display
          if (_showQrCode) ...[
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.tealAccent.withValues(alpha: 0.15),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 150.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const Center(
              child: Text(
                'Sender: Show this QR to receiver phone',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Hex Key Readout & Action Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF14171D),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _keyHex,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white60),
                  tooltip: 'Copy Hex',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _keyHex));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hex key copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Receiver Out-of-band Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _scanQrKey,
                  icon: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                  label: const Text('Scan QR Code', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showManualHexDialog,
                  icon: const Icon(Icons.edit, size: 16, color: Colors.white70),
                  label: const Text('Enter Hex', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTuningPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F29),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, size: 16, color: Colors.cyanAccent),
                  SizedBox(width: 6),
                  Text(
                    'Live DSP Tuning Parameters',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _resetTuningToDefaults,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text(
                  'Reset Defaults',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Amplitude Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Watermark Amplitude:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${_amplitude.toStringAsFixed(3)} (${(_amplitude == watermarkAmplitude) ? "Design Default" : "Tuned"})',
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: _amplitude,
            min: 0.005,
            max: 0.100,
            divisions: 19,
            activeColor: Colors.tealAccent,
            onChanged: (val) {
              setState(() {
                _amplitude = val;
                _syncTuningConfig();
              });
            },
          ),

          // Preamble Threshold Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Preamble Threshold:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${_threshold.toStringAsFixed(1)} (${(_threshold == defaultPreambleThreshold) ? "Design Default" : "Tuned"})',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: _threshold,
            min: 0.2,
            max: 5.0,
            divisions: 24,
            activeColor: Colors.amberAccent,
            onChanged: (val) {
              setState(() {
                _threshold = val;
                _syncTuningConfig();
              });
            },
          ),

          // Symbol Duration Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Symbol Duration:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${_symbolDuration.toStringAsFixed(0)} ms (${(_symbolDuration == defaultSymbolDurationMs) ? "Design Default" : "Tuned"})',
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Slider(
            value: _symbolDuration,
            min: 30.0,
            max: 200.0,
            divisions: 17,
            activeColor: Colors.lightGreenAccent,
            onChanged: (val) {
              setState(() {
                _symbolDuration = val;
                _syncTuningConfig();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTestEnvironmentCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Two-Device Test Setup',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDistance,
                  decoration: const InputDecoration(
                    labelText: 'Distance',
                    labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                    filled: true,
                    fillColor: Color(0xFF14171D),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  dropdownColor: const Color(0xFF1E222A),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: _distances.map((d) {
                    return DropdownMenuItem(value: d, child: Text(d));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedDistance = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedEnvironment,
                  decoration: const InputDecoration(
                    labelText: 'Environment',
                    labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                    filled: true,
                    fillColor: Color(0xFF14171D),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  dropdownColor: const Color(0xFF1E222A),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: _environments.map((e) {
                    return DropdownMenuItem(value: e, child: Text(e));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedEnvironment = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF14171D),
              hintText: 'Notes for this test run (optional)...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Message to Embed & Transmit',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF14171D),
              hintText: 'Enter secret text...',
              hintStyle: const TextStyle(color: Colors.white38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              _buildPresetChip('HI'),
              _buildPresetChip('SECRET_STAGE7_OK'),
              _buildPresetChip('Hello world through phone audio!'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      backgroundColor: const Color(0xFF2B313D),
      onPressed: () {
        setState(() {
          _messageController.text = text;
        });
      },
    );
  }

  Widget _buildHostSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Host Audio Carrier',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<HostMode>(
            segments: const [
              ButtonSegment<HostMode>(
                value: HostMode.assetWav,
                label: Text('Asset Song', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.music_note, size: 14),
              ),
              ButtonSegment<HostMode>(
                value: HostMode.syntheticMusic,
                label: Text('Synthesized', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.graphic_eq, size: 14),
              ),
              ButtonSegment<HostMode>(
                value: HostMode.quiet,
                label: Text('Quiet Host', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.volume_mute, size: 14),
              ),
            ],
            selected: {_hostMode},
            onSelectionChanged: (newSelection) {
              setState(() => _hostMode = newSelection.first);
            },
          ),
          if (_isLoadingAsset) ...[
            const SizedBox(height: 6),
            const Text(
              'Loading host WAV asset...',
              style: TextStyle(color: Colors.amberAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: (_isTxActive || _isRxActive) ? null : _runSimultaneousLoopbackTest,
          icon: const Icon(Icons.sync_alt, color: Colors.black),
          label: const Text(
            '★ Run Single-Device Loopback (Listen + Send)',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amberAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isTxActive ? null : _startTransmitting,
                icon: const Icon(Icons.volume_up, color: Colors.white),
                label: Text(_isTxActive ? 'Sending...' : 'Send (Speaker)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isRxActive ? _stopListening : _startListening,
                icon: Icon(
                  _isRxActive ? Icons.stop : Icons.mic,
                  color: Colors.white,
                ),
                label: Text(_isRxActive ? 'Stop Mic' : 'Listen (Mic)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isRxActive ? Colors.red.shade800 : Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.white70),
              SizedBox(width: 6),
              Text(
                'Live Pipeline Status',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Transmitter: $_txStatus',
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Receiver: $_rxStatus',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final hasResult = _decodedMessage != null;
    final isMatch =
        hasResult && _decodedMessage == _messageController.text.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasResult
              ? (isMatch ? Colors.greenAccent : Colors.orangeAccent)
              : Colors.white12,
          width: hasResult ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Decoded Message Result',
                style: TextStyle(
                  color: hasResult ? Colors.greenAccent : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (hasResult)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isMatch
                        ? Colors.green.shade900
                        : Colors.orange.shade900,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isMatch ? 'VERIFIED MATCH ✓' : 'PARTIAL / CORRUPTED',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF121418),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _decodedMessage ?? 'No message detected yet.',
              style: TextStyle(
                color: hasResult ? Colors.white : Colors.white38,
                fontSize: 14,
                fontWeight: hasResult ? FontWeight.w600 : FontWeight.normal,
                fontFamily: hasResult ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsLogSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    'Test Runs Log (${_testLogs.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18, color: Colors.tealAccent),
                    tooltip: 'Copy as Markdown Table',
                    onPressed: _copyLogsToClipboard,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
                    tooltip: 'Clear Logs',
                    onPressed: () => setState(() => _testLogs.clear()),
                  ),
                ],
              ),
            ],
          ),
          if (_testLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  'No test runs recorded yet.\nSend & receive messages to populate results log.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white30, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _testLogs.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12),
              itemBuilder: (context, index) {
                final item = _testLogs[index];
                final time =
                    '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.isSuccess ? 'PASS' : 'FAIL',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$time • ${item.distance} • ${item.environment}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Amp: ${item.amplitude.toStringAsFixed(3)} | Thresh: ${item.threshold.toStringAsFixed(1)} | Sym: ${item.symbolDurationMs.toStringAsFixed(0)}ms | Len: ${item.messageLength}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (item.notes.isNotEmpty && item.notes != '-') ...[
                              const SizedBox(height: 2),
                              Text(
                                item.notes,
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 10),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
