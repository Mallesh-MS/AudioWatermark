import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:dsp/audio/wav_utils.dart';

Uint8List createWavHeader({
  int audioFormat = 1,
  int numChannels = 1,
  int sampleRate = 44100,
  int bitsPerSample = 16,
  int dataSize = 0,
  List<int>? extraChunkBeforeFmt,
  bool oddSizedFmt = false,
}) {
  final builder = BytesBuilder();

  // fmt chunk data
  final fmtData = ByteData(16);
  fmtData.setUint16(0, audioFormat, Endian.little);
  fmtData.setUint16(2, numChannels, Endian.little);
  fmtData.setUint32(4, sampleRate, Endian.little);
  final byteRate = numChannels == 0 ? 0 : sampleRate * numChannels * (bitsPerSample ~/ 8);
  fmtData.setUint32(8, byteRate, Endian.little);
  final blockAlign = numChannels == 0 ? 0 : numChannels * (bitsPerSample ~/ 8);
  fmtData.setUint16(12, blockAlign, Endian.little);
  fmtData.setUint16(14, bitsPerSample, Endian.little);

  final chunks = BytesBuilder();

  if (extraChunkBeforeFmt != null) {
    chunks.add(extraChunkBeforeFmt);
  }

  // fmt chunk
  chunks.add('fmt '.codeUnits);
  final fmtSizeData = ByteData(4);
  fmtSizeData.setUint32(0, 16, Endian.little);
  chunks.add(fmtSizeData.buffer.asUint8List());
  chunks.add(fmtData.buffer.asUint8List());

  // data chunk header
  chunks.add('data'.codeUnits);
  final dataSizeData = ByteData(4);
  dataSizeData.setUint32(0, dataSize, Endian.little);
  chunks.add(dataSizeData.buffer.asUint8List());

  final chunkBytes = chunks.toBytes();
  final riffHeader = ByteData(12);
  riffHeader.setUint8(0, 0x52); // R
  riffHeader.setUint8(1, 0x49); // I
  riffHeader.setUint8(2, 0x46); // F
  riffHeader.setUint8(3, 0x46); // F
  riffHeader.setUint32(4, 4 + chunkBytes.length, Endian.little);
  riffHeader.setUint8(8, 0x57);  // W
  riffHeader.setUint8(9, 0x41);  // A
  riffHeader.setUint8(10, 0x56); // V
  riffHeader.setUint8(11, 0x45); // E

  builder.add(riffHeader.buffer.asUint8List());
  builder.add(chunkBytes);

  return builder.toBytes();
}

void main() {
  group('Priority Group D.14: Fuzzing WavUtils Robustness', () {
    test('Truncated header (< 12 bytes) raises ArgumentError', () {
      expect(
        () => WavUtils.readWavBytes(Uint8List(8)),
        throwsArgumentError,
        reason: 'Header shorter than 12 bytes must raise ArgumentError',
      );
    });

    test('Declared data size > buffer size throws RangeError instead of typed error', () {
      // Declared data size 100,000 bytes, but actual audio data has 0 bytes:
      final wav = createWavHeader(dataSize: 100000);
      // In WavUtils: allocates List<double>.filled(50000, 0.0), then in loop calls getInt16(44)
      // which throws unhandled RangeError instead of ArgumentError:
      expect(
        () => WavUtils.readWavBytes(wav),
        throwsA(isA<RangeError>()),
        reason: 'DEFECT: Spoofed data size leads to unhandled RangeError rather than ArgumentError',
      );
    });

    test('Zero channels causes IntegerDivisionByZeroException / UnsupportedError', () {
      final wav = createWavHeader(numChannels: 0, dataSize: 100);
      // WavUtils line 89: totalFrames = totalSampleValues ~/ numChannels (div by zero!)
      expect(
        () => WavUtils.readWavBytes(wav),
        throwsA(anyOf(isA<UnsupportedError>(), isA<IntegerDivisionByZeroException>())),
        reason: 'DEFECT: Zero channels causes uncaught division by zero exception',
      );
    });

    test('Zero sample rate is silently accepted without validation', () {
      final wav = createWavHeader(sampleRate: 0, dataSize: 0);
      final wavData = WavUtils.readWavBytes(wav);
      expect(wavData.sampleRate, equals(0), reason: 'DEFECT: Zero sample rate is accepted silently');
    });

    test('24-bit PCM raises typed ArgumentError', () {
      final wav = createWavHeader(bitsPerSample: 24, dataSize: 0);
      expect(
        () => WavUtils.readWavBytes(wav),
        throwsArgumentError,
        reason: 'Unsupported 24-bit bit depth must raise ArgumentError',
      );
    });

    test('32-bit float audio format raises typed ArgumentError', () {
      final wav = createWavHeader(audioFormat: 3, bitsPerSample: 32, dataSize: 0);
      expect(
        () => WavUtils.readWavBytes(wav),
        throwsArgumentError,
        reason: 'Unsupported IEEE float format must raise ArgumentError',
      );
    });

    test('LIST chunk before fmt chunk is parsed cleanly', () {
      final listChunk = BytesBuilder();
      listChunk.add('LIST'.codeUnits);
      final listSize = ByteData(4);
      listSize.setUint32(0, 8, Endian.little);
      listChunk.add(listSize.buffer.asUint8List());
      listChunk.add(List<int>.filled(8, 0));

      final wav = createWavHeader(extraChunkBeforeFmt: listChunk.toBytes(), dataSize: 0);
      final wavData = WavUtils.readWavBytes(wav);
      expect(wavData.sampleRate, equals(44100), reason: 'Chunks preceding fmt must be skipped cleanly');
    });
  });
}
