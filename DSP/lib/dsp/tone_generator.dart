import 'dart:math';

import 'protocol.dart';
import 'tuning_config.dart';

class ToneGenerator {
  static int get _preambleSamples => _sampleCount(preambleDurationMs);
  static int get _symbolSamples => _sampleCount(TuningConfig.symbolDurationMs);

  static List<double> generatePreamble() {
    return _generateTone(preambleFreq, _preambleSamples);
  }

  static List<double> generateSymbol(int bit) {
    if (bit != 0 && bit != 1) {
      throw ArgumentError.value(bit, 'bit', 'must be 0 or 1');
    }
    final frequency = bit == 0 ? bit0Freq : bit1Freq;
    return _generateTone(frequency, _symbolSamples);
  }

  /// Generates [durationMs] of a pure sine tone at [freq] Hz, looped
  /// continuously (not a single symbol-length burst) — useful for manual
  /// calibration testing where you want to record for several seconds.
  static List<double> generatePureTone(
    double freq,
    double durationMs, {
    double? amplitude,
  }) {
    if (freq <= 0) {
      throw ArgumentError.value(freq, 'freq', 'must be greater than 0');
    }
    if (durationMs <= 0) {
      throw ArgumentError.value(
        durationMs,
        'durationMs',
        'must be greater than 0',
      );
    }
    final sampleCount = _sampleCount(durationMs);
    final amp = amplitude ?? TuningConfig.amplitude;
    return List<double>.generate(
      sampleCount,
      (index) => amp * sin(2 * pi * freq * index / sampleRate),
    );
  }

  static List<double> bitsToSamples(List<int> bits) {
    final samples = generatePreamble();
    for (final bit in bits) {
      samples.addAll(generateSymbol(bit));
    }
    return samples;
  }

  static List<double> bitsToSamplesWithHeader(List<int> payloadBits) {
    if (payloadBits.length % 8 != 0) {
      throw ArgumentError.value(
        payloadBits.length,
        'payloadBits.length',
        'must be a multiple of 8',
      );
    }
    final byteLength = payloadBits.length ~/ 8;
    if (byteLength > 255) {
      throw ArgumentError.value(byteLength, 'byteLength', 'must fit in 8 bits');
    }
    final lengthBits = bytesToBits([byteLength]);
    return bitsToSamples([
      ...lengthBits,
      ...lengthBits,
      ...lengthBits,
      ...payloadBits,
    ]);
  }

  static List<int> bytesToBits(List<int> bytes) {
    final bits = <int>[];
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw ArgumentError.value(byte, 'byte', 'must be between 0 and 255');
      }
      for (int shift = 7; shift >= 0; shift--) {
        bits.add((byte >> shift) & 1);
      }
    }
    return bits;
  }

  static List<int> bitsToBytes(List<int> bits) {
    if (bits.length % 8 != 0) {
      throw ArgumentError.value(bits.length, 'bits.length', 'must be a multiple of 8');
    }
    final bytes = <int>[];
    for (int offset = 0; offset < bits.length; offset += 8) {
      var byte = 0;
      for (int index = 0; index < 8; index++) {
        final bit = bits[offset + index];
        if (bit != 0 && bit != 1) {
          throw ArgumentError.value(bit, 'bit', 'must be 0 or 1');
        }
        byte = (byte << 1) | bit;
      }
      bytes.add(byte);
    }
    return bytes;
  }

  static int _sampleCount(double durationMs) {
    return (sampleRate * durationMs / 1000).round();
  }

  static List<double> _generateTone(double frequency, int sampleCount) {
    return List<double>.generate(
      sampleCount,
      (index) => TuningConfig.amplitude * sin(2 * pi * frequency * index / sampleRate),
    );
  }
}
