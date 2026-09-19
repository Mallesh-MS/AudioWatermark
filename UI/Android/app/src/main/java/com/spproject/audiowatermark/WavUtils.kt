package com.spproject.audiowatermark

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * WAV file I/O — reads and writes 44100 Hz / mono / 16-bit PCM.
 *
 * Required host-song format:
 *   44100 Hz, 16-bit PCM WAV (mono or stereo).
 */
object WavUtils {

    // ── Load ─────────────────────────────────────────────────────────────

    /**
     * Loads a WAV resource from res/raw into a normalized [-1.0, 1.0] DoubleArray.
     */
    fun loadWavAsDoubles(context: Context, resId: Int): DoubleArray {
        val bytes = context.resources.openRawResource(resId).use { it.readBytes() }
        return parseWavBytes(bytes)
    }

    /**
     * Loads a WAV from any [InputStream] into a normalized [-1.0, 1.0] DoubleArray.
     */
    fun loadWavFromStreamAsDoubles(inputStream: InputStream): DoubleArray {
        val bytes = inputStream.use { it.readBytes() }
        return parseWavBytes(bytes)
    }

    /**
     * Parses RIFF/WAVE PCM bytes into normalized [-1.0, 1.0] doubles.
     */
    private fun parseWavBytes(bytes: ByteArray): DoubleArray {
        require(bytes.size >= 12 &&
                String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" &&
                String(bytes, 8, 4, Charsets.US_ASCII) == "WAVE") {
            "Not a valid RIFF/WAVE file"
        }

        var pos = 12
        var numChannels = 1
        var sampleRate = 0
        var bitsPerSample = 16
        var dataOffset = -1
        var dataSize = -1

        while (pos + 8 <= bytes.size) {
            val chunkId = String(bytes, pos, 4, Charsets.US_ASCII)
            val chunkSize = readLE32(bytes, pos + 4)
            when (chunkId) {
                "fmt " -> {
                    val audioFormat = readLE16(bytes, pos + 8)   // 1 = PCM
                    require(audioFormat == 1) {
                        "Only uncompressed PCM WAV is supported (audioFormat=$audioFormat)."
                    }
                    numChannels = readLE16(bytes, pos + 10)
                    sampleRate  = readLE32(bytes, pos + 12)
                    bitsPerSample = readLE16(bytes, pos + 22)
                }
                "data" -> {
                    dataOffset = pos + 8
                    dataSize   = chunkSize
                }
            }
            pos += 8 + chunkSize + (chunkSize and 1)
            if (dataOffset != -1) break
        }

        require(dataOffset != -1)  { "No 'data' chunk found in WAV." }
        require(bitsPerSample == 16) {
            "Expected 16-bit PCM, got ${bitsPerSample}-bit."
        }
        require(sampleRate == Config.SAMPLE_RATE) {
            "Audio file is $sampleRate Hz, but app expects ${Config.SAMPLE_RATE} Hz."
        }

        val totalFrames = dataSize / (numChannels * 2)   // 2 bytes per 16-bit sample
        val doubles = DoubleArray(totalFrames)
        var bi = dataOffset
        for (i in 0 until totalFrames) {
            if (numChannels == 1) {
                doubles[i] = readLE16Signed(bytes, bi) / 32768.0
                bi += 2
            } else {
                // Downmix stereo → mono by averaging L and R channels
                val left  = readLE16Signed(bytes, bi)
                val right = readLE16Signed(bytes, bi + 2)
                doubles[i] = (left + right) / 2.0 / 32768.0
                bi += numChannels * 2
            }
        }
        return doubles
    }

    // ── Write ─────────────────────────────────────────────────────────────

    /**
     * Writes normalized [-1.0, 1.0] [samples] to a 44100 Hz / mono / 16-bit
     * PCM WAV file at [outFile].
     */
    fun writeWav(samples: DoubleArray, outFile: File) {
        val numSamples = samples.size
        val byteRate   = Config.SAMPLE_RATE * 2         // 1 ch × 2 bytes/sample
        val dataSize   = numSamples * 2                 // bytes in data chunk
        val fileSize   = 36 + dataSize                  // total RIFF size - 8

        FileOutputStream(outFile).use { fos ->
            // RIFF header
            fos.write("RIFF".toByteArray(Charsets.US_ASCII))
            fos.writeLE32(fileSize)
            fos.write("WAVE".toByteArray(Charsets.US_ASCII))

            // fmt  chunk (16 bytes)
            fos.write("fmt ".toByteArray(Charsets.US_ASCII))
            fos.writeLE32(16)                            // chunk size
            fos.writeLE16(1)                             // PCM
            fos.writeLE16(1)                             // mono
            fos.writeLE32(Config.SAMPLE_RATE)
            fos.writeLE32(byteRate)
            fos.writeLE16(2)                             // block align
            fos.writeLE16(16)                            // bits per sample

            // data chunk
            fos.write("data".toByteArray(Charsets.US_ASCII))
            fos.writeLE32(dataSize)
            val buf = ByteArray(2)
            for (s in samples) {
                val v = (s * 32767.0).toInt().coerceIn(-32768, 32767)
                buf[0] = (v and 0xFF).toByte()
                buf[1] = ((v shr 8) and 0xFF).toByte()
                fos.write(buf)
            }
        }
    }

    // ── LE read helpers ──────────────────────────────────────────────────

    private fun readLE16(b: ByteArray, offset: Int): Int =
        (b[offset].toInt() and 0xFF) or ((b[offset + 1].toInt() and 0xFF) shl 8)

    private fun readLE16Signed(b: ByteArray, offset: Int): Int {
        val lo = b[offset].toInt() and 0xFF
        val hi = b[offset + 1].toInt()
        return (hi shl 8) or lo
    }

    private fun readLE32(b: ByteArray, offset: Int): Int =
        (b[offset].toInt() and 0xFF) or
        ((b[offset + 1].toInt() and 0xFF) shl 8) or
        ((b[offset + 2].toInt() and 0xFF) shl 16) or
        ((b[offset + 3].toInt() and 0xFF) shl 24)

    // ── LE write helpers ─────────────────────────────────────────────────

    private fun FileOutputStream.writeLE16(v: Int) {
        write(v and 0xFF)
        write((v shr 8) and 0xFF)
    }

    private fun FileOutputStream.writeLE32(v: Int) {
        write(v and 0xFF)
        write((v shr 8) and 0xFF)
        write((v shr 16) and 0xFF)
        write((v shr 24) and 0xFF)
    }
}
