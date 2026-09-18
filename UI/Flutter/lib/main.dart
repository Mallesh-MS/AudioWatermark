import 'package:flutter/material.dart';
import 'ui/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudioWatermarkApp());
}

class AudioWatermarkApp extends StatelessWidget {
  const AudioWatermarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Watermark Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121418),
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.amberAccent,
          surface: Color(0xFF1E222A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF14171D),
          elevation: 0,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}
