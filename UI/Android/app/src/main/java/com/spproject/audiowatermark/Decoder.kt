package com.spproject.audiowatermark

import android.util.Log

/**
 * Decodes a captured microphone buffer back into the original plaintext.
 *
 * Pipeline:
 *   1. Scan captured audio with a sliding window for the preamble tone (17 kHz).
 *   2. Once preamble is locked, read the 8-bit length header to know payload size.
 *   3. Decode each data bit by comparing Goertzel energy at 18 kHz vs 19.5 kHz.
 *   4. Reassemble bytes and AES-decrypt using the specified secret key / passphrase.
 *
 * All intermediate energy values are exposed via [DecodeResult] so callers can
 * log or display them for diagnostic/calibration purposes.
 */
object Decoder {

    private const val TAG = "Decoder"

    // ─────────────────────────────────────────────────────────────────────
    // Result type
    // ─────────────────────────────────────────────────────────────────────

    /** All possible outcomes of a decode attempt, with diagnostic detail. */
    sealed class DecodeResult {

        /** Decode succeeded. */
        data class Success(
            val message: String,
            val preamblePeakEnergy: Double,
            val preambleEndSample: Int,
            val mode: Config.RangeMode
        ) : DecodeResult()

        /** Audio was captured but no energy spike was seen near 17 kHz. */
        data class NoSignal(
            val maxPreambleEnergy: Double,
            val threshold: Double,
            val mode: Config.RangeMode
        ) : DecodeResult()

        /** Preamble energy spike was detected but locking the start position failed. */
        data class NoPreambleLock(
            val preamblePeakEnergy: Double,
            val threshold: Double,
            val mode: Config.RangeMode
        ) : DecodeResult()

        /**
         * Preamble was found and bits were decoded, but AES decryption failed.
         * Usually means wrong secret key / passphrase, or bit errors corrupted the ciphertext.
         */
        data class DecryptFailed(
            val preambleEndSample: Int,
            val cipherLength: Int,
            val reason: String,
            val mode: Config.RangeMode
        ) : DecodeResult()

        /**
         * Decryption succeeded but the result is not printable UTF-8,
         * which means wrong secret key (AES-CTR with wrong key produces random bytes)
         * or flipped payload bits.
         */
        data class GarbageOutput(
            val preambleEndSample: Int,
            val rawDecrypted: String,
            val mode: Config.RangeMode
        ) : DecodeResult()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Full decode pipeline.
     *
     * @param captured Normalized [-1.0, 1.0] doubles from [AudioReceiver] or WAV file.
     * @param mode Selected transmission mode (symbol and preamble timing).
     * @param passphrase Secret key used to derive the AES-128 key.
     */
    fun decode(
        captured: DoubleArray,
        mode: Config.RangeMode = Config.activeMode,
        passphrase: String = Config.SHARED_PASSPHRASE
    ): DecodeResult {
        val symbolLen = Config.symbolSamples(mode)
        val preambleLen = Config.preambleSamples(mode)
        val threshold = mode.detectionThreshold

        Log.d(TAG, "Starting decode: mode=${mode.displayName}, passphraseLen=${passphrase.length}")

        // Step 1: find preamble
        val (preambleEnd, peakEnergy, maxEnergy) = findPreambleEnd(captured, mode)

        if (preambleEnd == -1) {
            return if (maxEnergy < threshold) {
                Log.d(TAG, "No signal: max preamble energy = ${"%.1f".format(maxEnergy)}, threshold = $threshold")
                DecodeResult.NoSignal(maxEnergy, threshold, mode)
            } else {
                Log.d(TAG, "Preamble energy detected (${"%.1f".format(peakEnergy)}) but lock failed")
                DecodeResult.NoPreambleLock(peakEnergy, threshold, mode)
            }
        }
        Log.d(TAG, "Preamble locked at sample $preambleEnd (energy = ${"%.1f".format(peakEnergy)})")

        // Step 2: decode 8-bit length header
        val (lengthBits, lengthEnergies) = decodeBitsWithEnergy(captured, preambleEnd, 8, mode)
        if (lengthBits.size < 8) {
            return DecodeResult.DecryptFailed(preambleEnd, 0, "Capture too short for length header", mode)
        }
        val cipherLength = (ToneGenerator.bitsToBytes(lengthBits)[0].toInt() and 0xFF)
        Log.d(TAG, "Length header decoded: $cipherLength bytes")
        logEnergyTable("LengthHeader", lengthEnergies)

        if (cipherLength == 0 || cipherLength > 255) {
            return DecodeResult.DecryptFailed(
                preambleEnd, cipherLength,
                "Length header decoded to invalid value $cipherLength (expected 1–255). " +
                "Bit errors likely — verify both devices have matching profiles.",
                mode
            )
        }

        // Step 3: decode payload bits
        val payloadStart = preambleEnd + 8 * symbolLen
        val (payloadBits, payloadEnergies) = decodeBitsWithEnergy(captured, payloadStart, cipherLength * 8, mode)
        Log.d(TAG, "Payload bits decoded: ${payloadBits.size} / ${cipherLength * 8} expected")
        logEnergyTable("Payload[0..7]", payloadEnergies.take(8))

        if (payloadBits.size < cipherLength * 8) {
            return DecodeResult.DecryptFailed(
                preambleEnd, cipherLength,
                "Capture buffer ended early: got ${payloadBits.size} payload bits, need ${cipherLength * 8}.",
                mode
            )
        }

        val cipherBytes = ToneGenerator.bitsToBytes(payloadBits)

        // Step 4: AES decrypt with the provided custom secret key
        val key = try {
            AesCrypto.deriveKey(passphrase)
        } catch (e: Exception) {
            return DecodeResult.DecryptFailed(preambleEnd, cipherLength, "Invalid secret key: ${e.message}", mode)
        }

        val plainText = try {
            AesCrypto.decrypt(cipherBytes, key)
        } catch (e: Exception) {
            Log.e(TAG, "AES decrypt threw: ${e.message}")
            return DecodeResult.DecryptFailed(preambleEnd, cipherLength, "Decryption error: ${e.message}", mode)
        }

        // Step 5: sanity-check output
        if (!isReasonableUtf8(plainText)) {
            Log.w(TAG, "Decryption produced garbage: [${plainText.take(60)}...]")
            return DecodeResult.GarbageOutput(preambleEnd, plainText, mode)
        }

        Log.d(TAG, "Decode success: \"$plainText\"")
        return DecodeResult.Success(plainText, peakEnergy, preambleEnd, mode)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────

    private fun findPreambleEnd(
        captured: DoubleArray,
        mode: Config.RangeMode
    ): Triple<Int, Double, Double> {
        val symbolLen = Config.symbolSamples(mode)
        val preambleLen = Config.preambleSamples(mode)
        val threshold = mode.detectionThreshold

        val coarseStep = symbolLen / 2
        var maxSeen = 0.0
        var coarsePeakAt = -1
        var coarsePeakEnergy = 0.0

        var i = 0
        while (i + preambleLen <= captured.size) {
            val window = captured.copyOfRange(i, i + preambleLen)
            val mag = Goertzel.magnitude(window, Config.PREAMBLE_FREQ)
            if (mag > maxSeen) maxSeen = mag
            if (mag > threshold && mag > coarsePeakEnergy) {
                coarsePeakEnergy = mag
                coarsePeakAt = i
            }
            i += coarseStep
        }

        if (coarsePeakAt == -1) {
            return Triple(-1, coarsePeakEnergy, maxSeen)
        }

        // Fine-alignment pass: scan ±coarseStep with 5 ms resolution to lock exact edge
        val fineStep = maxOf(1, (Config.SAMPLE_RATE * 0.005).toInt()) // 5 ms = 220 samples
        val fineStart = maxOf(0, coarsePeakAt - coarseStep)
        val fineEnd = minOf(captured.size - preambleLen, coarsePeakAt + coarseStep)

        var finePeakAt = coarsePeakAt
        var finePeakEnergy = coarsePeakEnergy

        var fi = fineStart
        while (fi <= fineEnd) {
            val window = captured.copyOfRange(fi, fi + preambleLen)
            val mag = Goertzel.magnitude(window, Config.PREAMBLE_FREQ)
            if (mag > finePeakEnergy) {
                finePeakEnergy = mag
                finePeakAt = fi
            }
            fi += fineStep
        }

        return Triple(finePeakAt + preambleLen, finePeakEnergy, maxSeen)
    }

    private fun decodeBitsWithEnergy(
        captured: DoubleArray,
        startIdx: Int,
        numBits: Int,
        mode: Config.RangeMode
    ): Pair<List<Int>, List<Pair<Double, Double>>> {
        val symbolLen = Config.symbolSamples(mode)
        val bits = mutableListOf<Int>()
        val energies = mutableListOf<Pair<Double, Double>>()
        var idx = startIdx

        repeat(numBits) {
            if (idx + symbolLen > captured.size) return@repeat
            val window = captured.copyOfRange(idx, idx + symbolLen)
            val mag0 = Goertzel.magnitude(window, Config.FREQ_BIT_0)
            val mag1 = Goertzel.magnitude(window, Config.FREQ_BIT_1)
            bits.add(if (mag1 > mag0) 1 else 0)
            energies.add(Pair(mag0, mag1))
            idx += symbolLen
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

    private fun isReasonableUtf8(s: String): Boolean {
        if (s.isBlank()) return false
        if (s.contains('\uFFFD')) return false
        val printable = s.count { it.code >= 0x20 || it == '\n' || it == '\r' || it == '\t' }
        return printable.toDouble() / s.length >= 0.75
    }
}
