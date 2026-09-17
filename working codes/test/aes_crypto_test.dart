import 'dart:convert';

import 'package:test/test.dart';

import 'package:audio_watermark/dsp/aes_crypto.dart';

void main() {
  group('WatermarkCrypto', () {
    test('generates secure 16-byte keys', () {
      final key1 = WatermarkCrypto.generateKey();
      final key2 = WatermarkCrypto.generateKey();
      expect(key1.bytes.length, equals(16));
      expect(key2.bytes.length, equals(16));
      expect(key1.bytes, isNot(equals(key2.bytes)));
    });

    test('round-trips multiple plaintext lengths', () {
      final key = WatermarkCrypto.generateKey();
      const plaintexts = [
        '',
        'A',
        'HI',
        'Hello, watermark!',
        'This is a longer paragraph to test encryption and decryption with a larger amount of data. It should maintain the exact same length for ciphertext as the UTF-8 encoded plaintext bytes.',
      ];

      for (final plaintext in plaintexts) {
        final ciphertext = WatermarkCrypto.encrypt(plaintext, key);
        expect(WatermarkCrypto.decrypt(ciphertext, key), equals(plaintext));
        expect(ciphertext.length, equals(utf8.encode(plaintext).length));
      }
    });

    test('ciphertext length equals UTF-8 byte length', () {
      final key = WatermarkCrypto.generateKey();
      const plaintexts = ['', 'A', 'HI', 'Hello, world!', '🎵', 'Hello 🎵 world'];

      for (final plaintext in plaintexts) {
        final ciphertext = WatermarkCrypto.encrypt(plaintext, key);
        expect(ciphertext.length, equals(utf8.encode(plaintext).length));
      }
    });

    test('wrong key fails cleanly', () {
      final keyA = WatermarkCrypto.generateKey();
      final keyB = WatermarkCrypto.generateKey();
      const plaintext = 'Secret message for testing';
      final ciphertext = WatermarkCrypto.encrypt(plaintext, keyA);

      try {
        expect(WatermarkCrypto.decrypt(ciphertext, keyB), isNot(equals(plaintext)));
      } on FormatException {
        // Invalid UTF-8 is a clean failure for a wrong key.
      }
    });

    test('same plaintext and key produce deterministic ciphertext', () {
      final key = WatermarkCrypto.generateKey();
      const plaintext = 'Deterministic test message';
      expect(
        WatermarkCrypto.encrypt(plaintext, key),
        equals(WatermarkCrypto.encrypt(plaintext, key)),
      );
    });

    test('hex conversion round-trips key bytes', () {
      final key = WatermarkCrypto.generateKey();
      final hex = WatermarkCrypto.keyToHex(key);
      expect(hex.length, equals(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hex), isTrue);
      expect(WatermarkCrypto.keyFromHex(hex).bytes, equals(key.bytes));
    });

    test('invalid hex length throws', () {
      expect(() => WatermarkCrypto.keyFromHex('abc'), throwsA(isA<ArgumentError>()));
      expect(() => WatermarkCrypto.keyFromHex('0' * 30), throwsA(isA<ArgumentError>()));
      expect(() => WatermarkCrypto.keyFromHex('0' * 34), throwsA(isA<ArgumentError>()));
    });
  });
}
