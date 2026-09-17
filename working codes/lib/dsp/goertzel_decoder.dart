import 'dart:math';

import 'protocol.dart';

const int symbolSampleCount = 4410;
const int preambleSampleCount = 13230;

double goertzelMagnitude(List<double> samples, double targetFreq, int sampleRate) {
  if (samples.isEmpty) {
    return 0.0;
  }
  if (targetFreq <= 0 || sampleRate <= 0) {
    throw ArgumentError.value(targetFreq, 'targetFreq', 'must be > 0');
  }

  final coefficient = 2.0 * cos((2.0 * pi * targetFreq) / sampleRate);
  var previous = 0.0;
  var previousPrevious = 0.0;

  for (final sample in samples) {
    final current = sample + (coefficient * previous) - previousPrevious;
    previousPrevious = previous;
    previous = current;
  }

  final power = (previousPrevious * previousPrevious) +
      (previous * previous) -
      (coefficient * previous * previousPrevious);
  return sqrt(max(0.0, power));
}

int? detectPreamble(List<double> samples) {
  if (samples.length < preambleSampleCount) {
    return null;
  }

  for (int start = 0; start + preambleSampleCount <= samples.length; start++) {
    final window = samples.sublist(start, start + preambleSampleCount);
    final preambleMagnitude = goertzelMagnitude(window, preambleFreq, sampleRate);
    final bit0Magnitude = goertzelMagnitude(window, bit0Freq, sampleRate);
    final bit1Magnitude = goertzelMagnitude(window, bit1Freq, sampleRate);
    final strongestBitMagnitude = max(bit0Magnitude, bit1Magnitude);

    if (preambleMagnitude > (2.0 * strongestBitMagnitude) && preambleMagnitude > 0.5) {
      return start;
    }
  }

  return null;
}

int decodeBit(List<double> symbolWindow) {
  if (symbolWindow.length < symbolSampleCount) {
    throw StateError('Bit window too short for one symbol duration');
  }

  final bit0Magnitude = goertzelMagnitude(symbolWindow, bit0Freq, sampleRate);
  final bit1Magnitude = goertzelMagnitude(symbolWindow, bit1Freq, sampleRate);
  return bit1Magnitude > bit0Magnitude ? 1 : 0;
}

int decodeLengthHeader(List<double> samples, int startIndex) {
  if (startIndex < 0 || startIndex + preambleSampleCount > samples.length) {
    throw RangeError('Start index is out of range for a preamble window');
  }

  final headerStart = startIndex + preambleSampleCount;
  final bitVotes = List<int>.filled(8, 0);

  for (int repetition = 0; repetition < 3; repetition++) {
    for (int bitIndex = 0; bitIndex < 8; bitIndex++) {
      final symbolStart = headerStart + ((repetition * 8) + bitIndex) * symbolSampleCount;
      final symbolEnd = symbolStart + symbolSampleCount;
      if (symbolEnd > samples.length) {
        throw RangeError('Not enough samples to decode the length header');
      }
      final bitValue = decodeBit(samples.sublist(symbolStart, symbolEnd));
      bitVotes[bitIndex] += bitValue;
    }
  }

  var length = 0;
  for (final count in bitVotes) {
    length = (length << 1) | (count >= 2 ? 1 : 0);
  }
  return length;
}

List<int>? decodeFrame(List<double> samples) {
  final start = detectPreamble(samples);
  if (start == null) {
    return null;
  }

  final payloadBitLength = decodeLengthHeader(samples, start);
  if (payloadBitLength < 0 || payloadBitLength > 255) {
    return null;
  }

  final payloadStart = start + preambleSampleCount + (3 * 8 * symbolSampleCount);
  final payloadBits = <int>[];

  for (int bitIndex = 0; bitIndex < payloadBitLength; bitIndex++) {
    final bitStart = payloadStart + (bitIndex * symbolSampleCount);
    final bitEnd = bitStart + symbolSampleCount;
    if (bitEnd > samples.length) {
      return null;
    }
    payloadBits.add(decodeBit(samples.sublist(bitStart, bitEnd)));
  }

  return payloadBits;
}

class GoertzelDecoder {
  static double goertzelMagnitude(List<double> samples, double targetFreq, int sampleRate) =>
      _goertzelMagnitudeImpl(samples, targetFreq, sampleRate);

  static int? detectPreamble(List<double> samples) => _detectPreambleImpl(samples);

  static int decodeBit(List<double> symbolWindow) => _decodeBitImpl(symbolWindow);

  static int decodeLengthHeader(List<double> samples, int startIndex) =>
      _decodeLengthHeaderImpl(samples, startIndex);

  static List<int>? decodeFrame(List<double> samples) => _decodeFrameImpl(samples);
}

double _goertzelMagnitudeImpl(List<double> samples, double targetFreq, int sampleRate) {
  return goertzelMagnitude(samples, targetFreq, sampleRate);
}

int? _detectPreambleImpl(List<double> samples) {
  return detectPreamble(samples);
}

int _decodeBitImpl(List<double> symbolWindow) {
  return decodeBit(symbolWindow);
}

int _decodeLengthHeaderImpl(List<double> samples, int startIndex) {
  return decodeLengthHeader(samples, startIndex);
}

List<int>? _decodeFrameImpl(List<double> samples) {
  return decodeFrame(samples);
}
