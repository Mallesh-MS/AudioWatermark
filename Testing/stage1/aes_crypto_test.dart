import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:audio_watermark/dsp/aes_crypto.dart';

void main() {
  group('AES crypto core', () {
    test('generateKey creates a secure 128-bit key', () {
      final key1 = generateKey();
      final key2 = generateKey();

      expect(key1.length, equals(16));
      expect(key2.length, equals(16));
      expect(key1, isNot(equals(key2)));
    });

    test('encrypt/decrypt round-trips multiple message lengths', () {
      final key = generateKey();
      const messages = [
        '',
        'A',
        'hello',
        'This is a medium message.',
        'This is a longer message meant to verify the no-padding, fixed-IV CTR behavior across more than a single block of AES data.',
        'A slightly longer payload with emojis 🚀 and accented text: café, mañana, naïve.',
      ];

      for (final plaintext in messages) {
        final ciphertext = encrypt(plaintext, key);
        final decoded = decrypt(ciphertext, key);

        expect(ciphertext.length, equals(utf8.encode(plaintext).length));
        expect(decoded, equals(plaintext));
      }
    });

    test('wrong key fails cleanly instead of silently succeeding', () {
      final keyA = generateKey();
      final keyB = generateKey();
      const plaintext = 'Top secret message for testing';
      final ciphertext = encrypt(plaintext, keyA);

      expect(() => decrypt(ciphertext, keyB), throwsA(isA<FormatException>()));
    });
  });
}
