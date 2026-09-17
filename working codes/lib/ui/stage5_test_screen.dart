import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/audio_receiver.dart';
import '../audio/audio_transmitter.dart';
import '../dsp/aes_crypto.dart';
import '../dsp/pipeline.dart';
import '../dsp/wav_utils.dart';

class Stage5TestScreen extends StatefulWidget {
  const Stage5TestScreen({super.key});

  @override
  State<Stage5TestScreen> createState() => _Stage5TestScreenState();
}

class _Stage5TestScreenState extends State<Stage5TestScreen> {
  static const _message = 'STAGE5_SINGLE_PHONE_OK';

  late final Uint8List _key;
  List<double>? _hostSamples;
  bool _isListening = false;
  bool _isSending = false;
  String _status = 'Load the host audio, then start listening first.';
  String? _decodedMessage;

  @override
  void initState() {
    super.initState();
    _key = generateKey();
    _loadHostAudio();
  }

  @override
  void dispose() {
    AudioReceiver.dispose();
    AudioTransmitter.dispose();
    super.dispose();
  }

  Future<void> _loadHostAudio() async {
    try {
      final data = await rootBundle.load('assets/host_song.wav');
      final wav = readWavBytes(data.buffer.asUint8List());
      if (!mounted) return;
      setState(() {
        _hostSamples = wav.samples;
        _status = 'Host WAV loaded. Start listening before sending.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Could not load host WAV: $error');
    }
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    setState(() {
      _isListening = true;
      _decodedMessage = null;
      _status = 'Starting microphone...';
    });

    await AudioReceiver.startListening(
      _key,
      (result) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _decodedMessage = result;
          _status = result == null
              ? 'No message detected.'
              : 'Message decoded successfully.';
        });
      },
      onStatus: (status) {
        if (mounted) setState(() => _status = status);
      },
    );
  }

  Future<void> _sendTestMessage() async {
    final hostSamples = _hostSamples;
    if (hostSamples == null || _isSending) return;

    setState(() {
      _isSending = true;
      _status = 'Encrypting and embedding test message...';
    });

    try {
      final mixedSamples = transmitMessage(_message, _key, hostSamples);
      await AudioTransmitter.transmit(
        mixedSamples,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (mounted) setState(() => _status = 'Playback done. Waiting for decode.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Transmission error: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _stopListening() async {
    await AudioReceiver.stopListening();
    if (mounted) {
      setState(() {
        _isListening = false;
        _status = 'Listening stopped. No message detected.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stage 5 - Single Phone Test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Speaker-to-own-microphone pipeline',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This diagnostic uses the Stage 3 encrypt, embed, decode, and decrypt pipeline with real phone audio hardware.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isListening ? _stopListening : _startListening,
              icon: Icon(_isListening ? Icons.stop : Icons.mic),
              label: Text(_isListening ? 'Stop Listening' : 'Start Listening'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _hostSamples == null || _isSending
                  ? null
                  : _sendTestMessage,
              icon: const Icon(Icons.send),
              label: Text(_isSending ? 'Sending...' : 'Send Test Message'),
            ),
            const SizedBox(height: 16),
            const Text('Test message: $_message'),
            const SizedBox(height: 8),
            Text(_status),
            if (_decodedMessage != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Decoded result',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(_decodedMessage!),
            ],
          ],
        ),
      ),
    );
  }
}
