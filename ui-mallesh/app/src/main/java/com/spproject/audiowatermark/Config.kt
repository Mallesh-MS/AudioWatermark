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
 * We choose N = SYMBOL_SAMPLES = Fs × SYMBOL_DURATION_MS / 1000:
 *   Fs               = 44 100 Hz
 *   SYMBOL_DURATION  = 100 ms  → N = 4 410 samples
 *   Δf_bin           = 44 100 / 4 410 = 10.0 Hz  (exact integer)
 *
 * Our three tones and their bin indices (k = round(N × f / Fs)):
 *   PREAMBLE  17 000 Hz → k = round(4410 × 17000 / 44100) = round(1700.0) = 1700
 *   BIT_0     18 000 Hz → k = round(4410 × 18000 / 44100) = round(1800.0) = 1800
 *   BIT_1     19 500 Hz → k = round(4410 × 19500 / 44100) = round(1950.0) = 1950
 *
 * Separations in bins (= in Hz because Δf_bin = 10 Hz):
 *   BIT_1 − BIT_0     = 150 bins = 1 500 Hz   (150 × Δf_bin)  ✓ >> 2 bins
 *   BIT_0 − PREAMBLE  = 100 bins = 1 000 Hz   (100 × Δf_bin)  ✓ >> 2 bins
 *
 * All three land EXACTLY on bin centres (zero fractional-bin error), so the
 * Goertzel filter sees maximum energy with zero inter-bin leakage.
 * ──────────────────────────────────────────────────────────────────────────
 */
object Config {

    /** Audio pipeline sample rate — must match the host WAV and AudioRecord/AudioTrack setup. */
    const val SAMPLE_RATE = 44100           // Hz

    // ── Preamble tone ──────────────────────────────────────────────────────
    /** 17 000 Hz — distinct from both bit frequencies; receiver locks onto this. */
    const val PREAMBLE_FREQ = 17000.0       // Hz
    /**
     * 300 ms preamble = 3× a normal symbol.  That gives the receiver a
     * 150 ms half-symbol sliding step to lock onto preamble start even if
     * the capture begins mid-tone.
     */
    const val PREAMBLE_DURATION_MS = 300    // ms

    // ── Data tones ─────────────────────────────────────────────────────────
    const val FREQ_BIT_0 = 18000.0          // Hz  (see bin math above)
    const val FREQ_BIT_1 = 19500.0          // Hz
    /**
     * 100 ms per bit → 10 bits/s raw throughput.
     * A 10-char ASCII message ≈ 10 bytes cipher → 80 data bits + 8 header bits
     * = 88 bits × 100 ms = 8.8 s payload + 0.3 s preamble ≈ 9.1 s total.
     */
    const val SYMBOL_DURATION_MS = 100      // ms

    // ── Embedding level ────────────────────────────────────────────────────
    /**
     * WATERMARK_AMPLITUDE = 0.08 = 8 % of full scale (≈ −21.9 dBFS).
     *
     * Why 0.08?
     *  • Host WAV peaks are typically ≈ 0.90 FS.  Worst-case mix:
     *      0.90 + 0.08 = 0.98 FS — safely below 1.0 (no clipping).
     *  • 8 % is inaudible under music (masking) but at −22 dBFS the signal
     *    survives the speaker→air→mic path (typ. −20 to −30 dB attenuation)
     *    with enough headroom above the phone mic noise floor (~−45 dBFS).
     *  • Tune upward (e.g. 0.12) if detection is unreliable in a noisy room;
     *    downward if you hear a whistle through the music.
     */
    const val WATERMARK_AMPLITUDE = 0.08   // fraction of full scale

    // ── Shared secret ──────────────────────────────────────────────────────
    /**
     * Pre-shared passphrase from which both sides derive the AES key via SHA-256.
     * KNOWN LIMITATION: hardcoded; a real system would use proper key exchange.
     */
    const val SHARED_PASSPHRASE = "signal-processing-project-2026"
}
