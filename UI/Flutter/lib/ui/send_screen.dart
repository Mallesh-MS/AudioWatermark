import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;

import 'package:dsp/watermark_engine.dart';

/// Screen for composing messages, embedding watermarks into host audio,
/// and transmitting over device speakers.
class SendScreen extends StatefulWidget {
  final Key activeKey;
  final VoidCallback onNavigateToKeyExchange;

  const SendScreen({
    super.key,
    required this.activeKey,
    required this.onNavigateToKeyExchange,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController _messageController =
      TextEditingController(text: 'SECRET_STAGE9_OK');

  bool _isTransmitting = false;
  String _statusText = 'Ready to transmit';
  String _carrierChoice = 'acoustic_breeze'; // 'acoustic_breeze' or 'synthetic'

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  double _estimateDurationSeconds(int messageLength) {
    // Preamble (0.3s) + Header (2.4s) + Payload (0.8s per char) + Padding (1.0s)
    return 0.3 + 2.4 + (0.8 * messageLength) + 1.0;
  }

  Future<void> _handleTransmit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to send')),
      );
      return;
    }

    setState(() {
      _isTransmitting = true;
      _statusText = 'Initializing transmission...';
    });

    await WatermarkEngine.sendMessage(
      message: message,
      key: widget.activeKey,
      hostSongPath: _carrierChoice == 'acoustic_breeze'
          ? 'assets/host_song.wav'
          : null,
      onStatus: (status) {
        if (mounted) {
          setState(() => _statusText = status);
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isTransmitting = false;
            _statusText = 'Transmission complete.';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hexPreview = widget.activeKey.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .take(4)
        .join();
    final msgLength = _messageController.text.length;
    final estimatedSec = _estimateDurationSeconds(msgLength);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active Key Info Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key, size: 16, color: Colors.tealAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Session Key: ${hexPreview.toUpperCase()}... (AES-128)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: widget.onNavigateToKeyExchange,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Change', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Message Input Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.edit_note, size: 18, color: Colors.white70),
                    SizedBox(width: 6),
                    Text(
                      'Message to Watermark',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _messageController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF14171D),
                    hintText: 'Enter secret text to embed into audio...',
                    hintStyle: const TextStyle(color: Colors.white30),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$msgLength characters (~${estimatedSec.toStringAsFixed(1)}s audio)',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        _buildPresetChip('HI'),
                        _buildPresetChip('MEET_AT_10PM'),
                        _buildPresetChip('SECRET_STAGE9_OK'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Carrier Audio Selector
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222A),
              borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'acoustic_breeze',
                      label: Text('Acoustic Breeze', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.music_note, size: 14),
                    ),
                    ButtonSegment<String>(
                      value: 'synthetic',
                      label: Text('Synthesizer', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.graphic_eq, size: 14),
                    ),
                  ],
                  selected: {_carrierChoice},
                  onSelectionChanged: (newSelection) {
                    setState(() => _carrierChoice = newSelection.first);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Button
          ElevatedButton.icon(
            onPressed: _isTransmitting ? null : _handleTransmit,
            icon: Icon(
              _isTransmitting ? Icons.hourglass_top : Icons.volume_up,
              color: Colors.black,
            ),
            label: Text(
              _isTransmitting ? 'Transmitting Audio...' : 'Transmit Watermark (Speaker)',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Live Transmission Status Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF171A21),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isTransmitting ? Colors.tealAccent.withValues(alpha: 0.5) : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                if (_isTransmitting)
                  const Padding(
                    padding: EdgeInsets.only(right: 12.0),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.tealAccent,
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 12.0),
                    child: Icon(Icons.info_outline, size: 18, color: Colors.white54),
                  ),
                Expanded(
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      color: _isTransmitting ? Colors.tealAccent : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      backgroundColor: const Color(0xFF2B313D),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        setState(() {
          _messageController.text = text;
        });
      },
    );
  }
}
