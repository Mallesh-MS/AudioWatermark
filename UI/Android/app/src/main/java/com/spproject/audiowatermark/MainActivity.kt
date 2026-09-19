package com.spproject.audiowatermark

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.spproject.audiowatermark.databinding.ActivityMainBinding
import java.io.File

/**
 * Single-screen UI wiring together the transmitter and receiver.
 * Supports:
 *   • Local acoustic transmission via phone speaker & mic (17–20 kHz)
 *   • 20 km / Global Digital Steganography via Audio File Export & Sharing (WhatsApp/Telegram/Drive)
 *   • Audio File Picking & Instant Decoding
 *   • Encoding Profiles (Standard Fast vs High Robustness)
 *   • Quick Test Presets: HELLO, PASS_2026, PAY_100, SHARE_20KM
 *   • Decoded Message copy-to-clipboard and signal diagnostics
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

    private val hostSongResId: Int
        get() = resources.getIdentifier("host_song", "raw", packageName)

    private val micPermissionLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            startListening()
        } else {
            setStatus(
                "⚠ Microphone permission denied — cannot receive acoustic messages.",
                StatusState.ERROR,
                "PERMISSION DENIED"
            )
            setBothButtonsEnabled(true)
        }
    }

    private val filePickerLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            decodeSelectedAudioFile(uri)
        } else {
            setStatus("File selection canceled.", StatusState.IDLE, "CANCELED")
            setBothButtonsEnabled(true)
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupRangeModeSelector()
        setupSecretKey()
        setupPresetChips()
        setupMessageInput()

        binding.btnSend.setOnClickListener        { onSendClicked() }
        binding.btnExportAudio.setOnClickListener { onExportAudioClicked() }
        binding.btnListen.setOnClickListener      { onListenClicked() }
        binding.btnPickFile.setOnClickListener    { onPickFileClicked() }
        binding.btnCopyMessage.setOnClickListener { onCopyClicked() }

        updateEstimatedDuration()
        setStatus(
            "Ready — Transmit nearby via speaker, OR export watermarked audio to share across 20 km.",
            StatusState.IDLE,
            "READY"
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        transmitter.release()
        receiver?.stop()
    }

    // ── Setup Helpers ──────────────────────────────────────────────────

    private fun setupSecretKey() {
        binding.chipDefaultKey.setOnClickListener {
            binding.editSecretKey.setText(Config.SHARED_PASSPHRASE)
            binding.editSecretKey.setSelection(binding.editSecretKey.text?.length ?: 0)
            Toast.makeText(this, "Secret Key set to Default", Toast.LENGTH_SHORT).show()
        }
        binding.chipCustomKey.setOnClickListener {
            binding.editSecretKey.setText("TOP_SECRET_42")
            binding.editSecretKey.setSelection(binding.editSecretKey.text?.length ?: 0)
            Toast.makeText(this, "Secret Key set to TOP_SECRET_42", Toast.LENGTH_SHORT).show()
        }
        binding.chipWrongKey.setOnClickListener {
            binding.editSecretKey.setText("INVALID_KEY_999")
            binding.editSecretKey.setSelection(binding.editSecretKey.text?.length ?: 0)
            Toast.makeText(this, "Secret Key set to INVALID_KEY_999 (Test Mismatch)", Toast.LENGTH_SHORT).show()
        }

        binding.editSecretKey.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {
                updateEstimatedDuration()
            }
            override fun afterTextChanged(s: Editable?) {}
        })
    }

    private fun getActivePassphrase(): String {
        val pass = binding.editSecretKey.text?.toString()?.trim()
        return if (pass.isNullOrEmpty()) Config.SHARED_PASSPHRASE else pass
    }

    private fun setupRangeModeSelector() {
        binding.toggleGroupRange.check(R.id.btnModeStandard)
        Config.activeMode = Config.RangeMode.STANDARD

        binding.toggleGroupRange.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (isChecked) {
                when (checkedId) {
                    R.id.btnModeStandard -> {
                        Config.activeMode = Config.RangeMode.STANDARD
                        binding.txtRangeBadge.text = "STANDARD"
                        binding.txtRangeBadge.setTextColor(ContextCompat.getColor(this, R.color.primary))
                        binding.txtRangeBadge.setBackgroundResource(R.drawable.bg_badge_primary)
                        binding.txtRangeDescription.text = Config.activeMode.description
                    }
                    R.id.btnModeLongRange -> {
                        Config.activeMode = Config.RangeMode.LONG_RANGE
                        binding.txtRangeBadge.text = "HIGH ROBUSTNESS"
                        binding.txtRangeBadge.setTextColor(ContextCompat.getColor(this, R.color.secondary))
                        binding.txtRangeBadge.setBackgroundResource(R.drawable.bg_badge_secondary)
                        binding.txtRangeDescription.text = Config.activeMode.description
                    }
                }
                updateEstimatedDuration()
            }
        }
    }

    private fun setupPresetChips() {
        binding.chipPresetHello.setOnClickListener {
            binding.editMessage.setText("HELLO")
            binding.editMessage.setSelection(binding.editMessage.text?.length ?: 0)
        }
        binding.chipPresetPass.setOnClickListener {
            binding.editMessage.setText("PASS_2026")
            binding.editMessage.setSelection(binding.editMessage.text?.length ?: 0)
        }
        binding.chipPresetPay.setOnClickListener {
            binding.editMessage.setText("PAY_100")
            binding.editMessage.setSelection(binding.editMessage.text?.length ?: 0)
        }
        binding.chipPresetRange.setOnClickListener {
            binding.editMessage.setText("SHARE_20KM")
            binding.editMessage.setSelection(binding.editMessage.text?.length ?: 0)
        }
    }

    private fun setupMessageInput() {
        binding.editMessage.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {
                updateEstimatedDuration()
            }
            override fun afterTextChanged(s: Editable?) {}
        })
    }

    private fun updateEstimatedDuration() {
        val message = binding.editMessage.text?.toString()?.trim() ?: "HELLO"
        val passphrase = getActivePassphrase()
        val cipherByteEst = try {
            AesCrypto.encrypt(if (message.isEmpty()) "HELLO" else message, passphrase).size
        } catch (e: Exception) {
            32
        }
        val duration = TransmissionSizing.totalSecondsNeeded(cipherByteEst, Config.activeMode)
        binding.txtEstimatedDuration.text = "~%.1f s duration".format(duration)
    }

    private fun onCopyClicked() {
        val textToCopy = binding.txtDecodedMessage.text.toString()
        if (textToCopy.isNotBlank()) {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Decoded Ultrasonic Message", textToCopy)
            clipboard.setPrimaryClip(clip)
            Toast.makeText(this, "Copied to clipboard: $textToCopy", Toast.LENGTH_SHORT).show()
        }
    }

    // ── Transmitter Flows ──────────────────────────────────────────────

    private fun buildAudioSamplesForMessage(message: String): DoubleArray {
        val mode = Config.activeMode
        val passphrase = getActivePassphrase()
        val cipherBytes = AesCrypto.encrypt(message, passphrase)
        val neededSec = TransmissionSizing.totalSecondsNeeded(cipherBytes.size, mode)
        val watermark = ToneGenerator.buildWatermarkSequence(cipherBytes, mode)

        val pureUltrasonic = binding.switchCarrierMode.isChecked
        return if (pureUltrasonic) {
            val pad = (Config.SAMPLE_RATE * 0.4).toInt() // 400ms padding
            DoubleArray(pad + watermark.size + pad) { i ->
                if (i in pad until pad + watermark.size) watermark[i - pad] else 0.0
            }
        } else {
            val resId = hostSongResId
            if (resId == 0) {
                throw IllegalStateException("host_song.wav not found in res/raw/. Switch to Pure Ultrasonic mode or add host_song.wav.")
            }
            val hostSamples = WavUtils.loadWavAsDoubles(this, resId)
            val startIndex = Config.SAMPLE_RATE
            val availableSec = (hostSamples.size - startIndex) / Config.SAMPLE_RATE.toDouble()
            if (availableSec < neededSec) {
                throw IllegalStateException(
                    "Host song too short for this message (need %.1f s, only %.1f s available).".format(neededSec, availableSec)
                )
            }
            Embedder.embed(hostSamples, watermark, startIndex)
        }
    }

    private fun onSendClicked() {
        val message = binding.editMessage.text?.toString()?.trim() ?: ""
        if (message.isBlank()) {
            setStatus("⚠ Please type a message or select a preset first.", StatusState.WARNING, "EMPTY MESSAGE")
            return
        }

        setBothButtonsEnabled(false)
        binding.layoutDecodedResult.visibility = View.GONE
        setStatus("Encrypting for ${Config.activeMode.displayName}…", StatusState.IN_PROGRESS, "ENCRYPTING")

        Thread {
            try {
                val audioToPlay = buildAudioSamplesForMessage(message)
                val durationSec = audioToPlay.size / Config.SAMPLE_RATE.toDouble()

                runOnUiThread {
                    val modeLabel = if (binding.switchCarrierMode.isChecked) "pure ultrasonic carrier" else "watermarked song"
                    setStatus(
                        "▶ Transmitting $modeLabel (~%.1f s)\nProfile: %s\nPerson B: tap Listen now!".format(durationSec, Config.activeMode.displayName),
                        StatusState.IN_PROGRESS,
                        "TRANSMITTING"
                    )
                    transmitter.play(audioToPlay) {
                        runOnUiThread {
                            setStatus(
                                "✓ Transmission finished (%.1f s).\nReady for next transmission or reception.".format(durationSec),
                                StatusState.SUCCESS,
                                "TRANSMIT COMPLETE"
                            )
                            setBothButtonsEnabled(true)
                        }
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    setStatus("⚠ ${e.message}", StatusState.ERROR, "ERROR")
                    setBothButtonsEnabled(true)
                }
            }
        }.apply {
            name = "MainActivity-send"
            isDaemon = true
            start()
        }
    }

    /**
     * Creates a watermarked 16-bit 44.1 kHz WAV file and shares it via Android system share sheet.
     * Works over ANY distance (20 km, 2000 km, across the world).
     */
    private fun onExportAudioClicked() {
        val message = binding.editMessage.text?.toString()?.trim() ?: ""
        if (message.isBlank()) {
            setStatus("⚠ Please type a message or select a preset first.", StatusState.WARNING, "EMPTY MESSAGE")
            return
        }

        setBothButtonsEnabled(false)
        binding.layoutDecodedResult.visibility = View.GONE
        setStatus("Generating watermarked audio file…", StatusState.IN_PROGRESS, "CREATING FILE")

        Thread {
            try {
                val audioSamples = buildAudioSamplesForMessage(message)

                val exportDir = File(cacheDir, "shared_audio").apply { mkdirs() }
                val exportFile = File(exportDir, "secret_watermarked_audio.wav")
                WavUtils.writeWav(audioSamples, exportFile)

                val contentUri = FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    exportFile
                )

                runOnUiThread {
                    setBothButtonsEnabled(true)
                    setStatus(
                        "✓ Watermarked audio file created!\n\n" +
                        "File: secret_watermarked_audio.wav\n" +
                        "Size: ${exportFile.length() / 1024} KB\n" +
                        "Profile: ${Config.activeMode.displayName}\n\n" +
                        "Opening share sheet — Send this file via WhatsApp, Telegram, Drive or Email to Person B (20 km away)!",
                        StatusState.SUCCESS,
                        "FILE READY"
                    )

                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "audio/wav"
                        putExtra(Intent.EXTRA_STREAM, contentUri)
                        putExtra(Intent.EXTRA_SUBJECT, "Secret Watermarked Audio File")
                        putExtra(Intent.EXTRA_TEXT, "Here is the watermarked audio file. Open it with the Audio Watermark app to decode!")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(shareIntent, "Share Watermarked Audio (20 km)"))
                }
            } catch (e: Exception) {
                runOnUiThread {
                    setStatus("⚠ Failed to export audio: ${e.message}", StatusState.ERROR, "EXPORT FAILED")
                    setBothButtonsEnabled(true)
                }
            }
        }.apply {
            name = "MainActivity-export"
            isDaemon = true
            start()
        }
    }

    // ── Receiver Flows ─────────────────────────────────────────────────

    private fun onListenClicked() {
        val hasMic = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                     PackageManager.PERMISSION_GRANTED
        if (hasMic) startListening() else micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }

    private fun startListening() {
        setBothButtonsEnabled(false)
        binding.layoutDecodedResult.visibility = View.GONE
        receiver?.stop()

        val mode = Config.activeMode
        val listenSec = 20
        receiver = AudioReceiver(
            listenDurationSec = listenSec,
            onProgressSec = { elapsed ->
                val remaining = listenSec - elapsed
                runOnUiThread {
                    setStatus(
                        "🎙 Listening for %s signal…\n⏱ %d seconds remaining\n(Person A: press transmit now!)".format(mode.displayName, remaining),
                        StatusState.IN_PROGRESS,
                        "LISTENING (${remaining}s)"
                    )
                }
            }
        )
        setStatus(
            "🎙 Listening for %s signal (%d s window)…\n(Person A: press transmit now!)".format(mode.displayName, listenSec),
            StatusState.IN_PROGRESS,
            "LISTENING"
        )

        val passphrase = getActivePassphrase()
        receiver!!.listen(mode = mode, passphrase = passphrase) { result ->
            runOnUiThread {
                handleDecodeResult(result)
                setBothButtonsEnabled(true)
            }
        }
    }

    private fun onPickFileClicked() {
        setBothButtonsEnabled(false)
        binding.layoutDecodedResult.visibility = View.GONE
        setStatus("Select a watermarked WAV audio file to decode…", StatusState.IN_PROGRESS, "SELECTING FILE")
        filePickerLauncher.launch("audio/*")
    }

    private fun decodeSelectedAudioFile(uri: Uri) {
        setBothButtonsEnabled(false)
        binding.layoutDecodedResult.visibility = View.GONE
        setStatus("Loading audio file and decoding watermark…", StatusState.IN_PROGRESS, "DECODING FILE")

        Thread {
            try {
                val inputStream = contentResolver.openInputStream(uri)
                    ?: throw IllegalArgumentException("Cannot open audio file stream.")
                val samples = WavUtils.loadWavFromStreamAsDoubles(inputStream)

                runOnUiThread {
                    setStatus(
                        "Analyzing ${samples.size} samples (%.1f s audio)…".format(samples.size / Config.SAMPLE_RATE.toDouble()),
                        StatusState.IN_PROGRESS,
                        "ANALYZING"
                    )
                }

                val passphrase = getActivePassphrase()
                // Decode with active mode and active passphrase
                var result = Decoder.decode(samples, mode = Config.activeMode, passphrase = passphrase)

                // If decode failed with active mode, attempt fallback with the other mode automatically!
                if (result !is Decoder.DecodeResult.Success) {
                    val alternateMode = if (Config.activeMode == Config.RangeMode.STANDARD)
                        Config.RangeMode.LONG_RANGE else Config.RangeMode.STANDARD
                    val altResult = Decoder.decode(samples, mode = alternateMode, passphrase = passphrase)
                    if (altResult is Decoder.DecodeResult.Success) {
                        result = altResult
                    }
                }

                runOnUiThread {
                    handleDecodeResult(result)
                    setBothButtonsEnabled(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    setStatus(
                        "⚠ Failed to read audio file: ${e.message}\n\nMake sure the file is a 16-bit 44.1 kHz PCM WAV file.",
                        StatusState.ERROR,
                        "FILE ERROR"
                    )
                    setBothButtonsEnabled(true)
                }
            }
        }.apply {
            name = "MainActivity-fileDecode"
            isDaemon = true
            start()
        }
    }

    // ── Decode result → UI ─────────────────────────────────────────────

    private fun handleDecodeResult(result: Decoder.DecodeResult) {
        when (result) {
            is Decoder.DecodeResult.Success -> {
                binding.layoutDecodedResult.visibility = View.VISIBLE
                binding.txtDecodedMessage.text = result.message

                val snrQuality = when {
                    result.preamblePeakEnergy > 10.0 -> "EXCELLENT (HIGH SNR)"
                    result.preamblePeakEnergy > 4.0  -> "GOOD (MEDIUM SNR)"
                    else                             -> "WEAK (LOW SNR - BORDERLINE)"
                }

                setStatus(
                    "✓ Message decoded successfully!\n\n" +
                    "Profile:       ${result.mode.displayName}\n" +
                    "Secret Key:    '${getActivePassphrase()}'\n" +
                    "Signal Energy: ${"%.1f".format(result.preamblePeakEnergy)}  [$snrQuality]\n" +
                    "Threshold:     ${result.mode.detectionThreshold}\n" +
                    "Lock Sample:   #${result.preambleEndSample}\n" +
                    "Decryption:    AES-128-CTR verified",
                    StatusState.SUCCESS,
                    "DECODE SUCCESS"
                )
            }

            is Decoder.DecodeResult.NoSignal -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setStatus(
                    "✗ No ultrasonic carrier detected.\n\n" +
                    "Profile:       ${result.mode.displayName}\n" +
                    "Max Energy:    ${"%.1f".format(result.maxPreambleEnergy)} (Threshold: ${result.threshold})\n\n" +
                    "Checklist to fix:\n" +
                    "  • If testing over-the-air: Turn speaker volume up and bring phones within range\n" +
                    "  • If using 20 km file transfer: Use 'Share Audio File' and pick the received file\n" +
                    "  • Verify BOTH phones have the same profile selected",
                    StatusState.NO_SIGNAL,
                    "NO SIGNAL DETECTED"
                )
            }

            is Decoder.DecodeResult.NoPreambleLock -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setStatus(
                    "✗ Preamble energy was detected, but lock failed.\n\n" +
                    "Peak Energy:   ${"%.1f".format(result.preamblePeakEnergy)} (Threshold: ${result.threshold})\n" +
                    "Profile:       ${result.mode.displayName}\n\n" +
                    "Check speaker volume or verify both sides use identical profiles.",
                    StatusState.NO_PREAMBLE_LOCK,
                    "PREAMBLE LOCK FAILED"
                )
            }

            is Decoder.DecodeResult.DecryptFailed -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setStatus(
                    "✗ Decryption failed — key mismatch or bit errors.\n\n" +
                    "Profile:       ${result.mode.displayName}\n" +
                    "Active Key:    '${getActivePassphrase()}'\n" +
                    "Preamble Lock: sample #${result.preambleEndSample}\n" +
                    "Length Header: ${result.cipherLength} bytes\n" +
                    "Failure:       ${result.reason}\n\n" +
                    "Check: Verify that both sender and receiver are using the EXACT same Secret Key.",
                    StatusState.DECRYPT_FAILED,
                    "DECRYPTION FAILED"
                )
            }

            is Decoder.DecodeResult.GarbageOutput -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setStatus(
                    "✗ Secret Key Mismatch or Corrupted Payload!\n\n" +
                    "Active Key:    '${getActivePassphrase()}'\n" +
                    "Raw Output:    \"${result.rawDecrypted.take(35)}…\"\n\n" +
                    "AES-CTR decryption with an incorrect secret key decrypts ciphertext into random non-readable bytes.\n\n" +
                    "Troubleshooting:\n" +
                    "  1. Verify the Secret Passphrase matches the sender's key exactly.\n" +
                    "  2. If using Over-the-Air transmission, reduce background noise.",
                    StatusState.GARBAGE_OUTPUT,
                    "WRONG KEY"
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
        binding.btnSend.isEnabled        = enabled
        binding.btnExportAudio.isEnabled = enabled
        binding.btnListen.isEnabled      = enabled
        binding.btnPickFile.isEnabled    = enabled
        val alpha = if (enabled) 1.0f else 0.5f
        binding.btnSend.alpha        = alpha
        binding.btnExportAudio.alpha = alpha
        binding.btnListen.alpha      = alpha
        binding.btnPickFile.alpha    = alpha
    }
}
