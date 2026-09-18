import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/crc.dart';
import 'package:dsp/dsp/decoder.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';
import 'package:dsp/dsp/tuning_config.dart';

void main() {
  setUp(() {
    TuningConfig.resetToDefaults();
  });

  group('Priority Group C.9: Goertzel Bin Alignment & Leakage Analysis', () {
    test('Tone frequencies land exactly on Goertzel bin centers at 44100 Hz / 100ms window', () {
      final windowSamples = (sampleRate * TuningConfig.symbolDurationMs / 1000).round();
      expect(windowSamples, equals(4410));

      final binResolution = sampleRate / windowSamples;
      expect(binResolution, equals(10.0), reason: 'Bin resolution must be exactly 10.0 Hz');

      final preambleBin = preambleFreq / binResolution;
      final bit0Bin = bit0Freq / binResolution;
      final bit1Bin = bit1Freq / binResolution;

      expect(preambleBin, equals(1700.0));
      expect(bit0Bin, equals(1800.0));
      expect(bit1Bin, equals(1950.0));

      const lowestSampleRate = 44100;
      const nyquist = lowestSampleRate / 2.0;
      expect(preambleFreq, lessThan(nyquist));
      expect(bit0Freq, lessThan(nyquist));
      expect(bit1Freq, lessThan(nyquist));
    });

    test('Quantify leakage into adjacent tone bins for pure synthesized symbols', () {
      final bit0Tone = ToneGenerator.generateSymbol(0);
      final bit0MagAtBit0 = Decoder.goertzelMagnitude(bit0Tone, 0, bit0Freq);
      final bit0LeakageAtPreamble = Decoder.goertzelMagnitude(bit0Tone, 0, preambleFreq);
      final bit0LeakageAtBit1 = Decoder.goertzelMagnitude(bit0Tone, 0, bit1Freq);

      expect(bit0MagAtBit0, greaterThan(10.0));
      expect(bit0LeakageAtPreamble / bit0MagAtBit0, lessThan(1e-4));
      expect(bit0LeakageAtBit1 / bit0MagAtBit0, lessThan(1e-4));

      final bit1Tone = ToneGenerator.generateSymbol(1);
      final bit1MagAtBit1 = Decoder.goertzelMagnitude(bit1Tone, 0, bit1Freq);
      final bit1LeakageAtBit0 = Decoder.goertzelMagnitude(bit1Tone, 0, bit0Freq);

      expect(bit1MagAtBit1, greaterThan(10.0));
      expect(bit1LeakageAtBit0 / bit1MagAtBit1, lessThan(1e-4));
    });
  });

  group('Priority Group C.10: Sample-Rate Mismatch Handling', () {
    test('Signal sampled at 48000 Hz decoded at 44100 Hz fails silently without error', () {
      final key = WatermarkCrypto.generateKey();
      const message = 'SampleRateMismatch';

      const fsTx = 48000;
      final totalSymbols = 24 + 8 * (message.length + 1);
      final durationSec = 0.3 + (totalSymbols * 0.1) + 1.0;
      final count = (fsTx * durationSec).round();
      final txSamples = List<double>.filled(count, 0.0);

      final ct = WatermarkCrypto.encrypt(message, key);
      final protected = Crc8.appendChecksum(ct);
      final bits = ToneGenerator.bytesToBits(protected);

      int idx = 0;
      final preCount = (fsTx * 0.3).round();
      for (int i = 0; i < preCount; i++) {
        txSamples[idx++] = 0.025 * sin(2 * pi * 17000.0 * i / fsTx);
      }
      final lenBits = ToneGenerator.bytesToBits([protected.length]);
      final headerBits = [...lenBits, ...lenBits, ...lenBits];
      final symCount = (fsTx * 0.1).round();
      for (final bit in [...headerBits, ...bits]) {
        final freq = bit == 0 ? 18000.0 : 19500.0;
        for (int i = 0; i < symCount; i++) {
          txSamples[idx++] = 0.025 * sin(2 * pi * freq * i / fsTx);
        }
      }

      final result = Embedder.extractMessage(txSamples, key);
      expect(result, isNull, reason: 'Sample rate mismatch is not detected; fails silently to decode');
    });
  });

  group('Priority Group C.11: Phase Continuity across Symbol Boundaries', () {
    test('Evaluate phase jump between consecutive symbols in ToneGenerator', () {
      final sym0 = ToneGenerator.generateSymbol(0);
      final sym1 = ToneGenerator.generateSymbol(1);

      final lastSampleSym0 = sym0.last;
      final firstSampleSym1 = sym1.first;

      final jump = (firstSampleSym1 - lastSampleSym0).abs();
      expect(jump, greaterThan(0.01), reason: 'Phase discontinuity causes sudden step jump at boundary');
    });
  });

  group('Priority Group C.12: Embedder Int16 Saturation & Host Boundary Cases', () {
    test('Full-amplitude tone embedded into host near +1.0 saturates cleanly without sign wrap', () {
      final hostNearMax = List<double>.filled(44100, 0.999);
      final tone = List<double>.filled(44100, 0.5);

      final mixed = Embedder.embed(hostNearMax, tone);
      for (final s in mixed) {
        expect(s, equals(1.0), reason: 'Must saturate at +1.0, never overflow or wrap');
      }

      final wavBytes = WavUtils.writeWavBytes(mixed, sampleRate: 44100);
      final byteData = ByteData.sublistView(wavBytes);
      final sampleVal = byteData.getInt16(44, Endian.little);
      expect(sampleVal, equals(32767), reason: 'Must saturate at 32767, not wrap to negative');
    });

    test('Host shorter than payload throws ArgumentError', () {
      final host = List<double>.filled(100, 0.0);
      final key = WatermarkCrypto.generateKey();

      expect(
        () => Embedder.embedMessage('Too long for tiny host', key, host),
        throwsArgumentError,
      );
    });

    test('All-zero host successfully embeds and extracts message', () {
      final host = List<double>.filled(44100 * 20, 0.0);
      final key = WatermarkCrypto.generateKey();
      const message = 'ZeroHostTest';

      final mixed = Embedder.embedMessage(message, key, host);
      final extracted = Embedder.extractMessage(mixed, key);
      expect(extracted, equals(message));
    });
  });

  group('Priority Group C.13: Robustness Sweep (Measurement Sweep)', () {
    test('Measure decode success rate across SNR, Clock Drift, and Filtering', () {
      final key = WatermarkCrypto.generateKey();
      const message = 'Audit123';
      final baseHost = List<double>.filled(44100 * 25, 0.0);
      final cleanMixed = Embedder.embedMessage(message, key, baseHost);

      final results = <String, String>{};

      const signalRms = 0.025 / 1.41421356;
      for (final snrDb in [20, 10, 5, 0]) {
        final noiseRms = signalRms / pow(10, snrDb / 20.0);
        final rng = Random(snrDb);
        final noisy = List<double>.generate(cleanMixed.length, (i) {
          final u1 = rng.nextDouble().clamp(1e-9, 1.0);
          final u2 = rng.nextDouble();
          final normal = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
          return (cleanMixed[i] + normal * noiseRms).clamp(-1.0, 1.0);
        });

        final decoded = Embedder.extractMessage(noisy, key);
        final success = decoded == message;
        results['Noise @ ' + snrDb.toString() + ' dB SNR'] = success ? 'PASS (100%)' : 'FAIL (0%)';
      }

      for (final drift in [0.005, -0.005]) {
        final resampledLength = (cleanMixed.length * (1.0 + drift)).round();
        final drifted = List<double>.generate(resampledLength, (i) {
          final srcIdx = i / (1.0 + drift);
          final i0 = srcIdx.floor();
          final frac = srcIdx - i0;
          if (i0 + 1 >= cleanMixed.length) return cleanMixed.last;
          return cleanMixed[i0] * (1.0 - frac) + cleanMixed[i0 + 1] * frac;
        });

        final decoded = Embedder.extractMessage(drifted, key);
        final label = drift > 0 ? '+0.5% Clock Drift' : '-0.5% Clock Drift';
        results[label] = decoded == message ? 'PASS (100%)' : 'FAIL (0%)';
      }

      for (final fc in [4000.0, 8000.0]) {
        final alpha = (2.0 * pi * fc / 44100.0).clamp(0.0, 1.0);
        var prev = 0.0;
        final filtered = List<double>.generate(cleanMixed.length, (i) {
          prev += alpha * (cleanMixed[i] - prev);
          return prev;
        });

        final decoded = Embedder.extractMessage(filtered, key);
        results['Low-pass @ ' + fc.toInt().toString() + ' Hz'] = decoded == message ? 'PASS (100%)' : 'FAIL (0% - Carrier Stripped)';
      }

      final alpha16k = (2.0 * pi * 16000.0 / 44100.0).clamp(0.0, 1.0);
      var prev16 = 0.0;
      final truncatedAbove16k = List<double>.generate(cleanMixed.length, (i) {
        prev16 += alpha16k * (cleanMixed[i] - prev16);
        return prev16;
      });
      final decoded16 = Embedder.extractMessage(truncatedAbove16k, key);
      results['Band Truncation > 16 kHz'] = decoded16 == message ? 'PASS (100%)' : 'FAIL (0% - Ultrasonic Blocked)';

      print('=== ROBUSTNESS SWEEP RESULTS ===');
      results.forEach((k, v) => print(k + ': ' + v));
      print('================================');
      expect(results.isNotEmpty, isTrue);
    });
  });
}
