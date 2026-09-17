import 'dart:math';

import 'protocol.dart';
import 'tone_generator.dart';

class Decoder {
  static final int _symbolSamples = _sampleCount(symbolDurationMs);
  static final int _preambleSamples = _sampleCount(preambleDurationMs);

  static double goertzelMagnitude(
    List<double> samples,
    int offset,
    double targetFreq,
  ) {
    if (offset < 0 || offset + _symbolSamples > samples.length) {
      throw RangeError('Not enough samples for a symbol window at offset $offset');
    }

    final coefficient = 2 * cos(2 * pi * targetFreq / sampleRate);
    var previous = 0.0;
    var previousPrevious = 0.0;
    for (int index = offset; index < offset + _symbolSamples; index++) {
      final current = samples[index] + coefficient * previous - previousPrevious;
      previousPrevious = previous;
      previous = current;
    }
    final power = previousPrevious * previousPrevious +
        previous * previous -
        coefficient * previous * previousPrevious;
    return sqrt(max(0, power));
  }

  static int? findPreambleEnd(List<double> samples) {
    if (samples.length < _preambleSamples) {
      return null;
    }
    for (int offset = 0; offset + _symbolSamples <= samples.length; offset++) {
      final preambleMagnitude =
          goertzelMagnitude(samples, offset, preambleFreq);
      final bit0Magnitude = goertzelMagnitude(samples, offset, bit0Freq);
      final bit1Magnitude = goertzelMagnitude(samples, offset, bit1Freq);
      final strongestBitMagnitude = max(bit0Magnitude, bit1Magnitude);
      if (preambleMagnitude > 2 * strongestBitMagnitude &&
          preambleMagnitude > 1) {
        return offset + _preambleSamples;
      }
    }
    return null;
  }

  /// Like [findPreambleEnd], but begins scanning at [searchStart] instead
  /// of offset 0. Uses a two-phase approach to correctly locate the
  /// preamble within a longer signal (e.g. a host song with an embedded
  /// watermark at an arbitrary position).
  ///
  /// **Phase 1** — Coarse scan: steps by `_symbolSamples` to quickly find
  /// a region with strong preamble energy.
  ///
  /// **Phase 2** — Boundary refinement: from the coarse hit, scans
  /// forward by `_symbolSamples` steps to find the first window where
  /// data-symbol energy dominates preamble energy, indicating the
  /// preamble→header transition.
  static int? findPreambleEndFrom(List<double> samples, int searchStart) {
    if (searchStart < 0 || searchStart >= samples.length) {
      return null;
    }

    // Phase 1: Coarse scan — find the first symbol-aligned position with
    // strong preamble energy.
    int? coarseHit;
    for (int offset = searchStart;
        offset + _symbolSamples <= samples.length;
        offset += _symbolSamples) {
      final pm = goertzelMagnitude(samples, offset, preambleFreq);
      final b0 = goertzelMagnitude(samples, offset, bit0Freq);
      final b1 = goertzelMagnitude(samples, offset, bit1Freq);
      if (pm > 2 * max(b0, b1) && pm > 1) {
        coarseHit = offset;
        break;
      }
    }
    if (coarseHit == null) return null;

    // Phase 2: From the coarse hit, advance by symbol-sized steps until
    // we find a window where data-symbol energy dominates preamble energy.
    // That window is the first data symbol, so the preamble ended just
    // before it.
    for (int offset = coarseHit;
        offset + _symbolSamples <= samples.length;
        offset += _symbolSamples) {
      final pm = goertzelMagnitude(samples, offset, preambleFreq);
      final b0 = goertzelMagnitude(samples, offset, bit0Freq);
      final b1 = goertzelMagnitude(samples, offset, bit1Freq);
      final strongestBit = max(b0, b1);
      // When data-symbol energy overtakes preamble energy, we've left
      // the preamble region. This offset is the start of the first data
      // symbol (i.e. the preamble end).
      if (strongestBit > pm) {
        return offset;
      }
    }

    // Preamble detected but no data after it — malformed signal.
    return null;
  }

  static List<int> readBits(List<double> samples, int numBits) {
    if (numBits < 0) {
      throw ArgumentError.value(numBits, 'numBits', 'must not be negative');
    }
    final bits = <int>[];
    for (int bitIndex = 0; bitIndex < numBits; bitIndex++) {
      final offset = bitIndex * _symbolSamples;
      final bit0Magnitude = goertzelMagnitude(samples, offset, bit0Freq);
      final bit1Magnitude = goertzelMagnitude(samples, offset, bit1Freq);
      bits.add(bit0Magnitude >= bit1Magnitude ? 0 : 1);
    }
    return bits;
  }

  static int majorityVoteHeader(List<int> rawHeaderBits) {
    if (rawHeaderBits.length != 24) {
      throw ArgumentError.value(
        rawHeaderBits.length,
        'rawHeaderBits.length',
        'must contain exactly 24 bits',
      );
    }
    final recoveredBits = <int>[];
    for (int bitIndex = 0; bitIndex < 8; bitIndex++) {
      final first = rawHeaderBits[bitIndex];
      final second = rawHeaderBits[8 + bitIndex];
      final third = rawHeaderBits[16 + bitIndex];
      if ([first, second, third].any((bit) => bit != 0 && bit != 1)) {
        throw ArgumentError('Header bits must be 0 or 1');
      }
      recoveredBits.add(first + second + third >= 2 ? 1 : 0);
    }
    return ToneGenerator.bitsToBytes(recoveredBits).single;
  }

  static List<int> decodeLengthPrefixedBits(List<double> samples) {
    final preambleEnd = findPreambleEnd(samples);
    if (preambleEnd == null) {
      throw StateError('Preamble not found');
    }
    final headerSamples = samples.sublist(preambleEnd);
    final rawHeaderBits = readBits(headerSamples, 24);
    final byteLength = majorityVoteHeader(rawHeaderBits);
    final payloadStart = 24 * _symbolSamples;
    final payload = headerSamples.sublist(payloadStart);
    return readBits(payload, byteLength * 8);
  }

  static int _sampleCount(double durationMs) {
    return (sampleRate * durationMs / 1000).round();
  }
}
