import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;

import '../calibration_screen.dart';
import '../pipeline_test_screen.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'key_exchange_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Main production navigation shell integrating Send, Receive, and QR Key Exchange.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late Key _activeKey;

  @override
  void initState() {
    super.initState();
    _activeKey = WatermarkCrypto.generateKey();
  }

  void _updateKey(Key newKey) {
    setState(() {
      _activeKey = newKey;
    });
  }

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hexPreview = _activeKey.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .take(3)
        .join();

    final screens = [
      SendScreen(
        activeKey: _activeKey,
        onNavigateToKeyExchange: () => _navigateToTab(2),
      ),
      ReceiveScreen(
        activeKey: _activeKey,
        onNavigateToKeyExchange: () => _navigateToTab(2),
      ),
      KeyExchangeScreen(
        activeKey: _activeKey,
        onKeyChanged: _updateKey,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.graphic_eq, color: Colors.tealAccent, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Watermark',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Encrypted Acoustic Messenger',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF14171D),
        elevation: 0,
        actions: [
          // Active Key Pill Shortcut
          ActionChip(
            avatar: const Icon(Icons.vpn_key, size: 14, color: Colors.tealAccent),
            label: Text(
              '${hexPreview.toUpperCase()}...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.tealAccent,
              ),
            ),
            backgroundColor: const Color(0xFF1E222A),
            side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.3)),
            onPressed: () => _navigateToTab(2),
          ),
          const SizedBox(width: 4),

          // Diagnostic / Debug menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            tooltip: 'Diagnostic Tools',
            color: const Color(0xFF1E222A),
            onSelected: (val) {
              if (val == 'pipeline') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => const PipelineTestScreen(),
                  ),
                );
              } else if (val == 'calibration') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => const CalibrationScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pipeline',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18, color: Colors.cyanAccent),
                    SizedBox(width: 8),
                    Text('Pipeline Debug & Tuning', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'calibration',
                child: Row(
                  children: [
                    Icon(Icons.settings_input_antenna, size: 18, color: Colors.amberAccent),
                    SizedBox(width: 8),
                    Text('Hardware Audio Calibration', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121418),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: const Color(0xFF14171D),
        indicatorColor: Colors.tealAccent.withValues(alpha: 0.2),
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.send_outlined, color: Colors.white54),
            selectedIcon: Icon(Icons.send, color: Colors.tealAccent),
            label: 'Transmit',
          ),
          NavigationDestination(
            icon: Icon(Icons.hearing_outlined, color: Colors.white54),
            selectedIcon: Icon(Icons.hearing, color: Colors.tealAccent),
            label: 'Receive',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined, color: Colors.white54),
            selectedIcon: Icon(Icons.qr_code_2, color: Colors.tealAccent),
            label: 'QR Keys',
          ),
        ],
      ),
    );
  }
}
