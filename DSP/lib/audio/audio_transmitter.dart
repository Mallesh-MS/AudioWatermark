import 'dart:async';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../audio/embedder.dart';
import '../audio/wav_utils.dart';
import '../dsp/protocol.dart';

class AudioTransmitter {
  static FlutterSoundPlayer? _player;
  static bool _isPlaying = false;

  static bool get isPlaying => _isPlaying;

  /// Encrypts [message] with [key], embeds it into [hostSamples] via
  /// Stage 3's [Embedder.embedMessage], converts the resulting mixed
  /// samples to a WAV byte buffer ([WavUtils.writeWavBytes]), and plays
  /// it through the device speaker via [FlutterSoundPlayer].
  ///
  /// Calls [onStatus] with human-readable progress ("Encrypting...",
  /// "Embedding...", "Playing...", "Done") and [onDone] when playback
  /// finishes.
  static Future<void> transmit({
    required String message,
    required Key key,
    required List<double> hostSamples,
    required void Function(String) onStatus,
    required void Function() onDone,
    FlutterSoundPlayer? player,
    int offset = 0,
  }) async {
    try {
      await stop();

      onStatus('Encrypting & embedding...');
      final mixedSamples = Embedder.embedMessage(
        message,
        key,
        hostSamples,
        offset: offset,
      );

      onStatus('Generating audio buffer...');
      final wavBytes = WavUtils.writeWavBytes(
        mixedSamples,
        sampleRate: sampleRate,
      );

      final activePlayer = player ?? (_player ??= FlutterSoundPlayer());
      if (!activePlayer.isOpen()) {
        await activePlayer.openPlayer();
      }

      _isPlaying = true;
      onStatus('Playing watermark over speaker...');

      final completer = Completer<void>();

      await activePlayer.startPlayer(
        fromDataBuffer: wavBytes,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          _isPlaying = false;
          onStatus('Playback complete.');
          onDone();
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await completer.future;
    } catch (e) {
      _isPlaying = false;
      onStatus('Transmission error: $e');
      onDone();
      rethrow;
    }
  }

  /// Stops any currently running playback.
  static Future<void> stop([FlutterSoundPlayer? player]) async {
    final activePlayer = player ?? _player;
    if (activePlayer != null && activePlayer.isPlaying) {
      await activePlayer.stopPlayer();
    }
    _isPlaying = false;
  }

  /// Closes and releases player resources.
  static Future<void> dispose([FlutterSoundPlayer? player]) async {
    await stop(player);
    final activePlayer = player ?? _player;
    if (activePlayer != null && activePlayer.isOpen()) {
      await activePlayer.closePlayer();
    }
    if (player == null) {
      _player = null;
    }
  }
}
