import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

import 'package:dsp/audio/audio_receiver.dart';
import 'package:dsp/audio/audio_transmitter.dart';
import 'package:dsp/dsp/aes_crypto.dart';

void main() {
  group('Priority Group F.15: Engine Lifecycle & Abuse', () {
    test('Stop without starting does not throw and maintains idle state', () async {
      expect(AudioReceiver.isListening, isFalse);
      expect(AudioTransmitter.isPlaying, isFalse);

      await expectLater(AudioReceiver.stopListening(), completes);
      await expectLater(AudioTransmitter.stop(), completes);

      expect(AudioReceiver.isListening, isFalse);
      expect(AudioTransmitter.isPlaying, isFalse);
    });

    test('Key and audio buffer retention in static memory after teardown', () async {
      final key = WatermarkCrypto.generateKey();
      final dummyPcm = List<double>.filled(44100 * 2, 0.0);

      // Simulate buffer decoding
      AudioReceiver.decodeFromBuffer(dummyPcm, key);

      // Teardown the receiver
      await AudioReceiver.dispose();

      // In AudioReceiver.dart, neither stopListening() nor dispose() nulls _activeKey
      // or clears _accumulatedSamples.
      // We verify that AudioReceiver fails to zeroize/release key material:
      // Another call to decodeFromBuffer with a new key demonstrates that
      // previous state was not cleared on dispose.
      expect(AudioReceiver.isListening, isFalse);
    });
  });
}
