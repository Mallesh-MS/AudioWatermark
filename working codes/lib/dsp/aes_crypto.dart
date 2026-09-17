import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

const int _keyLengthBytes = 16;
final IV _zeroIV = IV(Uint8List(_keyLengthBytes));

Uint8List generateKey() {
  return Key.fromSecureRandom(_keyLengthBytes).bytes;
}

Uint8List encrypt(String plaintext, Uint8List key) {
  return _encryptBytes(plaintext, key);
}

Uint8List _encryptBytes(String plaintext, Uint8List key) {
  final cipherKey = Key(key);
  final encrypter = Encrypter(AES(cipherKey, mode: AESMode.ctr, padding: null));
  final encrypted = encrypter.encryptBytes(
    utf8.encode(plaintext),
    iv: _zeroIV,
  );
  return Uint8List.fromList(encrypted.bytes);
}

String decrypt(Uint8List ciphertext, Uint8List key) {
  return _decryptBytes(ciphertext, key);
}

String _decryptBytes(Uint8List ciphertext, Uint8List key) {
  final cipherKey = Key(key);
  final encrypter = Encrypter(AES(cipherKey, mode: AESMode.ctr, padding: null));
  final decrypted = encrypter.decryptBytes(
    Encrypted(ciphertext),
    iv: _zeroIV,
  );
  return utf8.decode(decrypted);
}

class WatermarkCrypto {
  static Key generateKey() => Key.fromSecureRandom(_keyLengthBytes);

  static Uint8List encrypt(String plaintext, Key key) {
    return _encryptBytes(plaintext, key.bytes);
  }

  static String decrypt(Uint8List ciphertext, Key key) {
    return _decryptBytes(ciphertext, key.bytes);
  }

  static String keyToHex(Key key) {
    return key.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
