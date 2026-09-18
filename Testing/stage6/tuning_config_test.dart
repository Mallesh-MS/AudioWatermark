import 'dart:math';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';
import 'package:dsp/dsp/tuning_config.dart';

void main() {
  setUp(() {
    TuningConfig.resetToDefaults();
  });

  tearDown(() {
    TuningConfig.resetToDefaults();
  });

  group('TuningConfig Unit Tests', () {
    test('1. Initializes to protocol.dart designed defaults', () {
      expect(TuningConfig.amplitude, equals(watermarkAmplitude));
      expect(TuningConfig.preambleThreshold, equals(defaultPreambleThreshold));
      expect(TuningConfig.symbolDurationMs, equals(defaultSymbolDurationMs));
    });

    test('2. Modifying amplitude updates ToneGenerator generated tone amplitude', () {
      TuningConfig.amplitude = 0.08;
      final samples = ToneGenerator.generateSymbol(0);
      final maxVal = samples.map((s) => s.abs()).reduce(max);
      expect(maxVal, closeTo(0.08, 0.005));

      TuningConfig.amplitude = 0.01;
      final samplesLow = ToneGenerator.generateSymbol(0);
      final maxValLow = samplesLow.map((s) => s.abs()).reduce(max);
      expect(maxValLow, closeTo(0.01, 0.002));
    });

    test('3. Modifying symbolDurationMs dynamically adjusts symbol length and round-trips', () {
      // Test at 50ms (faster symbol rate)
      TuningConfig.symbolDurationMs = 50.0;
      final expected50 = (sampleRate * 0.05).round();
      final sym50 = ToneGenerator.generateSymbol(1);
      expect(sym50.length, equals(expected50));

      final key = WatermarkCrypto.generateKey();
      const message = 'FAST_50MS';
      final host = List<double>.filled(sampleRate * 12, 0.0);
      final embedded = Embedder.embedMessage(message, key, host);
      final extracted = Embedder.extractMessage(embedded, key);
      expect(extracted, equals(message));

      // Test at 150ms (slower symbol rate, higher energy per symbol)
      TuningConfig.symbolDurationMs = 150.0;
      final expected150 = (sampleRate * 0.15).round();
      final sym150 = ToneGenerator.generateSymbol(0);
      expect(sym150.length, equals(expected150));

      const messageLong = 'SLOW_150MS_ROBUST';
      final hostLong = List<double>.filled(sampleRate * 35, 0.0);
      final embeddedLong = Embedder.embedMessage(messageLong, key, hostLong);
      final extractedLong = Embedder.extractMessage(embeddedLong, key);
      expect(extractedLong, equals(messageLong));
    });

    test('4. Preamble threshold tuning correctly filters weak signals', () {
      final key = WatermarkCrypto.generateKey();
      const message = 'THRESH_TEST';
      final host = List<double>.filled(sampleRate * 18, 0.0);

      // Normal amplitude with standard threshold passes
      TuningConfig.amplitude = 0.02;
      TuningConfig.preambleThreshold = 1.0;
      final embedded = Embedder.embedMessage(message, key, host);
      expect(Embedder.extractMessage(embedded, key), equals(message));

      // Artificially high threshold causes preamble detection to reject weak signal
      TuningConfig.preambleThreshold = 50000.0;
      expect(Embedder.extractMessage(embedded, key), isNull);

      // Lowering threshold back allows it to pass
      TuningConfig.preambleThreshold = 0.5;
      expect(Embedder.extractMessage(embedded, key), equals(message));
    });

    test('5. resetToDefaults restores original design constants', () {
      TuningConfig.amplitude = 0.12;
      TuningConfig.preambleThreshold = 8.5;
      TuningConfig.symbolDurationMs = 180.0;

      TuningConfig.resetToDefaults();

      expect(TuningConfig.amplitude, equals(watermarkAmplitude));
      expect(TuningConfig.preambleThreshold, equals(defaultPreambleThreshold));
      expect(TuningConfig.symbolDurationMs, equals(defaultSymbolDurationMs));
    });
  });
}
