import 'dart:math';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/protocol.dart';

List<double> _generateSyntheticHost(double durationSeconds) {
  final count = (sampleRate * durationSeconds).round();
  final samples = List<double>.filled(count, 0.0);
  final freqs = [261.63, 329.63, 392.00, 523.25];

  for (int i = 0; i < count; i++) {
    final t = i / sampleRate;
    double sum = 0.0;
    for (final f in freqs) {
      sum += 0.08 * sin(2 * pi * f * t);
    }
    samples[i] = sum;
  }
  return samples;
}

void main() {
  group('Stage 5 Pipeline Unit Tests (Dart VM)', () {
    final key = WatermarkCrypto.generateKey();

    test('1. Short message round-trip through full embed/extract pipeline', () {
      const message = 'HI';
      final host = _generateSyntheticHost(10.0);
      final mixed = Embedder.embedMessage(message, key, host, offset: 4410);

      final decoded = Embedder.extractMessage(mixed, key);
      expect(decoded, equals(message));
    });

    test('2. Medium message round-trip through full embed/extract pipeline', () {
      const message = 'SECRET_KEY_42';
      final host = _generateSyntheticHost(20.0);
      final mixed = Embedder.embedMessage(message, key, host, offset: 8820);

      final decoded = Embedder.extractMessage(mixed, key);
      expect(decoded, equals(message));
    });

    test('3. Full sentence round-trip through synthetic music host', () {
      const message = 'The quick brown fox jumps over the lazy dog!';
      const ciphertextLen = message.length;
      const requiredSec = 2.7 + 0.8 * ciphertextLen + 3.0;
      final host = _generateSyntheticHost(requiredSec);
      final mixed = Embedder.embedMessage(message, key, host, offset: 4410);

      final decoded = Embedder.extractMessage(mixed, key);
      expect(decoded, equals(message));
    });

    test('4. Full pipeline through in-memory WAV serialization', () {
      const message = 'WAV_BUFFER_TEST_OK';
      final host = _generateSyntheticHost(25.0);
      final mixed = Embedder.embedMessage(message, key, host, offset: 4410);

      // Serialize to WAV bytes (like AudioTransmitter does)
      final wavBytes = WavUtils.writeWavBytes(mixed, sampleRate: sampleRate);

      // Deserialize from WAV bytes
      final readWav = WavUtils.readWavBytes(wavBytes);
      expect(readWav.sampleRate, equals(sampleRate));

      final decoded = Embedder.extractMessage(readWav.samples, key);
      expect(decoded, equals(message));
    });

    test('5. No message in audio returns null cleanly', () {
      final host = _generateSyntheticHost(5.0);
      final decoded = Embedder.extractMessage(host, key);
      expect(decoded, isNull);
    });

    test('6. Wrong key fails to decode cleanly without crashing', () {
      const message = 'TOP_SECRET';
      final host = _generateSyntheticHost(15.0);
      final mixed = Embedder.embedMessage(message, key, host, offset: 4410);

      final wrongKey = WatermarkCrypto.generateKey();
      final decoded = Embedder.extractMessage(mixed, wrongKey);
      expect(decoded, isNot(equals(message)));
    });
  });
}
