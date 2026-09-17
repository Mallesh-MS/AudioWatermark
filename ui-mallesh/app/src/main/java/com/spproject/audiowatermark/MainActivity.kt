package com.spproject.audiowatermark

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.spproject.audiowatermark.databinding.ActivityMainBinding

/**
 * Single-screen UI that wires together the transmitter and receiver.
 *
 * Person A flow:
 *   1. Types a message in the text field.
 *   2. Taps "Encrypt, Embed & Play".
 *   3. App encrypts, embeds watermark into host_song.wav, starts playback.
 *   4. Status bar tracks the playback state in real time.
 *
 * Person B flow:
 *   1. Taps "Listen & Decode" (microphone permission requested if not granted).
 *   2. App records for 20 seconds, runs the decoder pipeline.
 *   3. Status bar shows the specific outcome — never a bare "failed":
 *        • Success          → displays the recovered message
 *        • No signal        → tells the user the energy was below threshold + value
 *        • No preamble lock → energy was detected but lock position failed
 *        • Decrypt failed   → specific error (bad bits, wrong key, truncated)
 *        • Garbage output   → decrypted but not readable UTF-8
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    private val transmitter = AudioTransmitter()
    private var receiver: AudioReceiver? = null

    enum class StatusState {
        IDLE,
        IN_PROGRESS,
        SUCCESS,
        NO_SIGNAL,
        NO_PREAMBLE_LOCK,
        DECRYPT_FAILED,
        GARBAGE_OUTPUT,
        WARNING,
        ERROR
    }

    /**
     * Looks up R.raw.host_song by name at runtime so the project compiles even before
     * host_song.wav is placed in res/raw/.  Returns 0 if the resource is not found.
     * Place your 44100 Hz / mono / 16-bit WAV at app/src/main/res/raw/host_song.wav
     * (see WavUtils for ffmpeg conversion command) to make this resolve.
     */
    private val hostSongResId: Int
        get() = resources.getIdentifier("host_song", "raw", packageName)

    private val micPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            startListening()
        } else {
            setStatus(
                "⚠ Microphone permission denied — cannot receive messages.",
                StatusState.ERROR,
                "PERMISSION DENIED"
            )
            setBothButtonsEnabled(true)
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnSend.setOnClickListener   { onSendClicked() }
        binding.btnListen.setOnClickListener { onListenClicked() }

        setStatus("Idle — type a message and tap a button.", StatusState.IDLE, "IDLE")
    }

    override fun onDestroy() {
        super.onDestroy()
        transmitter.release()
        receiver?.stop()
    }

    // ── Button handlers ────────────────────────────────────────────────

    private fun onSendClicked() {
        val message = binding.editMessage.text?.toString()?.trim() ?: ""
        if (message.isBlank()) {
            setStatus("⚠ Please type a message first.", StatusState.WARNING, "EMPTY MESSAGE")
            return
        }

        setBothButtonsEnabled(false)
        setStatus("Encrypting…", StatusState.IN_PROGRESS, "ENCRYPTING")

        Thread {
            try {
                // Encrypt
                val cipherBytes = AesCrypto.encrypt(message)
                val neededSec = TransmissionSizing.totalSecondsNeeded(cipherBytes.size)

                // Build watermark audio sequence
                val watermark = ToneGenerator.buildWatermarkSequence(cipherBytes)

                // Load host song — requires host_song.wav in res/raw/
                runOnUiThread { setStatus("Loading host song…", StatusState.IN_PROGRESS, "LOADING AUDIO") }
                val resId = hostSongResId
                if (resId == 0) {
                    runOnUiThread {
                        setStatus(
                            "⚠ host_song.wav not found in res/raw/.\n\n" +
                            "Place a 44100 Hz / mono / 16-bit PCM WAV at:\n" +
                            "  app/src/main/res/raw/host_song.wav\n\n" +
                            "Convert with ffmpeg:\n" +
                            "  ffmpeg -i song.mp3 -ar 44100 -ac 1 -sample_fmt s16 host_song.wav",
                            StatusState.ERROR,
                            "HOST SONG MISSING"
                        )
                        setBothButtonsEnabled(true)
                    }
                    return@Thread
                }
                val hostSamples = WavUtils.loadWavAsDoubles(this, resId)

                val startIndex = Config.SAMPLE_RATE   // embed 1 second into the song
                val availableSec = (hostSamples.size - startIndex) / Config.SAMPLE_RATE.toDouble()
                if (availableSec < neededSec) {
                    runOnUiThread {
                        setStatus(
                            "⚠ Host song too short for this message.\n" +
                            "Need %.1f s of audio after the 1 s offset, but only %.1f s available.\n" +
                            "Shorten your message or use a longer song.".format(neededSec, availableSec),
                            StatusState.ERROR,
                            "SONG TOO SHORT"
                        )
                        setBothButtonsEnabled(true)
                    }
                    return@Thread
                }

                // Mix
                runOnUiThread {
                    setStatus(
                        "Embedding watermark (%.1f s)…".format(neededSec),
                        StatusState.IN_PROGRESS,
                        "EMBEDDING"
                    )
                }
                val mixed = Embedder.embed(hostSamples, watermark, startIndex)

                // Play
                runOnUiThread {
                    setStatus(
                        "▶ Playing watermarked song (~%.1f s)…\nPerson B: tap Listen now!".format(
                            mixed.size / Config.SAMPLE_RATE.toDouble()
                        ),
                        StatusState.IN_PROGRESS,
                        "TRANSMITTING"
                    )
                    transmitter.play(mixed) {
                        runOnUiThread {
                            setStatus("✓ Playback finished.", StatusState.SUCCESS, "PLAYBACK COMPLETE")
                            setBothButtonsEnabled(true)
                        }
                    }
                }
            } catch (e: IllegalArgumentException) {
                runOnUiThread {
                    setStatus("⚠ Input error: ${e.message}", StatusState.ERROR, "INPUT ERROR")
                    setBothButtonsEnabled(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    setStatus("⚠ Unexpected error: ${e.javaClass.simpleName}: ${e.message}", StatusState.ERROR, "UNEXPECTED ERROR")
                    setBothButtonsEnabled(true)
                }
            }
        }.apply {
            name = "MainActivity-send"
            isDaemon = true
            start()
        }
    }

    private fun onListenClicked() {
        val hasMic = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                     PackageManager.PERMISSION_GRANTED
        if (hasMic) startListening() else micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }

    // ── Listening flow ─────────────────────────────────────────────────

    private fun startListening() {
        setBothButtonsEnabled(false)
        receiver?.stop()

        val listenSec = 20
        receiver = AudioReceiver(
            listenDurationSec = listenSec,
            onProgressSec = { elapsed ->
                val remaining = listenSec - elapsed
                runOnUiThread {
                    setStatus(
                        "🎙 Listening… $remaining s remaining\n(Person A: play the song now)",
                        StatusState.IN_PROGRESS,
                        "LISTENING (${remaining}s)"
                    )
                }
            }
        )
        setStatus(
            "🎙 Listening for $listenSec s…\n(Person A: play the song now)",
            StatusState.IN_PROGRESS,
            "LISTENING"
        )

        receiver!!.listen { result ->
            runOnUiThread {
                handleDecodeResult(result)
                setBothButtonsEnabled(true)
            }
        }
    }

    // ── Decode result → UI ─────────────────────────────────────────────

    private fun handleDecodeResult(result: Decoder.DecodeResult) {
        when (result) {
            is Decoder.DecodeResult.Success -> {
                setStatus(
                    "✓ Message decoded successfully!\n\n" +
                    "\"${result.message}\"\n\n" +
                    "(Preamble locked at sample ${result.preambleEndSample}, " +
                    "energy = ${"%.0f".format(result.preamblePeakEnergy)})",
                    StatusState.SUCCESS,
                    "DECODE SUCCESS"
                )
            }

            is Decoder.DecodeResult.NoSignal -> {
                setStatus(
                    "✗ No signal detected.\n\n" +
                    "Max preamble-frequency energy seen: ${"%.0f".format(result.maxPreambleEnergy)}\n" +
                    "Detection threshold: ${"%.0f".format(result.threshold)}\n\n" +
                    "Fixes to try:\n" +
                    "  • Place the phones closer together (< 30 cm)\n" +
                    "  • Increase speaker volume on Person A's phone\n" +
                    "  • Reduce background noise\n" +
                    "  • Increase Config.WATERMARK_AMPLITUDE and rebuild",
                    StatusState.NO_SIGNAL,
                    "NO SIGNAL DETECTED"
                )
            }

            is Decoder.DecodeResult.NoPreambleLock -> {
                setStatus(
                    "✗ Preamble energy detected but lock failed.\n\n" +
                    "Peak energy = ${"%.0f".format(result.preamblePeakEnergy)} " +
                    "(threshold ${result.threshold.toInt()})\n\n" +
                    "This usually means the preamble was clipped or distorted.\n" +
                    "Fixes:\n" +
                    "  • Reduce Person A's speaker volume slightly\n" +
                    "  • Start listening before Person A presses Play\n" +
                    "  • Verify both phones use the same Config constants",
                    StatusState.NO_PREAMBLE_LOCK,
                    "PREAMBLE LOCK FAILED"
                )
            }

            is Decoder.DecodeResult.DecryptFailed -> {
                setStatus(
                    "✗ Decryption failed — bits probably corrupted.\n\n" +
                    "Preamble at sample ${result.preambleEndSample}, " +
                    "cipher length = ${result.cipherLength} bytes\n" +
                    "Reason: ${result.reason}\n\n" +
                    "Fixes:\n" +
                    "  • Reduce room noise / reflections\n" +
                    "  • Move phones closer\n" +
                    "  • Verify SHARED_PASSPHRASE is identical on both phones\n" +
                    "  • Check Logcat for per-bit Goertzel energy values",
                    StatusState.DECRYPT_FAILED,
                    "DECRYPTION FAILED"
                )
            }

            is Decoder.DecodeResult.GarbageOutput -> {
                setStatus(
                    "✗ Garbage output — decryption ran but result is not readable text.\n\n" +
                    "Raw decrypted bytes (truncated): \"${result.rawDecrypted.take(40)}…\"\n\n" +
                    "This almost always means multiple bit errors in the payload.\n" +
                    "AES-CTR has no integrity check, so a flipped bit in ciphertext " +
                    "produces a flipped bit in plaintext without throwing.\n" +
                    "Fixes: see Logcat Goertzel energy tables to find which bits decoded wrong.",
                    StatusState.GARBAGE_OUTPUT,
                    "CORRUPTED PAYLOAD"
                )
            }
        }
    }

    // ── UI helpers ─────────────────────────────────────────────────────

    private fun setStatus(text: String, state: StatusState = StatusState.IDLE, badge: String? = null) {
        val style = when (state) {
            StatusState.IDLE -> StyleConfig(
                R.color.status_idle_bg,
                R.color.status_idle_stroke,
                R.drawable.bg_badge_idle,
                R.color.status_idle_badge_text,
                R.color.status_idle_text,
                R.color.status_idle_title,
                R.color.status_idle_icon,
                R.drawable.ic_info,
                false
            )
            StatusState.IN_PROGRESS -> StyleConfig(
                R.color.status_progress_bg,
                R.color.status_progress_stroke,
                R.drawable.bg_badge_progress,
                R.color.status_progress_badge_text,
                R.color.status_progress_text,
                R.color.status_progress_title,
                R.color.status_progress_icon,
                R.drawable.ic_waveform,
                true
            )
            StatusState.SUCCESS -> StyleConfig(
                R.color.status_success_bg,
                R.color.status_success_stroke,
                R.drawable.bg_badge_success,
                R.color.status_success_badge_text,
                R.color.status_success_text,
                R.color.status_success_title,
                R.color.status_success_icon,
                R.drawable.ic_check_circle,
                false
            )
            StatusState.NO_SIGNAL -> StyleConfig(
                R.color.status_nosignal_bg,
                R.color.status_nosignal_stroke,
                R.drawable.bg_badge_nosignal,
                R.color.status_nosignal_badge_text,
                R.color.status_nosignal_text,
                R.color.status_nosignal_title,
                R.color.status_nosignal_icon,
                R.drawable.ic_signal_off,
                false
            )
            StatusState.NO_PREAMBLE_LOCK -> StyleConfig(
                R.color.status_preamble_bg,
                R.color.status_preamble_stroke,
                R.drawable.bg_badge_preamble,
                R.color.status_preamble_badge_text,
                R.color.status_preamble_text,
                R.color.status_preamble_title,
                R.color.status_preamble_icon,
                R.drawable.ic_lock_open,
                false
            )
            StatusState.DECRYPT_FAILED -> StyleConfig(
                R.color.status_decrypt_bg,
                R.color.status_decrypt_stroke,
                R.drawable.bg_badge_decrypt,
                R.color.status_decrypt_badge_text,
                R.color.status_decrypt_text,
                R.color.status_decrypt_title,
                R.color.status_decrypt_icon,
                R.drawable.ic_key_off,
                false
            )
            StatusState.GARBAGE_OUTPUT -> StyleConfig(
                R.color.status_garbage_bg,
                R.color.status_garbage_stroke,
                R.drawable.bg_badge_garbage,
                R.color.status_garbage_badge_text,
                R.color.status_garbage_text,
                R.color.status_garbage_title,
                R.color.status_garbage_icon,
                R.drawable.ic_code_off,
                false
            )
            StatusState.WARNING -> StyleConfig(
                R.color.status_nosignal_bg,
                R.color.status_nosignal_stroke,
                R.drawable.bg_badge_nosignal,
                R.color.status_nosignal_badge_text,
                R.color.status_nosignal_text,
                R.color.status_nosignal_title,
                R.color.status_nosignal_icon,
                R.drawable.ic_warning,
                false
            )
            StatusState.ERROR -> StyleConfig(
                R.color.status_error_bg,
                R.color.status_error_stroke,
                R.drawable.bg_badge_error,
                R.color.status_error_badge_text,
                R.color.status_error_text,
                R.color.status_error_title,
                R.color.status_error_icon,
                R.drawable.ic_error,
                false
            )
        }

        binding.cardStatus.setCardBackgroundColor(ContextCompat.getColor(this, style.bgColor))
        binding.cardStatus.strokeColor = ContextCompat.getColor(this, style.strokeColor)
        binding.imgStatusIcon.setImageResource(style.iconRes)
        binding.imgStatusIcon.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(this, style.iconColor))
        binding.txtStatusHeader.setTextColor(ContextCompat.getColor(this, style.titleColor))
        binding.txtStatusBadge.text = badge ?: state.name.replace('_', ' ')
        binding.txtStatusBadge.setBackgroundResource(style.badgeBgRes)
        binding.txtStatusBadge.setTextColor(ContextCompat.getColor(this, style.badgeTextColor))
        binding.txtStatus.setTextColor(ContextCompat.getColor(this, style.textColor))
        binding.dividerStatus.setBackgroundColor(ContextCompat.getColor(this, style.strokeColor))
        binding.progressStatus.visibility = if (style.inProgress) View.VISIBLE else View.GONE
        binding.txtStatus.text = text
    }

    private data class StyleConfig(
        val bgColor: Int,
        val strokeColor: Int,
        val badgeBgRes: Int,
        val badgeTextColor: Int,
        val textColor: Int,
        val titleColor: Int,
        val iconColor: Int,
        val iconRes: Int,
        val inProgress: Boolean
    )

    private fun setBothButtonsEnabled(enabled: Boolean) {
        binding.btnSend.isEnabled   = enabled
        binding.btnListen.isEnabled = enabled
        val alpha = if (enabled) 1.0f else 0.5f
        binding.btnSend.alpha   = alpha
        binding.btnListen.alpha = alpha
    }
}

