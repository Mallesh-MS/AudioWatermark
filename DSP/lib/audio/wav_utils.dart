/// Pure-Dart WAV file reader/writer for 16-bit PCM audio.
///
/// No external packages — uses only `dart:io` and `dart:typed_data`.
/// Handles standard RIFF/WAVE/fmt/data chunks. Reads mono or stereo
/// (stereo is downmixed to mono by averaging channels).
library;

import 'dart:io';
import 'dart:typed_data';

/// Container for WAV sample data and its sample rate.
class WavData {
  /// Audio samples normalised to the range [-1.0, 1.0].
  final List<double> samples;

  /// The sample rate read from the WAV file header.
  final int sampleRate;

  WavData(this.samples, this.sampleRate);
}

class WavUtils {
  /// Reads a 16-bit PCM mono or stereo WAV from [bytes] and returns
  /// its samples as normalised doubles in [-1.0, 1.0].
  ///
  /// If stereo, downmixes to mono by averaging left and right channels.
  /// Throws [ArgumentError] if the bytes do not represent a valid 16-bit PCM WAV.
  static WavData readWavBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    // --- RIFF header ---
    if (bytes.length < 12) {
      throw ArgumentError('WAV byte buffer too short: ${bytes.length} bytes');
    }
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') {
      throw ArgumentError('Not a RIFF buffer');
    }
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') {
      throw ArgumentError('Not a WAVE buffer');
    }

    // --- Walk sub-chunks to find "fmt " and "data" ---
    int? fmtOffset;
    int? dataOffset;
    int? dataSize;
    int offset = 12; // right after "WAVE"
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkId == 'fmt ') {
        fmtOffset = offset + 8;
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
      }
      // Move to next chunk (chunks are word-aligned)
      offset += 8 + chunkSize;
      if (offset % 2 != 0) offset++;
    }

    if (fmtOffset == null) {
      throw ArgumentError('Missing "fmt " chunk in WAV buffer');
    }
    if (dataOffset == null || dataSize == null) {
      throw ArgumentError('Missing "data" chunk in WAV buffer');
    }

    // --- Parse fmt chunk ---
    final audioFormat = data.getUint16(fmtOffset, Endian.little);
    if (audioFormat != 1) {
      throw ArgumentError(
        'Unsupported audio format $audioFormat (only PCM = 1 is supported)',
      );
    }
    final numChannels = data.getUint16(fmtOffset + 2, Endian.little);
    if (numChannels < 1 || numChannels > 2) {
      throw ArgumentError('Unsupported channel count $numChannels (only 1 or 2 supported)');
    }
    final sampleRate = data.getUint32(fmtOffset + 4, Endian.little);
    if (sampleRate <= 0) {
      throw ArgumentError('Invalid sample rate $sampleRate');
    }
    final bitsPerSample = data.getUint16(fmtOffset + 14, Endian.little);
    if (bitsPerSample != 16) {
      throw ArgumentError(
        'Unsupported bit depth $bitsPerSample (only 16-bit PCM is supported)',
      );
    }
    if (dataOffset + dataSize > bytes.length) {
      throw ArgumentError('Declared data chunk size exceeds available buffer length');
    }

    // --- Read PCM samples ---
    const bytesPerSample = 2; // 16-bit
    final totalSampleValues = dataSize ~/ bytesPerSample;
    final totalFrames = totalSampleValues ~/ numChannels;

    final samples = List<double>.filled(totalFrames, 0.0);
    for (int frame = 0; frame < totalFrames; frame++) {
      double sum = 0.0;
      for (int ch = 0; ch < numChannels; ch++) {
        final sampleOffset =
            dataOffset + (frame * numChannels + ch) * bytesPerSample;
        final int16Value = data.getInt16(sampleOffset, Endian.little);
        sum += int16Value / 32768.0;
      }
      samples[frame] = sum / numChannels; // average channels for mono mix
    }

    return WavData(samples, sampleRate);
  }

  /// Reads a 16-bit PCM mono or stereo WAV file from [path] and returns
  /// its samples as normalised doubles in [-1.0, 1.0], at whatever sample
  /// rate the file actually has.
  static WavData readWav(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    return readWavBytes(Uint8List.fromList(bytes));
  }

  /// Encodes [samples] (normalised doubles in [-1.0, 1.0]) as a 16-bit PCM
  /// mono WAV byte buffer at [sampleRate].
  ///
  /// Clips values to [-1.0, 1.0] before converting to avoid integer
  /// overflow/wraparound artifacts.
  static Uint8List writeWavBytes(List<double> samples, {required int sampleRate}) {
    const numChannels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = samples.length * bytesPerSample;
    const fmtChunkSize = 16;
    // Total file size = 4 (RIFF type) + 8+fmtChunkSize (fmt chunk)
    //                  + 8+dataSize (data chunk)
    final fileSize = 4 + (8 + fmtChunkSize) + (8 + dataSize);

    final buffer = ByteData(8 + fileSize); // 8 = "RIFF" + file size field
    int pos = 0;

    // --- RIFF header ---
    void writeString(String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(pos++, s.codeUnitAt(i));
      }
    }

    writeString('RIFF');
    buffer.setUint32(pos, fileSize, Endian.little);
    pos += 4;
    writeString('WAVE');

    // --- fmt sub-chunk ---
    writeString('fmt ');
    buffer.setUint32(pos, fmtChunkSize, Endian.little);
    pos += 4;
    buffer.setUint16(pos, 1, Endian.little); // PCM
    pos += 2;
    buffer.setUint16(pos, numChannels, Endian.little);
    pos += 2;
    buffer.setUint32(pos, sampleRate, Endian.little);
    pos += 4;
    buffer.setUint32(
      pos,
      sampleRate * numChannels * bytesPerSample,
      Endian.little,
    ); // byte rate
    pos += 4;
    buffer.setUint16(
      pos,
      numChannels * bytesPerSample,
      Endian.little,
    ); // block align
    pos += 2;
    buffer.setUint16(pos, bitsPerSample, Endian.little);
    pos += 2;

    // --- data sub-chunk ---
    writeString('data');
    buffer.setUint32(pos, dataSize, Endian.little);
    pos += 4;

    for (final sample in samples) {
      // Clip to [-1.0, 1.0] then convert to int16
      final clamped = sample.clamp(-1.0, 1.0);
      final int16Value = (clamped * 32767.0).round().clamp(-32768, 32767);
      buffer.setInt16(pos, int16Value, Endian.little);
      pos += 2;
    }

    return buffer.buffer.asUint8List(0, pos);
  }

  /// Writes [samples] (normalised doubles in [-1.0, 1.0]) as a 16-bit PCM
  /// mono WAV file to [path] at [sampleRate].
  static void writeWav(String path, List<double> samples, int sampleRate) {
    final bytes = writeWavBytes(samples, sampleRate: sampleRate);
    File(path).writeAsBytesSync(bytes);
  }
}
