package com.spproject.audiowatermark

/**
 * Figures out how many samples/seconds a given ciphertext needs to transmit.
 * Use this to make sure your host song is long enough (from the embed start
 * point onward) - a host that's too short silently truncates the watermark.
 */
object TransmissionSizing {
    fun totalSamplesNeeded(cipherByteLength: Int): Int {
        val symbolLen = (Config.SAMPLE_RATE * Config.SYMBOL_DURATION_MS / 1000.0).toInt()
        val preambleLen = (Config.SAMPLE_RATE * Config.PREAMBLE_DURATION_MS / 1000.0).toInt()
        val headerBits = 8
        val payloadBits = cipherByteLength * 8
        return preambleLen + (headerBits + payloadBits) * symbolLen
    }

    fun totalSecondsNeeded(cipherByteLength: Int): Double =
        totalSamplesNeeded(cipherByteLength) / Config.SAMPLE_RATE.toDouble()
}
