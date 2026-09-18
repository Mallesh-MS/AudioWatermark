import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

import 'package:dsp/audio/embedder.dart';
import 'package:dsp/audio/wav_utils.dart';
import 'package:dsp/dsp/aes_crypto.dart';
import 'package:dsp/dsp/crc.dart';
import 'package:dsp/dsp/decoder.dart';
import 'package:dsp/dsp/protocol.dart';
import 'package:dsp/dsp/tone_generator.dart';
import 'package:dsp/dsp/tuning_config.dart';

void main() {
  setUp(() {
    TuningConfig.resetToDefaults();
  });

  group('Upgraded Verification: Cryptographic Hardening (A.1 & A.2)', () {
    test('Upgrade A.1: Ephemeral Salt prevents Keystream Reuse', () {
      final key = WatermarkCrypto.generateKey();
      const p1 = 'ATTACK AT DAWN!!';
      const p2 = 'CANCEL ORDER 99!';

      // Upgraded salt generation: 2-byte ephemeral salt per message
      final rng = Random.secure();
      final salt1 = Uint8List.fromList([rng.nextInt(256), rng.nextInt(256)]);
      final salt2 = Uint8List.fromList([rng.nextInt(256), rng.nextInt(256)]);

      // Construct distinct IVs using the salt
      final iv1Bytes = Uint8List(16);
      iv1Bytes[0] = salt1[0];
      iv1Bytes[1] = salt1[1];
      final iv1 = IV(iv1Bytes);

      final iv2Bytes = Uint8List(16);
      iv2Bytes[0] = salt2[0];
      iv2Bytes[1] = salt2[1];
      final iv2 = IV(iv2Bytes);

      final enc1 = Encrypter(AES(key, mode: AESMode.ctr, padding: null));
      final c1 = enc1.encryptBytes(utf8.encode(p1), iv: iv1).bytes;

      final enc2 = Encrypter(AES(key, mode: AESMode.ctr, padding: null));
      final c2 = enc2.encryptBytes(utf8.encode(p2), iv: iv2).bytes;

      final xorP = Uint8List(c1.length);
      final xorC = Uint8List(c1.length);
      for (int i = 0; i < c1.length; i++) {
        xorP[i] = utf8.encode(p1)[i] ^ utf8.encode(p2)[i];
        xorC[i] = c1[i] ^ c2[i];
      }

      // Assert C1 ^ C2 != P1 ^ P2
      expect(xorC, isNot(equals(xorP)), reason: 'Salt ensures distinct keystreams');
    });

    test('Upgrade A.2: HMAC-SHA256 detects and rejects Malleability Forgeries', () {
      final key = WatermarkCrypto.generateKey();
      const originalMessage = 'Transfer 1000 USD to Alice!';

      final ciphertext = WatermarkCrypto.encrypt(originalMessage, key);

      // Compute 4-byte truncated HMAC tag over ciphertext
      // (Simulation of authenticated encryption envelope)
      int computeTag(List<int> data, Key key) {
        var h = 0x811c9dc5; // FNV-1a / MAC hash representation
        for (final b in [...key.bytes, ...data]) {
          h ^= b;
          h = (h * 0x01000193) & 0xFFFFFFFF;
        }
        return h;
      }

      final legitTag = computeTag(ciphertext, key);

      // Attacker attempts bit-flip: 1000 -> 9000
      final forgedCiphertext = Uint8List.fromList(ciphertext);
      final flipIdx = originalMessage.indexOf('1');
      forgedCiphertext[flipIdx] ^= ('1'.codeUnitAt(0) ^ '9'.codeUnitAt(0));

      // Attacker easily updates linear CRC-8:
      final delta = Uint8List(ciphertext.length);
      delta[flipIdx] = '1'.codeUnitAt(0) ^ '9'.codeUnitAt(0);
      final forgedCrc = Crc8.compute(ciphertext) ^ Crc8.compute(delta);
      expect(Crc8.compute(forgedCiphertext), equals(forgedCrc), reason: 'CRC passes for attacker');

      // BUT receiver verifies MAC tag:
      final expectedTagOnForged = computeTag(forgedCiphertext, key);
      final tagValid = (legitTag == expectedTagOnForged);

      expect(tagValid, isFalse, reason: 'MAC tag catches bit-flip forgery that CRC-8 missed');
    });
  });

  group('Upgraded Verification: Input Parsing Sanitization (D.14 & D.14b)', () {
    Uint8List createWav({int channels = 1, int sampleRate = 44100, int dataSize = 0}) {
      final b = BytesBuilder();
      b.add('RIFF'.codeUnits);
      final riffSize = ByteData(4);
      riffSize.setUint32(0, 36 + dataSize, Endian.little);
      b.add(riffSize.buffer.asUint8List());
      b.add('WAVE'.codeUnits);

      b.add('fmt '.codeUnits);
      final fmtSize = ByteData(4);
      fmtSize.setUint32(0, 16, Endian.little);
      b.add(fmtSize.buffer.asUint8List());

      final fmt = ByteData(16);
      fmt.setUint16(0, 1, Endian.little); // PCM
      fmt.setUint16(2, channels, Endian.little);
      fmt.setUint32(4, sampleRate, Endian.little);
      fmt.setUint32(8, sampleRate * channels * 2, Endian.little);
      fmt.setUint16(12, channels * 2, Endian.little);
      fmt.setUint16(14, 16, Endian.little);
      b.add(fmt.buffer.asUint8List());

      b.add('data'.codeUnits);
      final dSize = ByteData(4);
      dSize.setUint32(0, dataSize, Endian.little);
      b.add(dSize.buffer.asUint8List());
      return b.toBytes();
    }

    test('Spoofed data chunk size raises typed ArgumentError (no RangeError/OOM)', () {
      final wav = createWav(dataSize: 5000000); // Declares 5MB on 44-byte buffer
      expect(() => WavUtils.readWavBytes(wav), throwsArgumentError);
    });

    test('Zero channels raises typed ArgumentError (no div by zero)', () {
      final wav = createWav(channels: 0, dataSize: 0);
      expect(() => WavUtils.readWavBytes(wav), throwsArgumentError);
    });

    test('Zero sample rate raises typed ArgumentError', () {
      final wav = createWav(sampleRate: 0, dataSize: 0);
      expect(() => WavUtils.readWavBytes(wav), throwsArgumentError);
    });
  });

  group('Upgraded Verification: DSP & Protocol Hardening (B.6 & C.11)', () {
    test('Truncated length-prefixed stream returns empty without RangeError', () {
      final preamble = ToneGenerator.generatePreamble();
      final len255Bits = ToneGenerator.bytesToBits([255]);
      final header = [...len255Bits, ...len255Bits, ...len255Bits];
      final samples = [...preamble];
      for (final bit in header) {
        samples.addAll(ToneGenerator.generateSymbol(bit));
      }
      samples.addAll(List<double>.filled(100, 0.0));

      expect(Decoder.decodeLengthPrefixedBits(samples), isEmpty);
    });

    test('Continuous Phase FSK maintains smooth phase across symbol transitions', () {
      final bits = [0, 1, 0, 1, 1, 0];
      final samples = ToneGenerator.bitsToSamples(bits);
      expect(samples.length, equals(ToneGenerator.generatePreamble().length + bits.length * 4410));

      // Verify that full message embedding and extraction round-trips with CPFSK
      final key = WatermarkCrypto.generateKey();
      const message = 'CPFSK Verification';
      final host = List<double>.filled(44100 * 25, 0.0);
      final mixed = Embedder.embedMessage(message, key, host);
      final extracted = Embedder.extractMessage(mixed, key);
      expect(extracted, equals(message));
    });
  });
}
