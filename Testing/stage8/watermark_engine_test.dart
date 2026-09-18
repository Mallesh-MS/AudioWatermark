import 'package:test/test.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/qr/qr_key_exchange.dart';
import 'package:dsp/watermark_engine.dart';

void main() {
  group('WatermarkEngine Public Interface Tests (Plain Dart VM)', () {
    test('1. generateAndShowKey produces a valid 16-byte key and QR widget', () {
      final session = WatermarkEngine.generateAndShowKey(size: 200.0);

      expect(session.key.bytes.length, equals(16));
      expect(session.qrWidget, isNotNull);

      final qrHex = QrKeyExchange.keyToQrPayload(session.key);
      expect(qrHex.length, equals(32));

      final scannedKey = WatermarkEngine.scanQrResult(qrHex);
      expect(scannedKey.bytes, equals(session.key.bytes));
    });

    test('2. scanQrResult round-trips correctly and tryScanQrResult handles valid keys', () {
      for (int i = 0; i < 10; i++) {
        final key = WatermarkCrypto.generateKey();
        final qrPayload = QrKeyExchange.keyToQrPayload(key);

        final parsedKey = WatermarkEngine.scanQrResult(qrPayload);
        expect(parsedKey.bytes, equals(key.bytes));

        final tryParsedKey = WatermarkEngine.tryScanQrResult(qrPayload);
        expect(tryParsedKey, isNotNull);
        expect(tryParsedKey!.bytes, equals(key.bytes));
      }
    });

    test('3. Malformed QR inputs throw FormatException on scanQrResult and return null on tryScanQrResult', () {
      const invalidInputs = [
        '',
        'short',
        '1234567890abcdef1234567890abcde', // 31 chars
        '1234567890abcdef1234567890abcdef0', // 33 chars
        '1234567890abcdef1234567890abcdez', // non-hex
        '{"key":"1234567890abcdef123456"}',
      ];

      for (final input in invalidInputs) {
        expect(
          () => WatermarkEngine.scanQrResult(input),
          throwsA(isA<FormatException>()),
          reason: 'Should throw FormatException on "$input"',
        );

        expect(
          WatermarkEngine.tryScanQrResult(input),
          isNull,
          reason: 'tryScanQrResult should return null on "$input"',
        );
      }
    });

    test('4. buildQrWidget generates a widget for an existing key', () {
      final key = WatermarkCrypto.generateKey();
      final widget = WatermarkEngine.buildQrWidget(key, size: 150.0);
      expect(widget, isNotNull);
    });

    test('5. sendMessage with empty message fails cleanly without throwing', () async {
      final key = WatermarkCrypto.generateKey();
      var statusReceived = '';
      var doneCalled = false;

      await WatermarkEngine.sendMessage(
        message: '   ',
        key: key,
        onStatus: (status) => statusReceived = status,
        onDone: () => doneCalled = true,
      );

      expect(statusReceived, contains('Cannot transmit empty message'));
      expect(doneCalled, isTrue);
    });
  });
}
