import 'protocol.dart';

/// Runtime-tunable DSP and acoustic protocol configuration.
///
/// Exposes key physical and detection parameters so that they can be adjusted
/// live during two-device calibration tests without recompiling.
///
/// Default values are initialized from the designed protocol constants in
/// [protocol.dart].
class TuningConfig {
  /// Watermark signal amplitude relative to full scale (0.0 to 1.0).
  /// Designed default: [watermarkAmplitude] (0.02).
  static double amplitude = watermarkAmplitude;

  /// Absolute Goertzel magnitude threshold required to detect a preamble burst.
  /// Designed default: 1.0.
  static double preambleThreshold = defaultPreambleThreshold;

  /// Duration in milliseconds of each FSK tone symbol (and bit period).
  /// Designed default: [symbolDurationMs] (100.0 ms).
  static double symbolDurationMs = defaultSymbolDurationMs;

  /// Resets all tuning parameters back to their designed protocol defaults.
  static void resetToDefaults() {
    amplitude = watermarkAmplitude;
    preambleThreshold = defaultPreambleThreshold;
    symbolDurationMs = defaultSymbolDurationMs;
  }
}
