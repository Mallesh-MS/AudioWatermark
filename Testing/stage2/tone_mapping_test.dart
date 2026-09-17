import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:audio_watermark/dsp/goertzel_decoder.dart';
import 'package:audio_watermark/dsp/tone_generator.dart';

void main() {
  group('Stage 2 tone mapping', () {
    test('bitsToTones round-trips through decodeBit', () {
      final bits = [0, 1, 1, 0, 1, 0, 0, 1];
      final tones = bitsToTones(bits);
      final symbolSamples = (0.1 * 44100).round();

      expect(tones.length, equals(bits.length * symbolSamples));

      for (int i = 0; i < bits.length; i++) {
        final window = tones.sublist(i * symbolSamples, (i + 1) * symbolSamples);
        expect(decodeBit(window), equals(bits[i]));
      }
    });

    test('full frame round-trip works for several payload lengths', () {
      final payloadSets = [
        [0, 1, 0, 1, 1, 0, 1, 0],
        List<int>.generate(32, (index) => index % 2),
        List<int>.generate(64, (index) => (index * 7) % 2),
      ];

      for (final payloadBits in payloadSets) {
        final frame = encodeFrame(payloadBits);
        final decoded = decodeFrame(frame);

        expect(decoded, isNotNull);
        expect(decoded, equals(payloadBits));
      }
    });

    test('length header majority vote survives one corrupted repetition', () {
      final payloadBits = List<int>.generate(24, (index) => (index * 5) % 2);
      final frame = encodeFrame(payloadBits);
      final preambleLength = generatePreamble().length;
      final symbolSamples = (0.1 * 44100).round();

      final corrupted = frame.toList();
      final headerStart = preambleLength;
      final offset = headerStart + (8 * symbolSamples) + 2;
      final corruptWindow = corrupted.getRange(offset, offset + symbolSamples).toList();
      final inverted = corruptWindow.map((value) => -value).toList();
      corrupted.replaceRange(offset, offset + symbolSamples, inverted);

      final decodedLength = decodeLengthHeader(corrupted, 0);
      expect(decodedLength, equals(payloadBits.length));
    });

    test('detectPreamble returns null when no preamble exists', () {
      final noise = List<double>.generate(2000, (index) {
        final phase = index / 13.0;
        return 0.01 * sin(2 * pi * phase);
      });

      expect(detectPreamble(noise), isNull);
    });
  });
}
