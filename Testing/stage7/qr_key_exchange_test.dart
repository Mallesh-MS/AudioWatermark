import 'package:test/test.dart';

import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/qr/qr_key_exchange.dart';

void main() {
  group('QrKeyExchange Unit Tests (Dart VM)', () {
    test('1. Round-trip: qrPayloadToKey(keyToQrPayload(key)) reproduces the same key bytes', () {
      for (int i = 0; i < 20; i++) {
        final originalKey = WatermarkCrypto.generateKey();
        final qrPayload = QrKeyExchange.keyToQrPayload(originalKey);

        expect(qrPayload.length, equals(32));
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(qrPayload), isTrue);

        final recoveredKey = QrKeyExchange.qrPayloadToKey(qrPayload);
        expect(recoveredKey.bytes, equals(originalKey.bytes));
        expect(recoveredKey.base64, equals(originalKey.base64));
      }
    });

    test('2. Malformed input: throws FormatException for too-short, too-long, and non-hex inputs', () {
      // Too short
      expect(
        () => QrKeyExchange.qrPayloadToKey(''),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef0123456789abcde'), // 31 chars
        throwsA(isA<FormatException>()),
      );

      // Too long
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef0123456789abcdef0'), // 33 chars
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef0123456789abcdef0123456789abcdef'),
        throwsA(isA<FormatException>()),
      );

      // Non-hex characters
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef0123456789abcdeg'), // 'g' is not hex
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef0123456789abcdeZ'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrKeyExchange.qrPayloadToKey('0123456789abcdef 123456789abcdef'), // space inside
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrKeyExchange.qrPayloadToKey('{"key":"0123456789abcdef0123456"}'), // JSON wrapper
        throwsA(isA<FormatException>()),
      );
    });

    test('3. Case insensitivity: scanning uppercase, lowercase, and mixed case yields identical key', () {
      const lowerHex = '00112233445566778899aabbccddeeff';
      const upperHex = '00112233445566778899AABBCCDDEEFF';
      const mixedHex = '00112233445566778899AaBbCcDdEeFf';

      final keyLower = QrKeyExchange.qrPayloadToKey(lowerHex);
      final keyUpper = QrKeyExchange.qrPayloadToKey(upperHex);
      final keyMixed = QrKeyExchange.qrPayloadToKey(mixedHex);

      expect(keyLower.bytes, equals(keyUpper.bytes));
      expect(keyLower.bytes, equals(keyMixed.bytes));
      expect(keyUpper.bytes, equals(keyMixed.bytes));
    });

    test('4. End-to-end integration: message encrypted with sender key decrypts with QR-scanned receiver key', () {
      final senderKey = WatermarkCrypto.generateKey();
      final qrString = QrKeyExchange.keyToQrPayload(senderKey);

      final receiverKey = QrKeyExchange.qrPayloadToKey(qrString);

      const secretText = 'TOP_SECRET_QR_WATERMARK';
      final encrypted = WatermarkCrypto.encrypt(secretText, senderKey);
      final decrypted = WatermarkCrypto.decrypt(encrypted, receiverKey);

      expect(decrypted, equals(secretText));
    });
  });
}
