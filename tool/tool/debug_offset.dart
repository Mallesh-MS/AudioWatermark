import 'dart:math';
import 'package:audio_watermark/dsp/protocol.dart';
import 'package:audio_watermark/dsp/decoder.dart';
import 'package:audio_watermark/dsp/aes_crypto.dart';
import 'package:audio_watermark/dsp/tone_generator.dart';
import 'package:audio_watermark/audio/embedder.dart';

void main() {
  final key = WatermarkCrypto.generateKey();
  const msg = 'Hello Stage3';
  final ct = WatermarkCrypto.encrypt(msg, key);
  final reqSec = 2.7 + 0.8 * ct.length;
  final offsetSamples = sampleRate; // 1 second
  final hostLen = reqSec + 3.0 + (offsetSamples / sampleRate);

  // Generate host
  final numSamples = (sampleRate * hostLen).round();
  final host = List<double>.filled(numSamples, 0.0);
  for (int i = 0; i < numSamples; i++) {
    host[i] = 0.3 * sin(2 * pi * 220.0 * i / sampleRate) +
        0.3 * sin(2 * pi * 440.0 * i / sampleRate) +
        0.3 * sin(2 * pi * 880.0 * i / sampleRate);
  }

  // Generate watermark separately to check its length
  final payloadBits = ToneGenerator.bytesToBits(ct);
  final watermarkSamples = ToneGenerator.bitsToSamplesWithHeader(payloadBits);
  print('Watermark samples: ${watermarkSamples.length}');
  print('Host length: ${host.length}');
  print('Offset: $offsetSamples');
  print('Space available at offset: ${host.length - offsetSamples}');
  print('Enough space: ${watermarkSamples.length <= host.length - offsetSamples}');

  final mixed = Embedder.embedMessage(msg, key, host, offset: offsetSamples);

  // Check a few magnitudes near the expected preamble location
  final symbolSamples = (sampleRate * symbolDurationMs / 1000).round();
  final preambleSamples = (sampleRate * preambleDurationMs / 1000).round();

  // Check at the exact offset where preamble starts
  print('\n--- Goertzel at offset $offsetSamples (expected preamble start) ---');
  final pm = Decoder.goertzelMagnitude(mixed, offsetSamples, preambleFreq);
  final b0m = Decoder.goertzelMagnitude(mixed, offsetSamples, bit0Freq);
  final b1m = Decoder.goertzelMagnitude(mixed, offsetSamples, bit1Freq);
  print('Preamble mag: $pm, bit0 mag: $b0m, bit1 mag: $b1m');
  print('Passes threshold: ${pm > 2 * max(b0m, b1m) && pm > 1}');

  // Check 100 samples before
  final checkBefore = offsetSamples - 100;
  if (checkBefore >= 0 && checkBefore + symbolSamples <= mixed.length) {
    print('\n--- Goertzel at offset $checkBefore (before preamble) ---');
    final pm2 = Decoder.goertzelMagnitude(mixed, checkBefore, preambleFreq);
    final b0m2 = Decoder.goertzelMagnitude(mixed, checkBefore, bit0Freq);
    final b1m2 = Decoder.goertzelMagnitude(mixed, checkBefore, bit1Freq);
    print('Preamble mag: $pm2, bit0 mag: $b0m2, bit1 mag: $b1m2');
    print('Passes threshold: ${pm2 > 2 * max(b0m2, b1m2) && pm2 > 1}');
  }

  // Now search from 0
  print('\n--- Scanning from 0 ---');
  final sw = Stopwatch()..start();
  final pe = Decoder.findPreambleEndFrom(mixed, 0);
  sw.stop();
  print('Found preamble end at: $pe (took ${sw.elapsedMilliseconds}ms)');
  print('Expected: ${offsetSamples + preambleSamples}');

  if (pe != null) {
    final afterPreamble = mixed.sublist(pe);
    print('Samples after preamble: ${afterPreamble.length}');
    try {
      final rawHeaderBits = Decoder.readBits(afterPreamble, 24);
      final byteLength = Decoder.majorityVoteHeader(rawHeaderBits);
      print('Decoded byte length: $byteLength (expected: ${ct.length})');
    } catch (e) {
      print('Header decode error: $e');
    }
  }
}
