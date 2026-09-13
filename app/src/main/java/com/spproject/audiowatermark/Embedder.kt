package com.spproject.audiowatermark

import android.util.Log

/**
 * Superimposes (adds) the watermark signal on top of the host song's samples.
 *
 * The host song is treated as read-only; the result is a new array.
 * Both arrays use normalized [-1.0, 1.0] double-precision samples.
 *
 * Anti-clipping guarantee:
 *  The mix is: mixed[i] = host[i] + watermark[i]
 *  Because WATERMARK_AMPLITUDE ≤ 0.12 and host peaks are typically ≤ 0.92 FS,
 *  the worst-case sum is 1.04 — just above 1.0.  We clamp to [-1.0, 1.0] as a
 *  safety net but also log a warning if any sample was actually clamped, so
 *  you can increase the start offset or reduce WATERMARK_AMPLITUDE.
 */
object Embedder {

    private const val TAG = "Embedder"

    /**
     * Mixes [watermark] into [hostSamples] starting at [startSampleIndex].
     *
     * @param hostSamples       Normalized [-1.0, 1.0] PCM doubles from [WavUtils].
     * @param watermark         Output of [ToneGenerator.buildWatermarkSequence].
     * @param startSampleIndex  First sample of [hostSamples] to write into.
     *                          Use [Config.SAMPLE_RATE] to start 1 second in.
     * @return A new array the same length as [hostSamples] with the watermark mixed in.
     * @throws IllegalArgumentException if [watermark] would overrun [hostSamples].
     */
    fun embed(
        hostSamples: DoubleArray,
        watermark: DoubleArray,
        startSampleIndex: Int
    ): DoubleArray {
        require(startSampleIndex >= 0) { "startSampleIndex must be >= 0" }
        val endIdx = startSampleIndex + watermark.size
        require(endIdx <= hostSamples.size) {
            "Watermark overruns host audio: watermark ends at sample $endIdx " +
            "but host has only ${hostSamples.size} samples " +
            "(${"%.1f".format(hostSamples.size / Config.SAMPLE_RATE.toDouble())} s). " +
            "Use a longer host file or reduce the message length."
        }

        val mixed = hostSamples.copyOf()
        var clippedCount = 0
        var peakRaw = 0.0

        for (i in watermark.indices) {
            val idx = startSampleIndex + i
            val raw = mixed[idx] + watermark[i]
            if (kotlin.math.abs(raw) > peakRaw) peakRaw = kotlin.math.abs(raw)
            if (raw > 1.0 || raw < -1.0) clippedCount++
            mixed[idx] = raw.coerceIn(-1.0, 1.0)
        }

        // Convert back to 16-bit range to verify Short bounds (informational)
        val peakShort = (peakRaw * 32767.0).toInt()
        if (clippedCount > 0) {
            Log.w(TAG, "CLIPPING: $clippedCount/${watermark.size} samples exceeded ±1.0 " +
                       "(peak raw = ${"%.4f".format(peakRaw)}, peak 16-bit = $peakShort). " +
                       "Reduce WATERMARK_AMPLITUDE or start embedding later in the song.")
        } else {
            Log.d(TAG, "No clipping. Peak mix sample = ${"%.4f".format(peakRaw)} FS " +
                       "($peakShort / ${Short.MAX_VALUE})")
        }

        return mixed
    }
}
