package com.spproject.audiowatermark

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Plays the watermarked audio out through the phone speaker using [AudioTrack].
 *
 * Uses STREAM mode (not STATIC) so there is no built-in buffer-size limit —
 * STATIC mode caps the buffer at a few MB which would silently truncate a
 * multi-second song.  STREAM mode feeds audio in chunks on a background thread.
 */
class AudioTransmitter {

    private var track: AudioTrack? = null
    private var writeThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private companion object {
        const val TAG = "AudioTransmitter"
        const val WRITE_CHUNK_SHORTS = 4096   // samples per write call
    }

    /**
     * Converts [mixed] to 16-bit PCM and streams it to the speaker.
     *
     * @param mixed  Normalized [-1.0, 1.0] samples (e.g. from [Embedder.embed]).
     * @param onDone Optional callback invoked on the main thread when playback finishes.
     */
    fun play(mixed: DoubleArray, onDone: (() -> Unit)? = null) {
        // Stop any previous playback
        release()

        val minBuf = AudioTrack.getMinBufferSize(
            Config.SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        // Use a streaming buffer: 2× min or 0.5 s, whichever is bigger
        val streamBuf = maxOf(minBuf, Config.SAMPLE_RATE)  // 1 s worth of shorts = 44100×2 bytes

        val newTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(Config.SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(streamBuf * 2)   // bytes (2 per Short)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        track = newTrack
        newTrack.play()

        writeThread = Thread {
            Log.d(TAG, "Playback started: ${mixed.size} samples (${"%.1f".format(mixed.size / Config.SAMPLE_RATE.toDouble())} s)")
            var offset = 0
            while (offset < mixed.size) {
                if (track == null) break  // release() was called
                val len = minOf(WRITE_CHUNK_SHORTS, mixed.size - offset)
                val chunk = ShortArray(len) { i ->
                    (mixed[offset + i] * 32767.0).toInt().coerceIn(-32768, 32767).toShort()
                }
                val written = newTrack.write(chunk, 0, len)
                if (written < 0) {
                    Log.e(TAG, "AudioTrack.write() returned error $written")
                    break
                }
                offset += written
            }
            // Wait for the hardware buffer to drain before firing the callback
            newTrack.stop()
            Log.d(TAG, "Playback finished")
            mainHandler.post { onDone?.invoke() }
        }.apply {
            name = "AudioTransmitter-write"
            isDaemon = true
            start()
        }
    }

    /** Stops playback and releases all resources. Safe to call multiple times. */
    fun release() {
        writeThread?.interrupt()
        writeThread = null
        track?.pause()
        track?.flush()
        track?.release()
        track = null
    }
}
