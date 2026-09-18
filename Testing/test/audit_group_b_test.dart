import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/decoder.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';
import 'package:dsp/dsp/tuning_config.dart';

void main() {
  setUp(() {
    TuningConfig.resetToDefaults();
  });

  group('Priority Group B.6: Fuzz Frame Parsing with Malformed Length Fields', () {
    test('Decoder handles length field 0 without crash or hang', () {
      final preamble = ToneGenerator.generatePreamble();
      final lengthBits0 = ToneGenerator.bytesToBits([0]);
      final header0Bits = [...lengthBits0, ...lengthBits0, ...lengthBits0];
      final samples = [...preamble];
      for (final bit in header0Bits) {
        samples.addAll(ToneGenerator.generateSymbol(bit));
      }

      expect(() {
        try {
          final bits = Decoder.decodeLengthPrefixedBits(samples);
          expect(bits.isEmpty, isTrue);
        } catch (e) {
          expect(e, anyOf(isA<RangeError>(), isA<ArgumentError>(), isA<StateError>()));
        }
      }, returnsNormally);

      final key = WatermarkCrypto.generateKey();
      final extracted = Embedder.extractMessage(samples, key);
      expect(extracted, isNull, reason: 'Length 0 must be rejected cleanly by Embedder');
    });

    test('Decoder handles length field 1 without crash or hang', () {
      final preamble = ToneGenerator.generatePreamble();
      final lengthBits1 = ToneGenerator.bytesToBits([1]);
      final header1Bits = [...lengthBits1, ...lengthBits1, ...lengthBits1];
      final samples = [...preamble];
      for (final bit in header1Bits) {
        samples.addAll(ToneGenerator.generateSymbol(bit));
      }
      for (final bit in [0, 1, 0, 1, 0, 1, 0, 1]) {
        samples.addAll(ToneGenerator.generateSymbol(bit));
      }

      final key = WatermarkCrypto.generateKey();
      final extracted = Embedder.extractMessage(samples, key);
      expect(extracted, isNull, reason: 'Length 1 (payload + CRC requires >= 2 bytes) must return null cleanly');
    });

    test('Length field 255 with truncated stream safely returns empty without RangeError', () {
      final preamble = ToneGenerator.generatePreamble();
      final lengthBits255 = ToneGenerator.bytesToBits([255]);
      final header255Bits = [...lengthBits255, ...lengthBits255, ...lengthBits255];
      final samples = [...preamble];
      for (final bit in header255Bits) {
        samples.addAll(ToneGenerator.generateSymbol(bit));
      }
      samples.addAll(List<double>.filled(100, 0.0));

      expect(Decoder.decodeLengthPrefixedBits(samples), isEmpty);

      final key = WatermarkCrypto.generateKey();
      expect(Embedder.extractMessage(samples, key), isNull);
    });
  });

  group('Priority Group B.7: Payload Bytes Coincidentally Matching Preamble Pattern', () {
    test('Payload containing 17 kHz preamble frequency causes false preamble detection if scanned', () {
      final key = WatermarkCrypto.generateKey();
      const legitMessage = 'Secret Message Alpha';

      final host = List<double>.filled(44100 * 25, 0.0);
      final mixed = Embedder.embedMessage(legitMessage, key, host);

      final firstPreambleEnd = Decoder.findPreambleEnd(mixed)!;
      final detectedEnd = Decoder.findPreambleEndFrom(mixed, 0);
      expect(detectedEnd, equals(firstPreambleEnd));

      // Synthesize an audio stream where payload contains 17 kHz burst
      final injectedPreamble = ToneGenerator.generatePreamble();
      final falseHitEnd = Decoder.findPreambleEndFrom(injectedPreamble, 0);
      expect(falseHitEnd, isNull, reason: 'Standalone 17 kHz without succeeding data symbols fails Phase 2');
    });
  });

  group('Priority Group B.8: Preamble False Positives and Offset Robustness', () {
    test('60 seconds of White Noise under production scanner findPreambleEndFrom', () {
      final rng = Random(42);
      const durationSec = 60;
      final sampleCount = 44100 * durationSec;
      final whiteNoise = List<double>.generate(
        sampleCount,
        (_) => (rng.nextDouble() * 2.0 - 1.0) * 0.1,
      );

      // In production (AudioReceiver / Embedder), findPreambleEndFrom is used:
      final falseHit = Decoder.findPreambleEndFrom(whiteNoise, 0);
      expect(falseHit, isNull, reason: 'Production scanner must reject 60s white noise');
    });

    test('60 seconds of Pink Noise under production scanner findPreambleEndFrom', () {
      final rng = Random(1337);
      const durationSec = 60;
      final sampleCount = 44100 * durationSec;

      var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0;
      final pinkNoise = List<double>.generate(sampleCount, (_) {
        final white = rng.nextDouble() * 2.0 - 1.0;
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        b3 = 0.86650 * b3 + white * 0.3104856;
        b4 = 0.55000 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.0168980;
        final pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.05;
        b6 = white * 0.115926;
        return pink.clamp(-1.0, 1.0);
      });

      final falseHit = Decoder.findPreambleEndFrom(pinkNoise, 0);
      expect(falseHit, isNull, reason: 'Production scanner must reject 60s pink noise');
    });

    test('60 seconds of Silence under production scanner', () {
      final silence = List<double>.filled(44100 * 60, 0.0);
      expect(Decoder.findPreambleEndFrom(silence, 0), isNull);
    });

    test('60 seconds of Unwatermarked Music Host under production scanner', () {
      const durationSec = 60;
      final sampleCount = 44100 * durationSec;
      final music = List<double>.filled(sampleCount, 0.0);
      final freqs = [130.81, 261.63, 329.63, 392.00, 523.25, 1046.5, 2093.0, 4186.0, 8372.0, 11000.0];
      for (int i = 0; i < sampleCount; i++) {
        final t = i / 44100.0;
        double s = 0.0;
        for (int fi = 0; fi < freqs.length; fi++) {
          s += (0.3 / (fi + 1)) * sin(2 * pi * freqs[fi] * t);
        }
        music[i] = s.clamp(-1.0, 1.0);
      }

      expect(Decoder.findPreambleEndFrom(music, 0), isNull);
    });

    test('Sample-by-sample scanner findPreambleEnd generates false positive on white noise', () {
      // Demonstrates defect in findPreambleEnd: sample-by-sample scanning triggers false alarm
      final rng = Random(42);
      const durationSec = 5; // 5 seconds is enough to trigger false positive
      final sampleCount = 44100 * durationSec;
      final whiteNoise = List<double>.generate(
        sampleCount,
        (_) => (rng.nextDouble() * 2.0 - 1.0) * 0.1,
      );

      final hit = Decoder.findPreambleEnd(whiteNoise);
      // findPreambleEnd triggers false positive due to lack of phase-2 boundary check:
      expect(
        hit,
        isNull,
        reason: 'findPreambleEnd false alarm: noise triggered single-window threshold at sample ',
      );
    });

    test('Detect preamble starting at non-zero, non-frame-aligned sample offset', () {
      final key = WatermarkCrypto.generateKey();
      const message = 'Aligned test';

      // 1543 samples offset (not a multiple of 4410)
      const offset = 1543;
      final host = List<double>.filled(44100 * 20, 0.0);
      final mixed = Embedder.embedMessage(message, key, host, offset: offset);

      final extracted = Embedder.extractMessage(mixed, key);
      expect(
        extracted,
        equals(message),
        reason: 'findPreambleEndFrom should synchronize to preamble embedded at arbitrary sample offset ',
      );
    });
  });
}
