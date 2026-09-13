package com.spproject.audiowatermark

import kotlin.math.PI
import kotlin.math.sin

/**
 * Converts encrypted bytes into an audio watermark:
 *   preamble tone → 8-bit length header → ciphertext bits (one tone per bit)
 *
 * Wire format (transmitted left-to-right in time):
 *   ┌────────────────┬────────────────────────┬────────────────────────────┐
 *   │  Preamble      │  Length (8 bits)        │  Payload (N×8 bits)        │
 *   │  300 ms        │  8 × 100 ms = 800 ms   │  cipherLen × 8 × 100 ms   │
 *   │  17 000 Hz     │  18k/19.5k Hz per bit  │  18k/19.5k Hz per bit     │
 *   └────────────────┴────────────────────────┴────────────────────────────┘
 *
 * The receiver reads the 8-bit length header to know how many payload bits to
 * collect — no out-of-band parameter is needed on the receiving side.
 */
object ToneGenerator {

    /**
     * Generates a pure sine tone at [freq] Hz for [durationMs] ms.
     * Amplitude is [amplitude] as a fraction of full scale.
     */
    fun generateTone(
        freq: Double,
        durationMs: Int,
        sampleRate: Int = Config.SAMPLE_RATE,
        amplitude: Double = Config.WATERMARK_AMPLITUDE
    ): DoubleArray {
        val numSamples = (sampleRate * durationMs / 1000.0).toInt()
        return DoubleArray(numSamples) { i ->
            amplitude * sin(2.0 * PI * freq * i / sampleRate)
        }
    }

    // ── Bit/byte conversion helpers (public so Decoder can reuse them) ──

    /** Converts bytes to a list of bits, MSB-first, Big Endian. */
    fun bytesToBits(bytes: ByteArray): List<Int> =
        bytes.flatMap { byte -> (7 downTo 0).map { bit -> (byte.toInt() shr bit) and 1 } }

    /**
     * Converts a list of bits (MSB-first) back to bytes.
     * [bits].size must be a multiple of 8; any trailing incomplete byte is ignored.
     */
    fun bitsToBytes(bits: List<Int>): ByteArray {
        val numBytes = bits.size / 8
        return ByteArray(numBytes) { byteIdx ->
            var b = 0
            for (bitPos in 0 until 8) b = (b shl 1) or bits[byteIdx * 8 + bitPos]
            b.toByte()
        }
    }

    // ── Internal helpers ─────────────────────────────────────────────────

    private fun bitsToToneArray(bits: List<Int>): DoubleArray {
        if (bits.isEmpty()) return DoubleArray(0)
        // Allocate the whole output once to avoid repeated array concatenation
        val symbolLen = (Config.SAMPLE_RATE * Config.SYMBOL_DURATION_MS / 1000.0).toInt()
        val result = DoubleArray(bits.size * symbolLen)
        for ((i, bit) in bits.withIndex()) {
            val freq = if (bit == 0) Config.FREQ_BIT_0 else Config.FREQ_BIT_1
            val tone = generateTone(freq, Config.SYMBOL_DURATION_MS)
            tone.copyInto(result, destinationOffset = i * symbolLen)
        }
        return result
    }

    /**
     * Builds the complete self-describing watermark audio sequence:
     *   preamble + 8-bit length header + payload bits
     *
     * [cipherBytes] must be 1–255 bytes (enforced by the 1-byte length header).
     * Returns a [DoubleArray] of normalized [-1.0, 1.0] samples ready to
     * be mixed into the host audio by [Embedder].
     */
    fun buildWatermarkSequence(cipherBytes: ByteArray): DoubleArray {
        require(cipherBytes.isNotEmpty()) { "Ciphertext must not be empty" }
        require(cipherBytes.size <= 255) {
            "Ciphertext is ${cipherBytes.size} bytes; max is 255 (1-byte length header limit). " +
            "Shorten your message."
        }

        val preamble = generateTone(Config.PREAMBLE_FREQ, Config.PREAMBLE_DURATION_MS)

        // 8-bit length header: the number of ciphertext bytes encoded as 8 data tones
        val lengthBits = bytesToBits(byteArrayOf(cipherBytes.size.toByte()))
        val lengthTones = bitsToToneArray(lengthBits)

        // Payload: each ciphertext byte → 8 tones (MSB-first)
        val payloadBits = bytesToBits(cipherBytes)
        val payloadTones = bitsToToneArray(payloadBits)

        // Concatenate: preamble | header | payload
        val totalLen = preamble.size + lengthTones.size + payloadTones.size
        val out = DoubleArray(totalLen)
        preamble.copyInto(out, 0)
        lengthTones.copyInto(out, preamble.size)
        payloadTones.copyInto(out, preamble.size + lengthTones.size)
        return out
    }
}
