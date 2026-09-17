package com.spproject.audiowatermark

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Records a fixed 20-second window of microphone audio, then passes it to
 * [Decoder.decode] for processing.
 *
 * Design rationale for the fixed-window approach:
 *  • Simple and predictable: the UI shows a countdown and the user knows
 *    exactly when to start playing Person A's phone.
 *  • Avoids the complexity of streaming buffer management / real-time
 *    preamble detection.  Good enough for a first working demo; once this
 *    is end-to-end verified you can add streaming detection.
 *
 * CALLER MUST have RECORD_AUDIO permission granted before calling [listen].
 */
class AudioReceiver(
    private val listenDurationSec: Int = 20,
    private val onProgressSec: ((Int) -> Unit)? = null   // optional countdown callback
) {

    private companion object {
        const val TAG = "AudioReceiver"
        const val READ_CHUNK = 4096   // samples per AudioRecord.read() call
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var stopRequested = false

    /**
     * Starts recording for [listenDurationSec] seconds on a background thread.
     * Calls [onResult] on the main thread with the [Decoder.DecodeResult].
     *
     * The caller must have already obtained RECORD_AUDIO permission.
     */
    @SuppressLint("MissingPermission")
    fun listen(onResult: (Decoder.DecodeResult) -> Unit) {
        stopRequested = false

        Thread {
            val minBuf = AudioRecord.getMinBufferSize(
                Config.SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val totalSamples = Config.SAMPLE_RATE * listenDurationSec
            val recBufBytes = maxOf(minBuf, READ_CHUNK * 2)

            val recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                Config.SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                recBufBytes
            )

            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                mainHandler.post {
                    onResult(Decoder.DecodeResult.NoSignal(0.0, 0.0))
                }
                return@Thread
            }

            val buffer = ShortArray(totalSamples)
            recorder.startRecording()
            Log.d(TAG, "Recording started: $listenDurationSec s target")

            var read = 0
            val startMs = System.currentTimeMillis()
            while (read < totalSamples && !stopRequested) {
                val toRead = minOf(READ_CHUNK, totalSamples - read)
                val got = recorder.read(buffer, read, toRead)
                if (got > 0) {
                    read += got
                    // Fire progress callback (elapsed seconds) on main thread
                    val elapsedSec = ((System.currentTimeMillis() - startMs) / 1000L).toInt()
                    mainHandler.post { onProgressSec?.invoke(elapsedSec) }
                } else if (got < 0) {
                    Log.e(TAG, "AudioRecord.read() returned error $got")
                    break
                }
            }

            recorder.stop()
            recorder.release()
            Log.d(TAG, "Recording finished: $read samples captured")

            val captured = DoubleArray(read) { i -> buffer[i] / 32768.0 }
            val result = Decoder.decode(captured)

            mainHandler.post { onResult(result) }
        }.apply {
            name = "AudioReceiver-record"
            isDaemon = true
            start()
        }
    }

    /** Requests early stop (recording will end at the next chunk boundary). */
    fun stop() {
        stopRequested = true
    }
}
