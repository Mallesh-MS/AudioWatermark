import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/embedder.dart';
import '../audio/audio_receiver.dart';
import '../audio/audio_transmitter.dart';
import '../audio/calibration_screen.dart';
import '../audio/wav_utils.dart';
import '../dsp/aes_crypto.dart';
import '../dsp/protocol.dart';

class PipelineTestScreen extends StatefulWidget {
  const PipelineTestScreen({super.key});

  @override
  State<PipelineTestScreen> createState() => _PipelineTestScreenState();
}

enum HostMode { assetWav, syntheticMusic, quiet }

class _PipelineTestScreenState extends State<PipelineTestScreen> {
  final TextEditingController _messageController =
      TextEditingController(text: 'SECRET_STAGE5_OK');

  late enc.Key _activeKey;
  String _keyHex = '';

  HostMode _hostMode = HostMode.assetWav;
  List<double>? _assetHostSamples;
  bool _isLoadingAsset = false;

  String _txStatus = 'Idle';
  String _rxStatus = 'Idle';
  String? _decodedMessage;
  bool _isTxActive = false;
  bool _isRxActive = false;

  @override
  void initState() {
    super.initState();
    _generateNewKey();
    _loadAssetHost();
  }

  @override
  void dispose() {
    _messageController.dispose();
    AudioTransmitter.dispose();
    AudioReceiver.dispose();
    super.dispose();
  }

  void _generateNewKey() {
    _activeKey = WatermarkCrypto.generateKey();
    setState(() {
      _keyHex = WatermarkCrypto.keyToHex(_activeKey);
    });
  }

  Future<void> _loadAssetHost() async {
    setState(() => _isLoadingAsset = true);
    try {
      final byteData = await rootBundle.load('assets/host_song.wav');
      final bytes = byteData.buffer.asUint8List();
      final wavData = WavUtils.readWavBytes(bytes);
      _assetHostSamples = wavData.samples;
    } catch (_) {
      // Fall back if asset bundle is not available
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
            _assetHostSamples!.length >= (sampleRate * requiredSeconds).round()) {
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

  Future<void> _startTransmitting() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to transmit')),
      );
      return;
    }

    // Calculate required duration: T = 2.7 + 0.8 * L
    final ciphertextLength = message.length; // AES-CTR preserved length
    final requiredSec = 2.7 + 0.8 * ciphertextLength;
    final host = _getHostSamples(requiredSec);

    setState(() {
      _isTxActive = true;
      _txStatus = 'Preparing transmission...';
    });

    final mixedSamples = Embedder.embedMessage(message, _activeKey, host);
    await AudioTransmitter.transmit(
      mixedSamples,
      onStatus: (status) {
        if (mounted) {
          setState(() => _txStatus = status);
        }
      },
    );
    if (mounted) {
      setState(() {
        _isTxActive = false;
        _txStatus = 'Playback finished.';
      });
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _isRxActive = true;
      _rxStatus = 'Listening for signal...';
      _decodedMessage = null;
    });

    await AudioReceiver.startListening(
      Uint8List.fromList(_activeKey.bytes),
      (result) {
        if (mounted) {
          setState(() {
            _isRxActive = false;
            _decodedMessage = result;
            _rxStatus = result != null
                ? 'Message received!'
                : 'Listening stopped (no message).';
          });
        }
      },
      onStatus: (status) {
        if (mounted) {
          setState(() => _rxStatus = status);
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await AudioReceiver.stopListening();
  }

  Future<void> _runSimultaneousLoopbackTest() async {
    // 1. Start listening on mic first
    await _startListening();
    // 2. Wait 400ms then start transmitting from speaker
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted && _isRxActive) {
      await _startTransmitting();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage 5 — Acoustic Pipeline'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
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
              _buildMessageInput(),
              const SizedBox(height: 14),
              _buildHostSelector(),
              const SizedBox(height: 16),
              _buildActionControls(),
              const SizedBox(height: 16),
              _buildStatusCard(),
              const SizedBox(height: 16),
              _buildResultCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyCard() {
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
              const Text(
                'AES-128 Shared Key (Hex)',
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              TextButton.icon(
                onPressed: _generateNewKey,
                icon: const Icon(Icons.refresh, size: 16, color: Colors.tealAccent),
                label: const Text('New Key', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
              ),
            ],
          ),
          SelectableText(
            _keyHex,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
              letterSpacing: 1.1,
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
              _buildPresetChip('SECRET_STAGE5_OK'),
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
}
