import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import '../qr_scan_screen.dart';
import 'package:dsp/watermark_engine.dart';

/// Screen for generating, presenting, and scanning out-of-band AES-128 QR session keys.
class KeyExchangeScreen extends StatefulWidget {
  final Key activeKey;
  final ValueChanged<Key> onKeyChanged;

  const KeyExchangeScreen({
    super.key,
    required this.activeKey,
    required this.onKeyChanged,
  });

  @override
  State<KeyExchangeScreen> createState() => _KeyExchangeScreenState();
}

class _KeyExchangeScreenState extends State<KeyExchangeScreen> {
  late Key _currentKey;
  late Widget _currentQrWidget;
  bool _isTransmitterMode = true;

  @override
  void initState() {
    super.initState();
    _currentKey = widget.activeKey;
    _currentQrWidget = WatermarkEngine.buildQrWidget(_currentKey, size: 200.0);
  }

  @override
  void didUpdateWidget(covariant KeyExchangeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeKey.bytes != widget.activeKey.bytes) {
      setState(() {
        _currentKey = widget.activeKey;
        _currentQrWidget = WatermarkEngine.buildQrWidget(_currentKey, size: 200.0);
      });
    }
  }

  void _generateNewKey() {
    final session = WatermarkEngine.generateAndShowKey(size: 200.0);
    setState(() {
      _currentKey = session.key;
      _currentQrWidget = session.qrWidget;
    });
    widget.onKeyChanged(_currentKey);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New AES-128 session key generated!'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  Future<void> _scanPeerQrKey() async {
    final scannedKey = await Navigator.push<Key>(
      context,
      MaterialPageRoute(builder: (context) => const QrScanScreen()),
    );
    if (scannedKey != null && mounted) {
      setState(() {
        _currentKey = scannedKey;
        _currentQrWidget = WatermarkEngine.buildQrWidget(scannedKey, size: 200.0);
      });
      widget.onKeyChanged(scannedKey);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AES-128 key successfully synced from QR scanner!'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  void _showManualEntryDialog() {
    final hexString = _currentKey.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final textController = TextEditingController(text: hexString);
    String? errorMessage;

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
                    'Paste or type 32-character hexadecimal key:',
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
                      fillColor: const Color(0xFF121418),
                      hintText: '32 hex characters...',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      errorText: errorMessage,
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
                      final key = WatermarkEngine.scanQrResult(textController.text);
                      Navigator.pop(dialogContext);
                      setState(() {
                        _currentKey = key;
                        _currentQrWidget = WatermarkEngine.buildQrWidget(key, size: 200.0);
                      });
                      widget.onKeyChanged(key);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('AES key updated manually!')),
                      );
                    } catch (e) {
                      setDialogState(() {
                        errorMessage = 'Must be 32 valid hex characters';
                      });
                    }
                  },
                  child: const Text('Apply Key', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hexString = _currentKey.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode Toggle
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: true,
                label: Text('Transmitter (Show QR)'),
                icon: Icon(Icons.qr_code_2, size: 16),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text('Receiver (Scan QR)'),
                icon: Icon(Icons.qr_code_scanner, size: 16),
              ),
            ],
            selected: {_isTransmitterMode},
            onSelectionChanged: (val) {
              setState(() => _isTransmitterMode = val.first);
            },
          ),
          const SizedBox(height: 16),

          if (_isTransmitterMode) ...[
            // Transmitter QR Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Present QR Code to Receiver',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Point the receiver phone camera at this code to pair keys.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.tealAccent.withValues(alpha: 0.2),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _currentQrWidget,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _generateNewKey,
                    icon: const Icon(Icons.refresh, color: Colors.black),
                    label: const Text(
                      'Generate New Session Key',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Receiver Scan Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.camera_enhance, size: 48, color: Colors.amberAccent),
                  const SizedBox(height: 12),
                  const Text(
                    'Scan Transmitter Key',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Scan the QR code shown on the sender device to establish shared encryption key.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _scanPeerQrKey,
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.black),
                    label: const Text(
                      'Launch Camera Scanner',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Active Key Info & Fallback Actions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF171A21),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Active Key (Hex Fallback)',
                      style: TextStyle(
                        color: Colors.tealAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showManualEntryDialog,
                      icon: const Icon(Icons.edit, size: 14, color: Colors.tealAccent),
                      label: const Text('Manual Entry', style: TextStyle(color: Colors.tealAccent, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101216),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          hexString,
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
                          Clipboard.setData(ClipboardData(text: hexString));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Key copied to clipboard')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
