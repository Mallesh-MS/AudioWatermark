package com.spproject.audiowatermark

/**
 * Shared constants used by BOTH the transmitter and receiver.
 * Both devices must use identical values or decoding will fail.
 *
 * ─── FREQUENCY-SPACING MATH ───────────────────────────────────────────────
 *
 * Goertzel's frequency resolution over a block of N samples at sample rate Fs is:
 *
 *   Δf_bin = Fs / N     (Hz per DFT bin)
 *
 * For two tones to be cleanly separable we need them to fall on distinct bins
 * AND have enough separation to avoid spectral leakage bleed-over.
 * A conservative rule is: |f1 − f2| ≥ 2 × Δf_bin.
 *
 * Standard Mode (100 ms):
 *   Fs               = 44 100 Hz
 *   SYMBOL_DURATION  = 100 ms  → N = 4 410 samples
 *   Δf_bin           = 44 100 / 4 410 = 10.0 Hz  (exact integer)
 *
 * Long-Range Mode (250 ms):
 *   SYMBOL_DURATION  = 250 ms  → N = 11 025 samples
 *   Δf_bin           = 44 100 / 11 025 = 4.0 Hz   (exact integer)
 *   Higher coherent processing gain (+9.5 dB SNR) & narrower noise integration window!
 *
 * Tones:
 *   PREAMBLE  17 000 Hz
 *   BIT_0     18 000 Hz
 *   BIT_1     19 500 Hz
 * ──────────────────────────────────────────────────────────────────────────
 */
object Config {

    /** Audio pipeline sample rate — must match the host WAV and AudioRecord/AudioTrack setup. */
    const val SAMPLE_RATE = 44100           // Hz

    // ── Carrier frequencies ───────────────────────────────────────────────
    const val PREAMBLE_FREQ = 17000.0       // Hz
    const val FREQ_BIT_0    = 18000.0       // Hz
    const val FREQ_BIT_1    = 19500.0       // Hz

    /**
     * Transmission Profile / Range Mode.
     * Both phones must be in the same mode to communicate!
     */
    enum class RangeMode(
        val symbolDurationMs: Int,
        val preambleDurationMs: Int,
        val defaultAmplitude: Double,
        val detectionThreshold: Double,
        val displayName: String,
        val description: String
    ) {
        /** Fast transmission (10 bps), optimal for close range (0–1.5 meters). */
        STANDARD(
            symbolDurationMs = 100,
            preambleDurationMs = 300,
            defaultAmplitude = 0.15,
            detectionThreshold = 2.0,
            displayName = "Standard (0–1.5m)",
            description = "10 bps • Fast transfer"
        ),

        /** High-penetration mode (4 bps), optimal for across-the-room (2–5+ meters). */
        LONG_RANGE(
            symbolDurationMs = 250,
            preambleDurationMs = 600,
            defaultAmplitude = 0.22,
            detectionThreshold = 2.5,
            displayName = "Long Range (2–5m+)",
            description = "4 bps • +9.5dB SNR Gain"
        )
    }

    /** Active transmission mode across transmitter and receiver. */
    var activeMode: RangeMode = RangeMode.STANDARD

    /** Backward-compatible accessors forwarding to activeMode */
    val SYMBOL_DURATION_MS: Int get() = activeMode.symbolDurationMs
    val PREAMBLE_DURATION_MS: Int get() = activeMode.preambleDurationMs
    val WATERMARK_AMPLITUDE: Double get() = activeMode.defaultAmplitude

    fun symbolSamples(mode: RangeMode = activeMode): Int =
        (SAMPLE_RATE * mode.symbolDurationMs / 1000.0).toInt()

    fun preambleSamples(mode: RangeMode = activeMode): Int =
        (SAMPLE_RATE * mode.preambleDurationMs / 1000.0).toInt()

    // ── Shared secret ──────────────────────────────────────────────────────
    const val SHARED_PASSPHRASE = "signal-processing-project-2026"
}
