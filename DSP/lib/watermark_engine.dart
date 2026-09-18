import 'dart:math';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'audio/audio_receiver.dart';
import 'audio/audio_transmitter.dart';
import 'audio/wav_utils.dart';
import 'dsp/aes_crypto.dart';
import 'dsp/protocol.dart';
import 'dsp/tuning_config.dart';
import 'qr/qr_key_exchange.dart';

/// Clean public interface facade for the acoustic audio watermarking pipeline.
///
/// Encapsulates all crypto, DSP tone generation, Goertzel detection,
/// hardware playback/recording, and QR key exchange behind a simple, high-level
/// API for UI consumption.
class WatermarkEngine {
  /// Full send flow: encrypts [message] with [key], embeds into [hostSongPath]
  /// (or bundled default asset if null), and plays it through device speakers.
  ///
  /// Wraps [AudioTransmitter]. Catches internal errors cleanly and surfaces
  /// human-readable updates via [onStatus] and completion via [onDone].
  static Future<void> sendMessage({
    required String message,
    required Key key,
    String? hostSongPath,
    required void Function(String status) onStatus,
    required void Function() onDone,
  }) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      onStatus('Error: Cannot transmit empty message.');
      onDone();
      return;
    }

    try {
      onStatus('Loading host audio carrier...');
      final host = await _loadOrSynthesizeHost(
        hostSongPath: hostSongPath,
        messageLength: trimmedMessage.length,
      );

      await AudioTransmitter.transmit(
        message: trimmedMessage,
        key: key,
        hostSamples: host,
        onStatus: onStatus,
        onDone: onDone,
      );
    } catch (e) {
      onStatus('Transmission error: $e');
      onDone();
    }
  }

  /// Full receive flow: streams microphone audio, detects preamble, extracts
  /// redundant length header, decodes FSK tone payload, verifies CRC-8 checksum,
  /// and decrypts with [key].
  ///
  /// Wraps [AudioReceiver]. Calls [onResult] with the recovered string on success,
  /// or `null` if stopped or timed out without finding a message.
  static Future<void> startListening({
    required Key key,
    required void Function(String? message) onResult,
    void Function(String status)? onStatus,
    Duration? timeout = const Duration(seconds: 35),
  }) async {
    try {
      await AudioReceiver.startListening(
        key: key,
        onResult: onResult,
        onStatus: onStatus,
        timeout: timeout,
      );
    } catch (e) {
      onStatus?.call('Listening error: $e');
      onResult(null);
    }
  }

  /// Manually stops microphone listening.
  static Future<void> stopListening() async {
    try {
      await AudioReceiver.stopListening();
    } catch (_) {}
  }

  /// Generates a cryptographically secure 128-bit session key and its
  /// ready-to-render QR code [Widget].
  ///
  /// Wraps [WatermarkCrypto.generateKey] and [QrKeyExchange.keyToQrPayload].
  static ({Key key, Widget qrWidget}) generateAndShowKey({
    double size = 180.0,
  }) {
    final key = WatermarkCrypto.generateKey();
    final qrPayload = QrKeyExchange.keyToQrPayload(key);

    final qrWidget = QrImageView(
      data: qrPayload,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );

    return (key: key, qrWidget: qrWidget);
  }

  /// Generates the QR code [Widget] for an existing [key].
  static Widget buildQrWidget(Key key, {double size = 180.0}) {
    final qrPayload = QrKeyExchange.keyToQrPayload(key);
    return QrImageView(
      data: qrPayload,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
  }

  /// Parses a scanned QR payload string back into a validated [Key].
  ///
  /// Throws [FormatException] on malformed input (non-hex, wrong length).
  static Key scanQrResult(String scannedText) {
    return QrKeyExchange.qrPayloadToKey(scannedText);
  }

  /// Safely parses a scanned QR string, returning `null` instead of throwing
  /// on malformed input.
  static Key? tryScanQrResult(String scannedText) {
    try {
      return QrKeyExchange.qrPayloadToKey(scannedText);
    } catch (_) {
      return null;
    }
  }

  /// Internal helper to load host audio from file, asset bundle, or synthesize
  /// a clean carrier if assets are unavailable.
  static Future<List<double>> _loadOrSynthesizeHost({
    String? hostSongPath,
    required int messageLength,
  }) async {
    final totalSymbols = 24 + 8 * messageLength;
    final requiredSec =
        0.3 + (totalSymbols * (TuningConfig.symbolDurationMs / 1000.0)) + 2.0;
    final requiredSampleCount = (sampleRate * requiredSec).round();

    // 1. Try specified file path if provided
    if (hostSongPath != null && hostSongPath.isNotEmpty) {
      try {
        final wavData = WavUtils.readWav(hostSongPath);
        if (wavData.samples.length >= requiredSampleCount) {
          return wavData.samples;
        }
        return _extendHostSamples(wavData.samples, requiredSampleCount);
      } catch (_) {
        // Fall back to asset or synthesis
      }
    }

    // 2. Try bundled asset
    try {
      final byteData = await rootBundle.load('assets/host_song.wav');
      final bytes = byteData.buffer.asUint8List();
      final wavData = WavUtils.readWavBytes(bytes);
      if (wavData.samples.length >= requiredSampleCount) {
        return wavData.samples;
      }
      return _extendHostSamples(wavData.samples, requiredSampleCount);
    } catch (_) {
      // Fall back to synthesis
    }

    // 3. Fallback: synthesize harmonic host
    return _generateSyntheticHost(requiredSec);
  }

  static List<double> _extendHostSamples(
    List<double> source,
    int targetLength,
  ) {
    final extended = List<double>.filled(targetLength, 0.0);
    for (int i = 0; i < targetLength; i++) {
      extended[i] = source[i % source.length];
    }
    return extended;
  }

  static List<double> _generateSyntheticHost(double durationSeconds) {
    final count = (sampleRate * durationSeconds).round();
    final samples = List<double>.filled(count, 0.0);
    final freqs = [261.63, 329.63, 392.00, 523.25]; // C major chord notes

    for (int i = 0; i < count; i++) {
      final t = i / sampleRate;
      double sum = 0.0;
      for (final f in freqs) {
        sum += 0.08 * sin(2 * pi * f * t);
      }
      samples[i] = sum;
    }
    return samples;
  }
}
