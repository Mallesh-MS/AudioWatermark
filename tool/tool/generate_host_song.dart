import 'dart:io';
import 'dart:math';
import '../lib/audio/wav_utils.dart';
import '../lib/dsp/protocol.dart';

void main() {
  const durationSeconds = 20.0;
  final totalSamples = (sampleRate * durationSeconds).round();
  final samples = List<double>.filled(totalSamples, 0.0);

  // Musical progression: C (261.63Hz), G (392.00Hz), Am (440.00Hz), F (349.23Hz)
  final chords = [
    [261.63, 329.63, 392.00, 523.25], // C major
    [196.00, 246.94, 293.66, 392.00], // G major
    [220.00, 261.63, 329.63, 440.00], // A minor
    [174.61, 220.00, 261.63, 349.23], // F major
  ];

  final chordDuration = 5.0; // 5 seconds per chord

  for (int i = 0; i < totalSamples; i++) {
    final t = i / sampleRate;
    final chordIdx = (t ~/ chordDuration) % chords.length;
    final currentChord = chords[chordIdx];

    double sample = 0.0;
    for (int noteIdx = 0; noteIdx < currentChord.length; noteIdx++) {
      final f0 = currentChord[noteIdx];
      // Fundamental + overtones
      final a0 = 0.15 * sin(2 * pi * f0 * t);
      final a1 = 0.08 * sin(2 * pi * (2 * f0) * t);
      final a2 = 0.04 * sin(2 * pi * (3 * f0) * t);
      final a3 = 0.02 * sin(2 * pi * (4 * f0) * t);
      sample += (a0 + a1 + a2 + a3);
    }

    // Soft envelope / tremolo
    final envelope = 0.7 + 0.3 * sin(2 * pi * 0.5 * t);
    samples[i] = (sample * envelope).clamp(-0.8, 0.8);
  }

  final dir = Directory('assets/host_songs');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  WavUtils.writeWav('assets/host_songs/acoustic_breeze.wav', samples, sampleRate);
  WavUtils.writeWav('assets/host_song.wav', samples, sampleRate);
  print('Generated host WAV files: assets/host_songs/acoustic_breeze.wav and assets/host_song.wav (${durationSeconds}s)');
}
