import 'dart:typed_data';

import 'aes_crypto.dart';
import 'embedder.dart';
import 'goertzel_decoder.dart';
import 'tone_generator.dart';

List<double> transmitMessage(String message, Uint8List key, List<double> hostSamples) {
  final ciphertext = encrypt(message, key);
  final payloadBits = bytesToBits(ciphertext);
  if (payloadBits.length > 255) {
    throw ArgumentError.value(
      payloadBits.length,
      'payloadBits.length',
      'message exceeds the 255-bit payload cap for the in-memory watermark frame',
    );
  }
  final frame = encodeFrame(payloadBits);
  return embed(hostSamples, frame, 0.02);
}

String? receiveMessage(List<double> mixedSamples, Uint8List key) {
  final start = detectPreamble(mixedSamples);
  if (start == null) {
    return null;
  }

  final payloadBitLength = decodeLengthHeader(mixedSamples, start);
  if (payloadBitLength < 0 || payloadBitLength > 255) {
    return null;
  }

  final payloadStart = start + 13230 + (3 * 8 * 4410);
  final payloadBits = <int>[];
  for (int index = 0; index < payloadBitLength; index++) {
    final bitStart = payloadStart + (index * 4410);
    final bitEnd = bitStart + 4410;
    if (bitEnd > mixedSamples.length) {
      return null;
    }
    payloadBits.add(decodeBit(mixedSamples.sublist(bitStart, bitEnd)));
  }

  try {
    final bytes = bitsToBytes(payloadBits);
    return decrypt(Uint8List.fromList(bytes), key);
  } catch (_) {
    return null;
  }
}
