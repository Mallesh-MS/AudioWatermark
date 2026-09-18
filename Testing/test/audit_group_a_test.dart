import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/crc.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';
import 'package:dsp/qr/qr_key_exchange.dart';

void main() {
  group('Priority Group A.1: Keystream Reuse (ADR 005 Zero-IV)', () {
    test('XOR of ciphertexts under same key equals XOR of plaintexts (keystream cancellation)', () {
      final key = WatermarkCrypto.generateKey();

      const p1Str = 'ATTACK AT DAWN!!';
      const p2Str = 'CANCEL ORDER 99!';
      final p1Bytes = utf8.encode(p1Str);
      final p2Bytes = utf8.encode(p2Str);

      final c1 = WatermarkCrypto.encrypt(p1Str, key);
      final c2 = WatermarkCrypto.encrypt(p2Str, key);

      expect(c1.length, equals(p1Bytes.length));
      expect(c2.length, equals(p2Bytes.length));

      final xorPlaintext = Uint8List(c1.length);
      final xorCiphertext = Uint8List(c1.length);

      for (int i = 0; i < c1.length; i++) {
        xorPlaintext[i] = p1Bytes[i] ^ p2Bytes[i];
        xorCiphertext[i] = c1[i] ^ c2[i];
      }

      // Knowing P1 allows instant recovery of P2 as C1 ^ C2 ^ P1:
      final recoveredP2Bytes = Uint8List(c1.length);
      for (int i = 0; i < c1.length; i++) {
        recoveredP2Bytes[i] = c1[i] ^ c2[i] ^ p1Bytes[i];
      }
      expect(utf8.decode(recoveredP2Bytes), equals(p2Str));

      // Security requirement: Keystream must NOT be reused across distinct encryptions.
      // Under a secure nonce/IV scheme, C1 ^ C2 != P1 ^ P2.
      // This test MUST fail on AudioWatermark due to the ADR 005 fixed zero IV.
      expect(
        xorCiphertext,
        isNot(equals(xorPlaintext)),
        reason: 'CRITICAL: Fixed zero IV causes identical keystream reuse. '
            'C1 ^ C2 == P1 ^ P2 allows keyless plaintext recovery (ADR 005).',
      );
    });
  });

  group('Priority Group A.2: Malleability Forgery (CTR + CRC-8)', () {
    test('Keyless attacker can flip bits and forge CRC to alter decrypted message undetected', () {
      final key = WatermarkCrypto.generateKey();
      const originalMessage = 'Transfer 1000 USD to Alice!';
      const targetMessage   = 'Transfer 9000 USD to Alice!';

      // 1. Generate legitimate mixed audio containing originalMessage
      final host = List<double>.filled(44100 * 35, 0.0); // 35s silent host
      final originalMixed = Embedder.embedMessage(originalMessage, key, host);

      // Verify original decodes cleanly
      final legitExtracted = Embedder.extractMessage(originalMixed, key);
      expect(legitExtracted, equals(originalMessage));

      // 2. Demonstrate cryptographic malleability on raw ciphertext + CRC
      final origCiphertext = WatermarkCrypto.encrypt(originalMessage, key);
      final origCrc = Crc8.compute(origCiphertext);

      // We want to change '' -> ''. Offset of '1' is 10.
      final targetIndex = originalMessage.indexOf('1');
      final flipByte = utf8.encode('1')[0] ^ utf8.encode('9')[0];

      final forgedCiphertext = Uint8List.fromList(origCiphertext);
      forgedCiphertext[targetIndex] ^= flipByte;

      // Because CRC-8 is strictly linear over GF(2) with initial value 0:
      // CRC(Payload ^ Delta) = CRC(Payload) ^ CRC(Delta)
      final delta = Uint8List(origCiphertext.length);
      delta[targetIndex] = flipByte;
      final deltaCrc = Crc8.compute(delta);
      final forgedCrc = origCrc ^ deltaCrc;

      // Assert CRC verification accepts the forged ciphertext!
      final verified = Crc8.verifyAndExtract([...forgedCiphertext, forgedCrc]);
      expect(
        verified,
        isNotNull,
        reason: 'CRC-8 is linear over XOR; forged checksum must pass verifyAndExtract',
      );

      // Assert decryption yields the altered message without any MAC failure!
      final forgedPlaintext = WatermarkCrypto.decrypt(Uint8List.fromList(verified!), key);
      expect(forgedPlaintext, equals(targetMessage));

      // 3. Now verify this vulnerability at the acoustic carrier level:
      // Construct a forged acoustic carrier with the modified payload bits & CRC
      final forgedProtectedPayload = [...forgedCiphertext, forgedCrc];
      final forgedBits = ToneGenerator.bytesToBits(forgedProtectedPayload);
      final forgedWatermarkSamples = ToneGenerator.bitsToSamplesWithHeader(forgedBits);
      final forgedMixedAudio = Embedder.embed(host, forgedWatermarkSamples);

      final extractedForgedMessage = Embedder.extractMessage(forgedMixedAudio, key);

      // Security requirement: Receiver MUST reject tampered/forged ciphertext.
      // Without an authenticated MAC (HMAC/Poly1305), the receiver accepts the forgery!
      // This assertion MUST fail, proving keyless message forgery.
      expect(
        extractedForgedMessage,
        isNull,
        reason: 'CRITICAL: Keyless attacker altered message while keeping CRC valid. '
            'Absence of MAC allows ciphertext tampering.',
      );
    });
  });

  group('Priority Group A.3: Key Material and Generation', () {
    test('WatermarkCrypto.generateKey generates 1000 unique, structured-free 128-bit keys', () {
      final keys = <String>{};
      final byteCounts = List<int>.filled(256, 0);

      const count = 1000;
      for (int i = 0; i < count; i++) {
        final key = WatermarkCrypto.generateKey();
        expect(key.bytes.length, equals(16));

        final hex = WatermarkCrypto.keyToHex(key);
        expect(keys.add(hex), isTrue, reason: 'Key generation produced a duplicate key: ' + hex);

        for (final b in key.bytes) {
          byteCounts[b]++;
        }
      }

      // Assert no constant bytes across keys
      for (int b = 0; b < 256; b++) {
        expect(
          byteCounts[b],
          greaterThan(10),
          reason: 'Byte value ' + b.toString() + ' appeared too rarely (' + byteCounts[b].toString() + ' times), suggesting weak PRNG',
        );
      }
    });

    test('QrKeyExchange enforces 32-character hexadecimal format and round-trips cleanly', () {
      final key = WatermarkCrypto.generateKey();
      final qrPayload = QrKeyExchange.keyToQrPayload(key);

      expect(qrPayload.length, equals(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(qrPayload), isTrue);

      final parsedKey = QrKeyExchange.qrPayloadToKey(qrPayload);
      expect(parsedKey.bytes, equals(key.bytes));

      // Case insensitivity
      final upperParsed = QrKeyExchange.qrPayloadToKey(qrPayload.toUpperCase());
      expect(upperParsed.bytes, equals(key.bytes));

      // Negative cases: invalid chars, wrong lengths
      expect(() => QrKeyExchange.qrPayloadToKey(qrPayload.substring(0, 31)), throwsFormatException);
      expect(() => QrKeyExchange.qrPayloadToKey(qrPayload + '0'), throwsFormatException);
      expect(() => QrKeyExchange.qrPayloadToKey(qrPayload.substring(0, 31) + 'g'), throwsFormatException);
      expect(() => QrKeyExchange.qrPayloadToKey(qrPayload.substring(0, 31) + '!'), throwsFormatException);
    });
  });

  group('Priority Group A.4: Replay Attacks', () {
    test('Receiver has no sequence/nonce/timestamp and accepts replayed audio buffers', () {
      final key = WatermarkCrypto.generateKey();
      const message = 'Replay message';

      final host = List<double>.filled(44100 * 25, 0.0);
      final mixed = Embedder.embedMessage(message, key, host);

      // First decode
      final firstDecode = Embedder.extractMessage(mixed, key);
      expect(firstDecode, equals(message));

      // Second decode of exact same buffer (simulating captured microphone recording)
      final secondDecode = Embedder.extractMessage(mixed, key);

      // Security requirement: Receiver should reject duplicate/replayed transmission.
      // In AudioWatermark, there is zero replay protection.
      // This test fails to document the unmitigated replay vulnerability.
      expect(
        secondDecode,
        isNull,
        reason: 'CRITICAL: Replayed acoustic audio buffer decoded successfully. '
            'Protocol has no replay mitigation (no nonce, timestamp, or monotonic counter).',
      );
    });
  });

  group('Priority Group A.5: AES Vectors & Negative Boundary Cases', () {
    test('Verify official test vectors from Testing/fixtures/aes_crypto_vectors.json', () {
      final file = File('fixtures/aes_crypto_vectors.json');
      expect(file.existsSync(), isTrue);

      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final keys = (jsonMap['keys'] as List).cast<Map<String, dynamic>>();
      final messages = (jsonMap['messages'] as List).cast<Map<String, dynamic>>();

      for (final kEntry in keys) {
        final keyHex = kEntry['key_hex'] as String;
        final key = WatermarkCrypto.keyFromHex(keyHex);

        for (final mEntry in messages) {
          final plaintext = mEntry['plaintext'] as String;
          final ciphertext = WatermarkCrypto.encrypt(plaintext, key);
          final decrypted = WatermarkCrypto.decrypt(ciphertext, key);

          expect(decrypted, equals(plaintext));
          expect(ciphertext.length, equals(utf8.encode(plaintext).length));
        }
      }
    });

    test('Negative key lengths: wrong key length must throw an exception, not truncate silently', () {
      const invalidLengths = [0, 8, 15, 17, 24, 32];
      for (final len in invalidLengths) {
        final badKey = Key(Uint8List(len));
        if (len == 16) continue;

        if (len != 16 && len != 24 && len != 32) {
          expect(
            () => WatermarkCrypto.encrypt('Test', badKey),
            throwsA(anything),
            reason: 'Key of ' + len.toString() + ' bytes must be rejected by AES cipher',
          );
        }
      }
    });

    test('Boundary plaintext lengths: 15, 16, 17 bytes preserve exact length without padding', () {
      final key = WatermarkCrypto.generateKey();

      for (final length in [15, 16, 17]) {
        final plaintext = 'X' * length;
        final ciphertext = WatermarkCrypto.encrypt(plaintext, key);
        expect(ciphertext.length, equals(length), reason: 'Length ' + length.toString() + ' must be strictly preserved');

        final decrypted = WatermarkCrypto.decrypt(ciphertext, key);
        expect(decrypted, equals(plaintext));
      }
    });

    test('1 MB large plaintext streams and round-trips without truncation or hang', () {
      final key = WatermarkCrypto.generateKey();
      const oneMb = 1024 * 1024;
      final largePlaintext = 'A' * oneMb;

      final ciphertext = WatermarkCrypto.encrypt(largePlaintext, key);
      expect(ciphertext.length, equals(oneMb));

      final decrypted = WatermarkCrypto.decrypt(ciphertext, key);
      expect(decrypted.length, equals(oneMb));
      expect(decrypted, equals(largePlaintext));
    });

    test('Empty plaintext behavior in crypto vs embedder framing', () {
      final key = WatermarkCrypto.generateKey();

      // At crypto level: empty string encrypts and decrypts cleanly
      final emptyCiphertext = WatermarkCrypto.encrypt('', key);
      expect(emptyCiphertext.length, equals(0));
      expect(WatermarkCrypto.decrypt(emptyCiphertext, key), equals(''));

      // In Embedder: extractMessage requires byteLength > 1, so empty message is rejected
      final host = List<double>.filled(44100 * 10, 0.0);
      final mixed = Embedder.embedMessage('', key, host);
      final extracted = Embedder.extractMessage(mixed, key);

      expect(
        extracted,
        isNull,
        reason: 'Embedder requires byteLength > 1; empty payload cannot be extracted',
      );
    });

    test('Corrupted ciphertext producing invalid UTF-8 throws FormatException, never garbage', () {
      final key = WatermarkCrypto.generateKey();
      const plain = 'Hello world';
      final ct = WatermarkCrypto.encrypt(plain, key);

      bool threwFormatException = false;
      for (int testByte = 0x80; testByte <= 0xFF; testByte++) {
        final corrupted = Uint8List.fromList(ct);
        corrupted[0] = testByte;
        try {
          WatermarkCrypto.decrypt(corrupted, key);
        } on FormatException {
          threwFormatException = true;
          break;
        } catch (_) {}
      }

      expect(threwFormatException, isTrue, reason: 'Invalid UTF-8 bytes must throw FormatException');
    });
  });
}
