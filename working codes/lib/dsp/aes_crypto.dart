/// AES-128-CTR crypto module for audio watermarking.
///
/// Uses a fixed 16-byte zero IV (per ADR 005). No padding, no framing.
/// Ciphertext length equals plaintext UTF-8 byte length exactly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

class WatermarkCrypto {
  /// Fixed 16-byte zero IV for CTR mode (per ADR 005).
  static final IV _fixedIV = IV(Uint8List(16));

  /// Generates a cryptographically secure random 128-bit (16 byte) key.
  static Key generateKey() {
    return Key.fromSecureRandom(16);
  }

  /// Encrypts [plaintext] with AES-128 in CTR mode, NO padding.
  /// Uses a FIXED 16-byte zero IV.
  /// Returns raw ciphertext bytes (same length as plaintext).
  static Uint8List encrypt(String plaintext, Key key) {
    final encrypter = Encrypter(AES(key, mode: AESMode.ctr, padding: null));
    final encrypted = encrypter.encryptBytes(utf8.encode(plaintext), iv: _fixedIV);
    return Uint8List.fromList(encrypted.bytes);
  }

  /// Decrypts [ciphertext] back to the original string using the same
  /// fixed zero IV and AES-128-CTR.
  /// Throws on invalid UTF-8 rather than silently succeeding with corrupted output.
  static String decrypt(Uint8List ciphertext, Key key) {
    final encrypter = Encrypter(AES(key, mode: AESMode.ctr, padding: null));
    final decrypted = encrypter.decryptBytes(Encrypted(ciphertext), iv: _fixedIV);
    return utf8.decode(decrypted);
  }

  /// Converts a [Key] to a 32-character hex string.
  static String keyToHex(Key key) {
    return key.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Creates a [Key] from a 32-character hex string.
  static Key keyFromHex(String hex) {
    if (hex.length != 32) {
      throw ArgumentError('Hex string must be 32 characters (16 bytes)');
    }
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return Key(bytes);
  }
}