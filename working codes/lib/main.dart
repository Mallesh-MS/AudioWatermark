import 'package:flutter/material.dart';
import 'audio/pipeline_test_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudioWatermarkApp());
}

class AudioWatermarkApp extends StatelessWidget {
  const AudioWatermarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Watermark Pipeline Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121418),
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.amberAccent,
        ),
      ),
      home: const PipelineTestScreen(),
    );
  }
}
