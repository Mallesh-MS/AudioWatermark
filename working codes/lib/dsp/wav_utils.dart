import 'dart:io';
import 'dart:typed_data';

class WavAudio {
  final int sampleRate;
  final int channels;
  final List<double> samples;

  WavAudio({
    required this.sampleRate,
    required this.channels,
    required this.samples,
  });
}

WavAudio readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  return readWavBytes(bytes);
}

WavAudio readWavBytes(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  if (bytes.length < 12 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw ArgumentError('Not a valid WAV byte buffer');
  }

  int? fmtOffset;
  int? dataOffset;
  int? dataSize;

  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    if (id == 'fmt ') {
      fmtOffset = offset + 8;
    } else if (id == 'data') {
      dataOffset = offset + 8;
      dataSize = chunkSize;
    }
    offset += 8 + chunkSize + (chunkSize % 2);
  }

  if (fmtOffset == null || dataOffset == null || dataSize == null) {
    throw ArgumentError('WAV byte buffer is missing required fmt/data chunks');
  }

  final audioFormat = data.getUint16(fmtOffset, Endian.little);
  if (audioFormat != 1) {
    throw ArgumentError('Only PCM WAV files are supported');
  }

  final channels = data.getUint16(fmtOffset + 2, Endian.little);
  final sampleRate = data.getUint32(fmtOffset + 4, Endian.little);
  final bitsPerSample = data.getUint16(fmtOffset + 14, Endian.little);

  if (bitsPerSample != 16) {
    throw ArgumentError('Only 16-bit PCM WAV files are supported');
  }

  final sampleCount = dataSize ~/ (bitsPerSample ~/ 8);
  final monoSamples = <double>[];

  for (int index = 0; index < sampleCount; index += channels) {
    var sum = 0.0;
    for (int ch = 0; ch < channels; ch++) {
      final sampleIndex = dataOffset + ((index + ch) * 2);
      final pcm = data.getInt16(sampleIndex, Endian.little);
      sum += pcm / 32768.0;
    }
    monoSamples.add(sum / channels);
  }

  return WavAudio(sampleRate: sampleRate, channels: 1, samples: monoSamples);
}

void writeWav(String path, WavAudio audio) {
  final dataSize = audio.samples.length * 2;
  final buffer = BytesBuilder();
  const chunkSize = 16;

  buffer.add('RIFF'.codeUnits);
  buffer.add((40 + dataSize).toBytesLE(4));
  buffer.add('WAVE'.codeUnits);
  buffer.add('fmt '.codeUnits);
  buffer.add(chunkSize.toBytesLE(4));
  buffer.add((1).toBytesLE(2));
  buffer.add(audio.channels.toBytesLE(2));
  buffer.add(audio.sampleRate.toBytesLE(4));
  buffer.add((audio.sampleRate * audio.channels * 2).toBytesLE(4));
  buffer.add((audio.channels * 2).toBytesLE(2));
  buffer.add((16).toBytesLE(2));
  buffer.add('data'.codeUnits);
  buffer.add(dataSize.toBytesLE(4));

  for (final sample in audio.samples) {
    final clamped = sample.clamp(-1.0, 1.0);
    final value = (clamped * 32767.0).round().clamp(-32768, 32767);
    buffer.add(value.toBytesLE(2));
  }

  File(path).writeAsBytesSync(buffer.toBytes());
}

extension _IntBytes on int {
  List<int> toBytesLE(int byteLength) {
    final bytes = Uint8List(byteLength);
    final b = ByteData.sublistView(bytes);
    switch (byteLength) {
      case 2:
        b.setInt16(0, this, Endian.little);
        break;
      case 4:
        b.setInt32(0, this, Endian.little);
        break;
      default:
        throw ArgumentError('Unsupported byte length $byteLength');
    }
    return bytes;
  }
}
