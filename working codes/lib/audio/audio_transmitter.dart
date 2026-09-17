import 'dart:async';

import 'package:flutter_sound/flutter_sound.dart';

import '../dsp/protocol.dart';
import 'wav_utils.dart';

class AudioTransmitter {
  static FlutterSoundPlayer? _player;

  static bool get isPlaying => _player?.isPlaying ?? false;

  static Future<void> transmit(
    List<double> mixedSamples, {
    void Function(String status)? onStatus,
    FlutterSoundPlayer? player,
  }) async {
    final activePlayer = player ?? (_player ??= FlutterSoundPlayer());
    if (!activePlayer.isOpen()) {
      await activePlayer.openPlayer();
    }
    if (activePlayer.isPlaying) {
      await activePlayer.stopPlayer();
    }

    final wavBytes = WavUtils.writeWavBytes(
      mixedSamples,
      sampleRate: sampleRate,
    );
    final finished = Completer<void>();
    onStatus?.call('playing');

    await activePlayer.startPlayer(
      fromDataBuffer: wavBytes,
      codec: Codec.pcm16WAV,
      whenFinished: () {
        onStatus?.call('done');
        if (!finished.isCompleted) finished.complete();
      },
    );

    await finished.future;
  }

  static Future<void> stop([FlutterSoundPlayer? player]) async {
    final activePlayer = player ?? _player;
    if (activePlayer?.isPlaying ?? false) {
      await activePlayer!.stopPlayer();
    }
  }

  static Future<void> dispose([FlutterSoundPlayer? player]) async {
    await stop(player);
    final activePlayer = player ?? _player;
    if (activePlayer?.isOpen() ?? false) {
      await activePlayer!.closePlayer();
    }
    if (player == null) _player = null;
  }
}
