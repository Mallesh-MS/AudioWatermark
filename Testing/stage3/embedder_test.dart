import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

import 'package:audio_watermark/audio/embedder.dart';
import 'package:audio_watermark/audio/wav_utils.dart';
import 'package:audio_watermark/dsp/aes_crypto.dart';
import 'package:audio_watermark/dsp/protocol.dart';
import 'package:audio_watermark/dsp/tone_generator.dart';

/// Generates a synthetic "music" host sample array: a mix of low-frequency
/// sines (220, 440, 880 Hz) at moderate amplitude, with no significant energy
/// near the watermark band (17-19.5 kHz). Returned samples are normalised
/// doubles in [-1.0, 1.0].
List<double> generateSyntheticHost(double durationSeconds) {
  final numSamples = (sampleRate * durationSeconds).round();
  final samples = List<double>.filled(numSamples, 0.0);
  const frequencies = [220.0, 440.0, 880.0];
  const amplitude = 0.3; // each tone — peak sum ≈ 0.9
  for (int i = 0; i < numSamples; i++) {
    double sum = 0.0;
    for (final freq in frequencies) {
      sum += amplitude * sin(2 * pi * freq * i / sampleRate);
    }
    samples[i] = sum;
  }
  return samples;
}

/// Like [generateSyntheticHost] but with samples near full scale (±0.98)
/// to test clipping behaviour.
List<double> generateNearFullScaleHost(double durationSeconds) {
  final numSamples = (sampleRate * durationSeconds).round();
  final samples = List<double>.filled(numSamples, 0.0);
  const amplitude = 0.98;
  for (int i = 0; i < numSamples; i++) {
    samples[i] = amplitude * sin(2 * pi * 440.0 * i / sampleRate);
  }
  return samples;
}

void main() {
  late Key key;
  const testMessage = 'Hello Stage3';

  setUp(() {
    key = WatermarkCrypto.generateKey();
  });

  group('Embedder', () {
    test('1. Full pipeline round-trip', () {
      // T = 2.7 + 0.8L — testMessage is 12 chars, ciphertext same length
      // for AES-CTR. T ≈ 2.7 + 9.6 = 12.3s. Use 15s for margin.
      final ciphertext = WatermarkCrypto.encrypt(testMessage, key);
      final requiredSeconds = 2.7 + 0.8 * ciphertext.length;
      final host = generateSyntheticHost(requiredSeconds + 3.0);

      final mixed = Embedder.embedMessage(testMessage, key, host);
      final recovered = Embedder.extractMessage(mixed, key);

      expect(recovered, equals(testMessage));
    });

    test('2. Message not at offset 0', () {
      final ciphertext = WatermarkCrypto.encrypt(testMessage, key);
      final requiredSeconds = 2.7 + 0.8 * ciphertext.length;
      // Offset 1 second into the host
      const offsetSamples = sampleRate; // 1 second
      final host = generateSyntheticHost(
        requiredSeconds + 3.0 + (offsetSamples / sampleRate),
      );

      final mixed = Embedder.embedMessage(
        testMessage,
        key,
        host,
        offset: offsetSamples,
      );
      final recovered = Embedder.extractMessage(mixed, key);

      expect(recovered, equals(testMessage));
    });

    test('3. Amplitude sanity — clipping works on near-full-scale host', () {
      final ciphertext = WatermarkCrypto.encrypt(testMessage, key);
      final requiredSeconds = 2.7 + 0.8 * ciphertext.length;
      final host = generateNearFullScaleHost(requiredSeconds + 3.0);

      final mixed = Embedder.embedMessage(testMessage, key, host);

      for (int i = 0; i < mixed.length; i++) {
        expect(
          mixed[i],
          inInclusiveRange(-1.0, 1.0),
          reason: 'Sample $i out of range: ${mixed[i]}',
        );
      }
    });

    test('4. Host too short throws ArgumentError', () {
      // Create a watermark that's definitely longer than 100 samples
      final watermark = ToneGenerator.bitsToSamplesWithHeader(
        ToneGenerator.bytesToBits([0x41, 0x42]),
      );
      // Host is way too short
      final shortHost = List<double>.filled(100, 0.0);

      expect(
        () => Embedder.embed(shortHost, watermark),
        throwsArgumentError,
      );

      // Also test with offset making it too short
      final barelyLongEnoughHost =
          List<double>.filled(watermark.length, 0.0);
      expect(
        () => Embedder.embed(barelyLongEnoughHost, watermark, offset: 1),
        throwsArgumentError,
      );
    });
  });

  group('WavUtils', () {
    test('5. WAV read/write round-trip', () {
      // Create a small known sample array
      final originalSamples = List<double>.generate(
        1000,
        (i) => 0.5 * sin(2 * pi * 440.0 * i / 44100),
      );

      final tempDir = Directory.systemTemp.createTempSync('wav_test_');
      final tempPath = '${tempDir.path}/test_roundtrip.wav';

      try {
        WavUtils.writeWav(tempPath, originalSamples, 44100);
        final wavData = WavUtils.readWav(tempPath);

        expect(wavData.sampleRate, equals(44100));
        expect(wavData.samples.length, equals(originalSamples.length));

        // Allow quantisation error from 16-bit conversion: ±1/32768
        const tolerance = 1.0 / 32768.0 + 1e-10;
        for (int i = 0; i < originalSamples.length; i++) {
          expect(
            (wavData.samples[i] - originalSamples[i]).abs(),
            lessThanOrEqualTo(tolerance),
            reason: 'Sample $i: expected ${originalSamples[i]}, '
                'got ${wavData.samples[i]}',
          );
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('6. Real file end-to-end (if fixture WAV exists)', () {
      final fixturesDir = Directory('../Testing/stage3/fixtures');
      if (!fixturesDir.existsSync()) {
        // No fixtures directory — generate a synthetic WAV to stand in
        // for a real host song, so we still exercise the full
        // write→read→embed→write→read→extract pipeline through 16-bit
        // PCM quantisation.
        final syntheticHost = generateSyntheticHost(15.0);
        fixturesDir.createSync(recursive: true);
        WavUtils.writeWav(
          '${fixturesDir.path}/synthetic_host.wav',
          syntheticHost,
          sampleRate,
        );
      }

      final wavFiles = fixturesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav'))
          .toList();

      if (wavFiles.isEmpty) {
        // Skip gracefully if no WAV files available
        markTestSkipped('No WAV files found in ../Testing/stage3/fixtures/');
        return;
      }

      final hostWav = WavUtils.readWav(wavFiles.first.path);
      // Ensure we're working at 44100 Hz (our protocol sample rate)
      expect(hostWav.sampleRate, equals(sampleRate),
          reason: 'Host WAV must be 44100 Hz for this test');

      final endToEndKey = WatermarkCrypto.generateKey();
      const endToEndMessage = 'E2E';

      // Check the host is long enough
      final ciphertext =
          WatermarkCrypto.encrypt(endToEndMessage, endToEndKey);
      final requiredSamples =
          ((2.7 + 0.8 * ciphertext.length) * sampleRate).round();
      if (hostWav.samples.length < requiredSamples) {
        markTestSkipped(
          'Host WAV too short: need $requiredSamples samples, '
          'have ${hostWav.samples.length}',
        );
        return;
      }

      // Embed
      final mixed = Embedder.embedMessage(
        endToEndMessage,
        endToEndKey,
        hostWav.samples,
      );

      // Write to temp WAV, then read back (exercises 16-bit quantisation)
      final tempDir = Directory.systemTemp.createTempSync('wav_e2e_');
      final outputPath = '${tempDir.path}/embedded_output.wav';

      try {
        WavUtils.writeWav(outputPath, mixed, sampleRate);
        final reRead = WavUtils.readWav(outputPath);

        // Extract from the quantised samples
        final recovered =
            Embedder.extractMessage(reRead.samples, endToEndKey);

        expect(recovered, equals(endToEndMessage),
            reason: 'Message must survive 16-bit PCM quantisation');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
