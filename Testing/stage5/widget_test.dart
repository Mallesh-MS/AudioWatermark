import 'package:audio_watermark/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AudioWatermarkApp loads PipelineTestScreen smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AudioWatermarkApp());
    expect(find.text('Stage 5 — Acoustic Pipeline'), findsOneWidget);
    expect(find.text('AES-128 Shared Key (Hex)'), findsOneWidget);
    expect(find.text('Message to Embed & Transmit'), findsOneWidget);
    expect(find.text('★ Run Single-Device Loopback (Listen + Send)'), findsOneWidget);
  });
}
