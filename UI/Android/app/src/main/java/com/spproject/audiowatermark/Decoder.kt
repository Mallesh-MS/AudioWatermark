package com.spproject.audiowatermark

import android.util.Log

/**
 * Decodes a captured microphone buffer back into the original plaintext.
 *
 * Pipeline:
 *   1. Scan captured audio with a sliding window for the preamble tone (17 kHz).
 *   2. Once preamble is locked, read the 8-bit length header to know payload size.
 *   3. Decode each data bit by comparing Goertzel energy at 18 kHz vs 19.5 kHz.
 *   4. Reassemble bytes and AES-decrypt.
 *
 * All intermediate energy values are exposed via [DecodeResult] so callers can
 * log or display them for diagnostic/calibration purposes — never just pass/fail.
 */
object Decoder {

    private const val TAG = "Decoder"

    private val SYMBOL_LEN   = (Config.SAMPLE_RATE * Config.SYMBOL_DURATION_MS / 1000.0).toInt()
    private val PREAMBLE_LEN = (Config.SAMPLE_RATE * Config.PREAMBLE_DURATION_MS / 1000.0).toInt()

    /**
     * Preamble detection threshold — the Goertzel magnitude at [Config.PREAMBLE_FREQ]
     * must exceed this to be considered a valid preamble.
     *
     * The magnitude for a pure 17 kHz sine at WATERMARK_AMPLITUDE (0.08) over
     * PREAMBLE_LEN samples is approximately:
     *   0.08 × 32768 × PREAMBLE_LEN / 2  ≈  0.08 × 32768 × 13230 / 2  ≈  17 366 592
     * After speaker→air→mic attenuation (−20 to −30 dB ≈ factor 10–30×),
     * received magnitude is roughly 580 000–1 740 000.
     * A threshold of 300 is very conservative and will be well exceeded by any
     * real signal; tune it upward only if you see false positives in a noisy room.
     * Print DecodeResult.preamblePeakEnergy to calibrate on your actual devices.
     */
    private const val PREAMBLE_THRESHOLD = 300.0

    // ─────────────────────────────────────────────────────────────────────
    // Result type
    // ─────────────────────────────────────────────────────────────────────

    /** All possible outcomes of a decode attempt, with diagnostic detail. */
    sealed class DecodeResult {

        /** Decode succeeded. */
        data class Success(
            val message: String,
            val preamblePeakEnergy: Double,
            val preambleEndSample: Int
        ) : DecodeResult()

        /** Audio was captured but no energy spike was seen near 17 kHz. */
        data class NoSignal(
            val maxPreambleEnergy: Double,   // largest preamble-frequency energy seen in the whole buffer
            val threshold: Double
        ) : DecodeResult()

        /** Preamble energy spike was detected but locking the start position failed. */
        data class NoPreambleLock(
            val preamblePeakEnergy: Double,
            val threshold: Double
        ) : DecodeResult()

        /**
         * Preamble was found and bits were decoded, but AES decryption threw.
         * Usually means bit errors corrupted the ciphertext, or the passphrase
         * does not match the transmitter's.
         */
        data class DecryptFailed(
            val preambleEndSample: Int,
            val cipherLength: Int,
            val reason: String
        ) : DecodeResult()

        /**
         * Decryption succeeded but the result is not printable UTF-8 (or contains
         * only control characters), which almost always means the bits decoded
         * incorrectly even though AES didn't throw.
         */
        data class GarbageOutput(
            val preambleEndSample: Int,
            val rawDecrypted: String
        ) : DecodeResult()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Full decode pipeline.  Returns a [DecodeResult] with specific failure
     * information — never a bare null.
     *
     * @param captured  Normalized [-1.0, 1.0] doubles from [AudioReceiver].
     */
    fun decode(captured: DoubleArray): DecodeResult {
        // Step 1: find preamble
        val (preambleEnd, peakEnergy, maxEnergy) = findPreambleEnd(captured)

        if (preambleEnd == -1) {
            // Distinguish "no signal at all" from "some energy but couldn't lock"
            return if (maxEnergy < PREAMBLE_THRESHOLD) {
                Log.d(TAG, "No signal: max preamble energy = ${"%.1f".format(maxEnergy)}, threshold = $PREAMBLE_THRESHOLD")
                DecodeResult.NoSignal(maxEnergy, PREAMBLE_THRESHOLD)
            } else {
                Log.d(TAG, "Preamble energy detected (${"%.1f".format(peakEnergy)}) but lock failed")
                DecodeResult.NoPreambleLock(peakEnergy, PREAMBLE_THRESHOLD)
            }
        }
        Log.d(TAG, "Preamble locked at sample $preambleEnd (energy = ${"%.1f".format(peakEnergy)})")

        // Step 2: decode 8-bit length header
        val (lengthBits, lengthEnergies) = decodeBitsWithEnergy(captured, preambleEnd, 8)
        if (lengthBits.size < 8) {
            return DecodeResult.DecryptFailed(preambleEnd, 0, "Capture too short for length header")
        }
        val cipherLength = (ToneGenerator.bitsToBytes(lengthBits)[0].toInt() and 0xFF)
        Log.d(TAG, "Length header decoded: $cipherLength bytes")
        logEnergyTable("LengthHeader", lengthEnergies)

        if (cipherLength == 0 || cipherLength > 255) {
            return DecodeResult.DecryptFailed(preambleEnd, cipherLength,
                "Length header decoded to invalid value $cipherLength (expected 1–255). " +
                "Bit errors likely — check preamble lock position and room noise.")
        }

        // Step 3: decode payload bits
        val payloadStart = preambleEnd + 8 * SYMBOL_LEN
        val (payloadBits, payloadEnergies) = decodeBitsWithEnergy(captured, payloadStart, cipherLength * 8)
        Log.d(TAG, "Payload bits decoded: ${payloadBits.size} / ${cipherLength * 8} expected")
        logEnergyTable("Payload[0..7]", payloadEnergies.take(8))   // first byte as sample

        if (payloadBits.size < cipherLength * 8) {
            return DecodeResult.DecryptFailed(preambleEnd, cipherLength,
                "Capture too short: got ${payloadBits.size} payload bits, need ${cipherLength * 8}. " +
                "Increase listening window (currently ${captured.size / Config.SAMPLE_RATE} s).")
        }

        val cipherBytes = ToneGenerator.bitsToBytes(payloadBits)

        // Step 4: AES decrypt
        val plainText = try {
            AesCrypto.decrypt(cipherBytes)
        } catch (e: Exception) {
            Log.e(TAG, "AES decrypt threw: ${e.message}")
            return DecodeResult.DecryptFailed(preambleEnd, cipherLength, e.message ?: e.javaClass.simpleName)
        }

        // Step 5: sanity-check the output — guard against silent bit-error corruption
        if (!isReasonableUtf8(plainText)) {
            Log.w(TAG, "Decryption produced garbage: [${plainText.take(60)}...]")
            return DecodeResult.GarbageOutput(preambleEnd, plainText)
        }

        Log.d(TAG, "Decode success: \"$plainText\"")
        return DecodeResult.Success(plainText, peakEnergy, preambleEnd)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Returns Triple(preambleEndSample, peakEnergy, maxEnergy).
     * preambleEndSample = -1 if not found.
     * Scans with a half-symbol step for overlap to avoid missing an edge.
     */
    private fun findPreambleEnd(captured: DoubleArray): Triple<Int, Double, Double> {
        val step = SYMBOL_LEN / 2
        var maxSeen = 0.0
        var peakAt = -1
        var peakEnergy = 0.0

        var i = 0
        while (i + PREAMBLE_LEN <= captured.size) {
            val window = captured.copyOfRange(i, i + PREAMBLE_LEN)
            val mag = Goertzel.magnitude(window, Config.PREAMBLE_FREQ)
            if (mag > maxSeen) maxSeen = mag
            if (mag > PREAMBLE_THRESHOLD && mag > peakEnergy) {
                peakEnergy = mag
                peakAt = i
            }
            i += step
        }

        return if (peakAt == -1) {
            Triple(-1, peakEnergy, maxSeen)
        } else {
            Triple(peakAt + PREAMBLE_LEN, peakEnergy, maxSeen)
        }
    }

    /**
     * Decodes [numBits] consecutive bits starting at [startIdx].
     * Returns Pair(bits, energyLog) where energyLog contains (mag0, mag1) per bit.
     */
    private fun decodeBitsWithEnergy(
        captured: DoubleArray,
        startIdx: Int,
        numBits: Int
    ): Pair<List<Int>, List<Pair<Double, Double>>> {
        val bits = mutableListOf<Int>()
        val energies = mutableListOf<Pair<Double, Double>>()
        var idx = startIdx

        repeat(numBits) {
            if (idx + SYMBOL_LEN > captured.size) return@repeat
            val window = captured.copyOfRange(idx, idx + SYMBOL_LEN)
            val mag0 = Goertzel.magnitude(window, Config.FREQ_BIT_0)
            val mag1 = Goertzel.magnitude(window, Config.FREQ_BIT_1)
            bits.add(if (mag1 > mag0) 1 else 0)
            energies.add(Pair(mag0, mag1))
            idx += SYMBOL_LEN
        }
        return Pair(bits, energies)
    }

    private fun logEnergyTable(label: String, energies: List<Pair<Double, Double>>) {
        if (!Log.isLoggable(TAG, Log.DEBUG)) return
        val sb = StringBuilder("$TAG energy [$label]:\n  #  | mag@18k      | mag@19.5k    | bit\n")
        energies.forEachIndexed { i, (m0, m1) ->
            sb.append("  %-3d| %-12.1f | %-12.1f | %d\n".format(i, m0, m1, if (m1 > m0) 1 else 0))
        }
        Log.d(TAG, sb.toString())
    }

    /** Returns false if the string is blank, entirely control chars, or has replacement chars. */
    private fun isReasonableUtf8(s: String): Boolean {
        if (s.isBlank()) return false
        if (s.contains('\uFFFD')) return false   // UTF-8 replacement character → decode error
        val printable = s.count { it.code >= 0x20 || it == '\n' || it == '\r' || it == '\t' }
        return printable.toDouble() / s.length >= 0.75   // ≥75 % printable
    }
}
