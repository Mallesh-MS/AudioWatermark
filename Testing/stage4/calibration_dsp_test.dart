import 'dart:typed_data';
import 'package:test/test.dart';

import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/decoder.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';

void main() {
  group('Stage 4 DSP & Helper Tests', () {
    test('generatePureTone generates continuous sine wave with requested duration', () {
      const durationMs = 500.0;
      final samples = ToneGenerator.generatePureTone(18000.0, durationMs, amplitude: 0.5);
      final expectedCount = (sampleRate * durationMs / 1000).round();
      expect(samples.length, equals(expectedCount));

      // Goertzel magnitude on 18000 Hz window should be strong
      final mag18k = Decoder.goertzelMagnitude(samples, 0, 18000.0);
      final mag17k = Decoder.goertzelMagnitude(samples, 0, 17000.0);
      final mag195k = Decoder.goertzelMagnitude(samples, 0, 19500.0);

      expect(mag18k, greaterThan(10.0));
      expect(mag18k, greaterThan(mag17k * 5));
      expect(mag18k, greaterThan(mag195k * 5));
    });

    test('generatePureTone error handling', () {
      expect(() => ToneGenerator.generatePureTone(0, 100), throwsArgumentError);
      expect(() => ToneGenerator.generatePureTone(18000, 0), throwsArgumentError);
    });

    test('WAV byte roundtrip preserves Goertzel tone peak', () {
      final samples = ToneGenerator.generatePureTone(19500.0, 300.0, amplitude: 0.5);
      final wavBytes = WavUtils.writeWavBytes(samples, sampleRate: sampleRate);
      
      final parsedWav = WavUtils.readWavBytes(wavBytes);
      expect(parsedWav.sampleRate, equals(sampleRate));
      expect(parsedWav.samples.length, equals(samples.length));

      final mag195k = Decoder.goertzelMagnitude(parsedWav.samples, 0, 19500.0);
      final mag18k = Decoder.goertzelMagnitude(parsedWav.samples, 0, 18000.0);
      expect(mag195k, greaterThan(mag18k * 5));
    });

    test('Rolling buffer PCM16 ByteData parsing emulation', () {
      final samples = ToneGenerator.generatePureTone(17000.0, 100.0, amplitude: 0.5);
      final byteData = ByteData(samples.length * 2);
      for (int i = 0; i < samples.length; i++) {
        final int16 = (samples[i] * 32767.0).round().clamp(-32768, 32767);
        byteData.setInt16(i * 2, int16, Endian.little);
      }

      final reconstructed = <double>[];
      final count = byteData.lengthInBytes ~/ 2;
      for (int i = 0; i < count; i++) {
        final val = byteData.getInt16(i * 2, Endian.little) / 32768.0;
        reconstructed.add(val);
      }

      final mag17k = Decoder.goertzelMagnitude(reconstructed, 0, 17000.0);
      final mag18k = Decoder.goertzelMagnitude(reconstructed, 0, 18000.0);
      final mag195k = Decoder.goertzelMagnitude(reconstructed, 0, 19500.0);

      expect(mag17k, greaterThan(mag18k * 5));
      expect(mag17k, greaterThan(mag195k * 5));
    });
  });
}
