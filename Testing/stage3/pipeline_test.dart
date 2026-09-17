import 'package:flutter_test/flutter_test.dart';

import 'package:audio_watermark/dsp/aes_crypto.dart';
import 'package:audio_watermark/dsp/pipeline.dart';
import 'package:audio_watermark/dsp/wav_utils.dart';

void main() {
  group('Stage 3 pipeline', () {
    test('full round-trip works across several message lengths', () {
      final hostAudio = readWav('../Testing/stage3/fixtures/host_tone.wav');
      final messages = [
        'HI',
        'This is a medium message.',
        'The quick brown fox jumps',
        'A compact payload test',
      ];

      for (final message in messages) {
        final key = generateKey();
        final mixed = transmitMessage(message, key, hostAudio.samples);
        final recovered = receiveMessage(mixed, key);

        expect(recovered, equals(message));
      }
    });

    test('different key fails cleanly even when frame decodes', () {
      final hostAudio = readWav('../Testing/stage3/fixtures/host_tone.wav');
      final keyA = generateKey();
      final keyB = generateKey();
      const message = 'Secret msg';

      final mixed = transmitMessage(message, keyA, hostAudio.samples);
      final recovered = receiveMessage(mixed, keyB);

      expect(recovered, isNull);
    });

    test('wav utils can read and write mono PCM audio', () {
      final original = readWav('../Testing/stage3/fixtures/host_tone.wav');
      final outputPath = '../Testing/stage3/fixtures/host_tone_roundtrip.wav';

      writeWav(outputPath, original);

      final roundTrip = readWav(outputPath);
      expect(roundTrip.sampleRate, equals(original.sampleRate));
      expect(roundTrip.channels, equals(1));
      expect(roundTrip.samples.length, equals(original.samples.length));
      expect(roundTrip.samples.first, isNotNull);
    });
  });
}
