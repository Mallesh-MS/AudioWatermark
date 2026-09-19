package com.spproject.audiowatermark

/**
 * Figures out how many samples/seconds a given ciphertext needs to transmit.
 * Supports dynamic [Config.RangeMode] calculation.
 */
object TransmissionSizing {
    fun totalSamplesNeeded(cipherByteLength: Int, mode: Config.RangeMode = Config.activeMode): Int {
        val symbolLen = Config.symbolSamples(mode)
        val preambleLen = Config.preambleSamples(mode)
        val headerBits = 8
        val payloadBits = cipherByteLength * 8
        return preambleLen + (headerBits + payloadBits) * symbolLen
    }

    fun totalSecondsNeeded(cipherByteLength: Int, mode: Config.RangeMode = Config.activeMode): Double =
        totalSamplesNeeded(cipherByteLength, mode) / Config.SAMPLE_RATE.toDouble()
}
