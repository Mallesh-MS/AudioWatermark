import 'package:audio_watermark/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AudioWatermarkApp loads MainNavigationScreen and navigates tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AudioWatermarkApp());
    await tester.pumpAndSettle();

    // 1. Verify Home App Bar & Transmit Tab
    expect(find.text('Audio Watermark'), findsOneWidget);
    expect(find.text('Message to Watermark'), findsOneWidget);
    expect(find.text('Transmit Watermark (Speaker)'), findsOneWidget);

    // 2. Tap Receive Tab
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();

    expect(find.text('RECEIVER READY'), findsOneWidget);
    expect(find.text('Start Listening (Mic)'), findsOneWidget);

    // 3. Tap QR Keys Tab
    await tester.tap(find.text('QR Keys'));
    await tester.pumpAndSettle();

    expect(find.text('Present QR Code to Receiver'), findsOneWidget);
    expect(find.text('Generate New Session Key'), findsOneWidget);

    // 4. Switch to QR Scanner view
    await tester.tap(find.text('Receiver (Scan QR)'));
    await tester.pumpAndSettle();

    expect(find.text('Launch Camera Scanner'), findsOneWidget);
  });
}
