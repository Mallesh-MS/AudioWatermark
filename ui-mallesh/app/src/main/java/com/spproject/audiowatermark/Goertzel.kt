package com.spproject.audiowatermark

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Goertzel algorithm — single-frequency energy detector.
 *
 * Cheaper than a full FFT when only a handful of specific frequencies need to
 * be checked, which is exactly our case (preamble + 2 data tones).
 *
 * Algorithm summary:
 *   Given N input samples and target frequency f:
 *     ω  = 2π × f / Fs          (angular frequency, radians/sample)
 *     c  = 2 cos(ω)             (recursive coefficient)
 *     For each sample x[n]:  s[n] = x[n] + c × s[n-1] − s[n-2]
 *     Real part  = s[N-1] − s[N-2] × cos(ω)
 *     Imag part  = s[N-2] × sin(ω)
 *     Magnitude  = sqrt(Real² + Imag²)
 *
 * IMPORTANT: we use the EXACT target frequency (not a bin-rounded frequency)
 * for ω.  The rounded-k approach introduces a small angle error that grows
 * with the distance from the nearest bin centre; using the exact frequency
 * is both simpler and more accurate.
 */
object Goertzel {

    /**
     * Returns the DFT magnitude at [targetFreq] Hz over the given [samples].
     *
     * [samples] should contain exactly one symbol-length window (e.g. 4 410
     * samples for a 100 ms symbol at 44 100 Hz).
     *
     * The magnitude is unnormalized (scales with N and signal amplitude); use
     * it comparatively (which of two frequencies is larger?) or against a
     * calibrated threshold for preamble detection.
     */
    fun magnitude(
        samples: DoubleArray,
        targetFreq: Double,
        sampleRate: Int = Config.SAMPLE_RATE
    ): Double {
        val omega = 2.0 * PI * targetFreq / sampleRate  // exact, not bin-rounded
        val cosine = cos(omega)
        val coeff = 2.0 * cosine

        var s1 = 0.0   // s[n-1]
        var s2 = 0.0   // s[n-2]

        for (x in samples) {
            val s0 = x + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        val real = s1 - s2 * cosine
        val imag = s2 * sin(omega)
        return sqrt(real * real + imag * imag)
    }
}
