import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:audio_watermark/dsp/aes_crypto.dart';
import 'package:audio_watermark/dsp/decoder.dart';
import 'package:audio_watermark/dsp/tone_generator.dart';

void main() {
  group('ToneGenerator and Decoder', () {
    test('sine round-trip decodes a short bit pattern', () {
      const bits = [1, 0, 1, 1, 0, 0, 1, 0];
      final samples = ToneGenerator.bitsToSamples(bits);
      final preambleEnd = Decoder.findPreambleEnd(samples);

      expect(preambleEnd, isNotNull);
      expect(Decoder.readBits(samples.sublist(preambleEnd!), bits.length), equals(bits));
    });

    test('Goertzel clearly discriminates bit frequencies', () {
      final bit0Samples = ToneGenerator.generateSymbol(0);
      final bit1Samples = ToneGenerator.generateSymbol(1);

      final bit0AtZero = Decoder.goertzelMagnitude(bit0Samples, 0, 18000.0);
      final bit0AtOne = Decoder.goertzelMagnitude(bit0Samples, 0, 19500.0);
      final bit1AtOne = Decoder.goertzelMagnitude(bit1Samples, 0, 19500.0);
      final bit1AtZero = Decoder.goertzelMagnitude(bit1Samples, 0, 18000.0);

      expect(bit0AtZero, greaterThan(5 * bit0AtOne));
      expect(bit1AtOne, greaterThan(5 * bit1AtZero));
    });

    test('redundant length header round-trips cleanly', () {
      final payloadBits = ToneGenerator.bytesToBits([0x00, 0x12, 0xFF]);
      final samples = ToneGenerator.bitsToSamplesWithHeader(payloadBits);

      expect(Decoder.decodeLengthPrefixedBits(samples), equals(payloadBits));
    });

    test('majority vote repairs one corrupted header copy', () {
      final originalHeader = ToneGenerator.bytesToBits([37]);
      final corruptedHeader = [
        ...originalHeader,
        ...originalHeader,
        ...originalHeader,
      ];
      corruptedHeader[8 + 3] = 1 - corruptedHeader[8 + 3];

      expect(Decoder.majorityVoteHeader(corruptedHeader), equals(37));
    });

    test('byte and bit helpers round-trip zero and 0xFF bytes', () {
      for (final bytes in [
        [0x00, 0x01, 0x7F],
        [0xFF, 0x00, 0xA5, 0x80],
      ]) {
        expect(ToneGenerator.bitsToBytes(ToneGenerator.bytesToBits(bytes)), equals(bytes));
      }
    });

    test('crypto and tone mapping compose end to end', () {
      final key = WatermarkCrypto.generateKey();
      const plaintext = 'Stage 2 works';
      final ciphertext = WatermarkCrypto.encrypt(plaintext, key);
      final payloadBits = ToneGenerator.bytesToBits(ciphertext);
      final samples = ToneGenerator.bitsToSamplesWithHeader(payloadBits);
      final decodedBits = Decoder.decodeLengthPrefixedBits(samples);
      final decodedBytes = ToneGenerator.bitsToBytes(decodedBits);

      expect(
        WatermarkCrypto.decrypt(Uint8List.fromList(decodedBytes), key),
        equals(plaintext),
      );
    });
  });
}
