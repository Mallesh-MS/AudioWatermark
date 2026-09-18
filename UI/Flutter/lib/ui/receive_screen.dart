import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'package:dsp/watermark_engine.dart';

/// Screen for recording microphone audio, detecting watermarks,
/// and displaying decrypted payloads.
class ReceiveScreen extends StatefulWidget {
  final Key activeKey;
  final VoidCallback onNavigateToKeyExchange;

  const ReceiveScreen({
    super.key,
    required this.activeKey,
    required this.onNavigateToKeyExchange,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool _isListening = false;
  String _statusMessage = 'Tap Listen to scan for incoming watermark signals';
  String? _decodedMessage;
  bool _hadError = false;

  final List<String> _receivedHistory = [];

  @override
  void dispose() {
    WatermarkEngine.stopListening();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await WatermarkEngine.stopListening();
      setState(() {
        _isListening = false;
        _statusMessage = 'Listening stopped manually.';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _decodedMessage = null;
      _hadError = false;
      _statusMessage = 'Listening on microphone for 17–19.5 kHz watermark...';
    });

    await WatermarkEngine.startListening(
      key: widget.activeKey,
      onStatus: (status) {
        if (mounted) {
          setState(() => _statusMessage = status);
        }
      },
      onResult: (result) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _decodedMessage = result;
            if (result != null && result.isNotEmpty) {
              _statusMessage = 'Watermark signal successfully decoded!';
              _hadError = false;
              if (!_receivedHistory.contains(result)) {
                _receivedHistory.insert(0, result);
              }
            } else {
              _statusMessage = 'Listening ended. No valid watermark detected.';
              _hadError = true;
            }
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active Key Status Bar
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
                    const Icon(Icons.lock, size: 16, color: Colors.tealAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Decrypt Key: ${hexPreview.toUpperCase()}... (AES-128)',
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
                  child: const Text('Sync QR', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Main Listening Visual Card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isListening ? Colors.tealAccent : Colors.white12,
                width: _isListening ? 2 : 1,
              ),
              boxShadow: _isListening
                  ? [
                      BoxShadow(
                        color: Colors.tealAccent.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                // Pulse Animation / Icon
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening
                        ? Colors.tealAccent.withValues(alpha: 0.15)
                        : const Color(0xFF14171D),
                    border: Border.all(
                      color: _isListening ? Colors.tealAccent : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isListening ? Icons.graphic_eq : Icons.mic,
                    size: 44,
                    color: _isListening ? Colors.tealAccent : Colors.white60,
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  _isListening ? 'LISTENING FOR WATERMARK...' : 'RECEIVER READY',
                  style: TextStyle(
                    color: _isListening ? Colors.tealAccent : Colors.white70,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isListening ? Colors.white : Colors.white54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),

                // Big Action Button
                ElevatedButton.icon(
                  onPressed: _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                  ),
                  label: Text(
                    _isListening ? 'Stop Listening' : 'Start Listening (Mic)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListening
                        ? Colors.red.shade800
                        : Colors.teal.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Decoded Result Banner
          if (_decodedMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2A22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: Colors.greenAccent),
                          SizedBox(width: 8),
                          Text(
                            'Decrypted Message',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: Colors.greenAccent),
                        tooltip: 'Copy Message',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _decodedMessage!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Message copied to clipboard')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101C16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _decodedMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (_hadError) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1C1C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No watermark detected. Ensure speaker is facing mic within 1 meter and keys match.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // History of received messages in session
          if (_receivedHistory.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Session Message History',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _receivedHistory.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final item = _receivedHistory[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_right, size: 16, color: Colors.tealAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
