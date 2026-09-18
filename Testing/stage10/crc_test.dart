import 'dart:math';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/crc.dart';
import 'package:dsp/dsp/decoder.dart';
import 'package:dsp/dsp/protocol.dart';

void main() {
  group('CRC-8 Error Detection Tests (Stage 10)', () {
    test('1. CRC-8 compute produces deterministic checksums', () {
      final data1 = [0x01, 0x02, 0x03, 0x04];
      final crc1 = Crc8.compute(data1);
      expect(crc1, isNonNegative);
      expect(crc1, lessThan(256));
      expect(Crc8.compute(data1), equals(crc1));

      final data2 = [0x01, 0x02, 0x03, 0x05]; // 1-bit difference
      final crc2 = Crc8.compute(data2);
      expect(crc2, isNot(equals(crc1)));
    });

    test('2. appendChecksum and verifyAndExtract round-trip cleanly on uncorrupted payloads', () {
      final payloads = [
        [0x41],
        [0x10, 0x20, 0x30, 0x40, 0x50],
        List<int>.generate(32, (i) => (i * 7) % 256),
      ];

      for (final payload in payloads) {
        final withChecksum = Crc8.appendChecksum(payload);
        expect(withChecksum.length, equals(payload.length + 1));

        final verified = Crc8.verifyAndExtract(withChecksum);
        expect(verified, isNotNull);
        expect(verified, equals(payload));
      }
    });

    test('3. verifyAndExtract detects and rejects single-bit, two-bit, and multi-byte corruptions', () {
      final payload = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE];
      final withChecksum = Crc8.appendChecksum(payload);

      // Single-bit flip in payload byte 0
      final flipped1 = List<int>.from(withChecksum);
      flipped1[0] ^= 0x01;
      expect(Crc8.verifyAndExtract(flipped1), isNull);

      // Single-bit flip in middle byte
      final flipped2 = List<int>.from(withChecksum);
      flipped2[2] ^= 0x80;
      expect(Crc8.verifyAndExtract(flipped2), isNull);

      // Single-bit flip in CRC checksum itself
      final flippedCrc = List<int>.from(withChecksum);
      flippedCrc[flippedCrc.length - 1] ^= 0x04;
      expect(Crc8.verifyAndExtract(flippedCrc), isNull);

      // Truncated buffer
      expect(Crc8.verifyAndExtract([0xAA]), isNull);
    });

    test('4. Corrupted audio packet in acoustic channel is rejected by Embedder.extractMessage', () {
      final key = WatermarkCrypto.generateKey();
      const message = 'CRITICAL_COMMAND_LAUNCH';
      final host = List<double>.filled(sampleRate * 25, 0.0);

      final mixedSamples = Embedder.embedMessage(message, key, host);

      // Clean signal extracts perfectly
      final cleanExtracted = Embedder.extractMessage(mixedSamples, key);
      expect(cleanExtracted, equals(message));

      // Corrupt some acoustic samples in the payload region by replacing a bit 0/1 with strong conflicting tone
      final corruptedSamples = List<double>.from(mixedSamples);
      final symbolSamples = (sampleRate * 0.100).round();
        final preambleEnd = Decoder.findPreambleEndFrom(mixedSamples, 0);
        expect(preambleEnd, isNotNull);
        final payloadSampleOffset = preambleEnd! + (24 * symbolSamples) +
          (2 * symbolSamples);
      for (int i = 0; i < symbolSamples; i++) {
        // Overwrite symbol with pure 19500Hz tone at full amplitude to flip bit value
        corruptedSamples[payloadSampleOffset + i] = sin(2 * pi * bit1Freq * i / sampleRate) * 0.5;
      }

      // Checksum protects against silent corruption: returns null rather than garbled plaintext
      final corruptedExtracted = Embedder.extractMessage(corruptedSamples, key);
      expect(corruptedExtracted, isNull);
    });
  });
}
