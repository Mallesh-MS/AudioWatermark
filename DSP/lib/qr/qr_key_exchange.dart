import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

import '../dsp/aes_crypto.dart';

/// Out-of-band QR code key exchange utility.
///
/// Encodes a 128-bit (16-byte) AES key as a raw 32-character hexadecimal
/// string payload for QR generation, and safely parses scanned QR text back
/// into a validated [Key] instance.
class QrKeyExchange {
  static final RegExp _hexRegex = RegExp(r'^[0-9a-fA-F]{32}$');

  /// Encodes [key] (via [WatermarkCrypto.keyToHex], 32-char hex) as QR data.
  ///
  /// Keeps payload as raw hex with no extra wrapping or JSON envelope.
  static String keyToQrPayload(Key key) {
    return WatermarkCrypto.keyToHex(key);
  }

  /// Parses scanned QR text back into a [Key].
  ///
  /// Throws [FormatException] on malformed input (wrong length, non-hex chars)
  /// rather than silently producing a corrupted key.
  /// Handles case-insensitivity seamlessly.
  static Key qrPayloadToKey(String scannedText) {
    final trimmed = scannedText.trim();
    if (trimmed.length != 32) {
      throw FormatException(
        'Scanned QR key must be exactly 32 hex characters (got ${trimmed.length})',
        scannedText,
      );
    }
    if (!_hexRegex.hasMatch(trimmed)) {
      throw FormatException(
        'Scanned QR key contains invalid non-hexadecimal characters',
        scannedText,
      );
    }
    try {
      final normalizedHex = trimmed.toLowerCase();
      final bytes = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        bytes[i] = int.parse(normalizedHex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return Key(bytes);
    } catch (e) {
      throw FormatException(
        'Failed to parse hexadecimal key bytes: $e',
        scannedText,
      );
    }
  }
}
