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
 * Modern, accessible UI/UX controller for Acoustic Audio Watermarking & Steganography.
 *
 * Provides:
 *   • Bottom navigation across Home, Send, Receive, and Settings & Help.
 *   • Guided 4-step transmission flow for beginners and non-technical users.
 *   • Dedicated reception experience with audio proximity diagrams and direct WAV decoding.
 *   • Full Level 1 (What am I doing), Level 2 (What to choose), and Level 3 (Engineering metrics) hierarchy.
 *   • End-to-end AES-128 secret key encryption/decryption with failure diagnosis.
 *   • Accessibility features: Large buttons, system text scaling resilience, and Reduce Motion.
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
        updateMicPermissionDisplay()
        if (granted) {
            startListening()
        } else {
            setReceiveStatus(
                "❌ Microphone permission denied — cannot capture acoustic sound.",
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
            setReceiveStatus("File selection canceled.", StatusState.IDLE, "CANCELED")
            setBothButtonsEnabled(true)
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupNavigation()
        setupOnboarding()
        setupRangeModeSelector()
        setupSecretKey()
        setupPresetChips()
        setupMessageInput()
        setupCarrierMode()
        setupEngineeringToggle()
        setupSettingsTab()

        binding.btnSend.setOnClickListener        { onSendClicked() }
        binding.btnExportAudio.setOnClickListener { onExportAudioClicked() }
        binding.btnListen.setOnClickListener      { onListenClicked() }
        binding.btnPickFile.setOnClickListener    { onPickFileClicked() }
        binding.btnCopyMessage.setOnClickListener { onCopyClicked() }

        updateEstimatedDuration()
        updateMicPermissionDisplay()

        setSendStatus("Ready to transmit — tap Send Message over Speaker, or export a file across 20 km.", StatusState.IDLE, "READY")
        setReceiveStatus("Ready to receive — tap 'Listen Nearby' to capture sound, or 'Open Audio File' to decode a file.", StatusState.IDLE, "READY")
    }

    override fun onDestroy() {
        super.onDestroy()
        transmitter.release()
        receiver?.stop()
    }

    // ── Navigation Setup ───────────────────────────────────────────────

    private fun setupNavigation() {
        binding.bottomNavigation.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_home -> switchTab(0)
                R.id.nav_send -> switchTab(1)
                R.id.nav_receive -> switchTab(2)
                R.id.nav_settings -> switchTab(3)
            }
            true
        }

        binding.cardHomeGoSend.setOnClickListener {
            binding.bottomNavigation.selectedItemId = R.id.nav_send
        }
        binding.cardHomeGoReceive.setOnClickListener {
            binding.bottomNavigation.selectedItemId = R.id.nav_receive
        }
    }

    private fun switchTab(index: Int) {
        binding.tabHome.visibility     = if (index == 0) View.VISIBLE else View.GONE
        binding.tabSend.visibility     = if (index == 1) View.VISIBLE else View.GONE
        binding.tabReceive.visibility  = if (index == 2) View.VISIBLE else View.GONE
        binding.tabSettings.visibility = if (index == 3) View.VISIBLE else View.GONE
    }

    private fun setupOnboarding() {
        val prefs = getSharedPreferences("steganography_prefs", Context.MODE_PRIVATE)
        val dismissed = prefs.getBoolean("onboarding_dismissed", false)
        if (dismissed) {
            binding.cardOnboarding.visibility = View.GONE
        }
        binding.btnDismissOnboarding.setOnClickListener {
            binding.cardOnboarding.visibility = View.GONE
            prefs.edit().putBoolean("onboarding_dismissed", true).apply()
        }
    }

    // ── Setup Helpers ──────────────────────────────────────────────────

    private fun setupSecretKey() {
        binding.chipDefaultKey.setOnClickListener {
            binding.editSecretKey.setText(Config.SHARED_PASSPHRASE)
            binding.editSecretKey.setSelection(binding.editSecretKey.text?.length ?: 0)
            Toast.makeText(this, "Secret Key set to Default Key", Toast.LENGTH_SHORT).show()
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
                        binding.txtRangeDescription.text = "Faster · 10 bps · Normal conditions"
                    }
                    R.id.btnModeLongRange -> {
                        Config.activeMode = Config.RangeMode.LONG_RANGE
                        binding.txtRangeDescription.text = "More reliable · 5 bps · Better in noise (+6 dB)"
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

    private fun setupCarrierMode() {
        binding.switchCarrierMode.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked) {
                binding.switchCarrierMode.text = "🔊 Pure Ultrasonic Sound"
                binding.txtCarrierDescription.text = "High-frequency sound (17–20 kHz) that is difficult for human ears to hear."
            } else {
                binding.switchCarrierMode.text = "🎶 Embed in Music"
                binding.txtCarrierDescription.text = "Hides the message beneath music tracks using acoustic masking."
            }
        }

        binding.btnExplainCarrier.setOnClickListener {
            val isVisible = binding.txtCarrierDetailPanel.visibility == View.VISIBLE
            binding.txtCarrierDetailPanel.visibility = if (isVisible) View.GONE else View.VISIBLE
            binding.btnExplainCarrier.text = if (isVisible) "ⓘ How does this work?" else "▲ Hide explanation"
        }
    }

    private fun setupEngineeringToggle() {
        binding.btnToggleEngineeringDetails.setOnClickListener {
            val isVis = binding.txtEngineeringDetails.visibility == View.VISIBLE
            binding.txtEngineeringDetails.visibility = if (isVis) View.GONE else View.VISIBLE
            binding.btnToggleEngineeringDetails.text = if (isVis) "▼ Advanced technical details" else "▲ Hide technical details"
        }
    }

    private fun setupSettingsTab() {
        val prefs = getSharedPreferences("steganography_prefs", Context.MODE_PRIVATE)
        binding.switchReduceMotion.isChecked = prefs.getBoolean("reduce_motion", false)
        binding.switchHighContrast.isChecked = prefs.getBoolean("high_contrast", true)

        binding.switchReduceMotion.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean("reduce_motion", isChecked).apply()
            Toast.makeText(this, "Reduce Motion: ${if (isChecked) "Enabled" else "Disabled"}", Toast.LENGTH_SHORT).show()
        }

        binding.switchHighContrast.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean("high_contrast", isChecked).apply()
            Toast.makeText(this, "High Contrast: ${if (isChecked) "Enabled" else "Standard"}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun updateMicPermissionDisplay() {
        val hasMic = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                     PackageManager.PERMISSION_GRANTED
        binding.txtMicPermissionStatus.text = if (hasMic) {
            "🎙 Microphone Permission: Granted"
        } else {
            "🎙 Microphone Permission: Not Granted (Tap 'Listen Nearby' to request)"
        }
        binding.txtMicPermissionStatus.setTextColor(
            ContextCompat.getColor(this, if (hasMic) R.color.primary else R.color.status_nosignal_title)
        )
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
            val clip = ClipData.newPlainText("Decoded Message", textToCopy)
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
                throw IllegalStateException("host_song.wav not found in res/raw/. Switch to Pure Ultrasonic sound or add host_song.wav.")
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
            setSendStatus("⚠ Please type a message or select a quick message first.", StatusState.WARNING, "EMPTY MESSAGE")
            return
        }

        setBothButtonsEnabled(false)
        setSendStatus("Encrypting message with secret key for ${Config.activeMode.displayName}…", StatusState.IN_PROGRESS, "ENCRYPTING")

        Thread {
            try {
                val audioToPlay = buildAudioSamplesForMessage(message)
                val durationSec = audioToPlay.size / Config.SAMPLE_RATE.toDouble()

                runOnUiThread {
                    val modeLabel = if (binding.switchCarrierMode.isChecked) "pure ultrasonic sound" else "watermarked song"
                    setSendStatus(
                        "▶ Transmitting $modeLabel (~%.1f s)\nProfile: %s\nReceiver: tap 'Listen Nearby' now!".format(durationSec, Config.activeMode.displayName),
                        StatusState.IN_PROGRESS,
                        "TRANSMITTING"
                    )
                    transmitter.play(audioToPlay) {
                        runOnUiThread {
                            setSendStatus(
                                "✓ Transmission complete (%.1f s).\nReady for next transmission or reception.".format(durationSec),
                                StatusState.SUCCESS,
                                "SENT"
                            )
                            binding.txtHomeRecentActivity.text = "Last sent: '$message' via ${Config.activeMode.displayName}"
                            setBothButtonsEnabled(true)
                        }
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    setSendStatus("⚠ ${e.message}", StatusState.ERROR, "ERROR")
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
     * Works across 20 km, 2000 km, or across the world via messaging apps / email / cloud.
     */
    private fun onExportAudioClicked() {
        val message = binding.editMessage.text?.toString()?.trim() ?: ""
        if (message.isBlank()) {
            setSendStatus("⚠ Please type a message or select a quick message first.", StatusState.WARNING, "EMPTY MESSAGE")
            return
        }

        setBothButtonsEnabled(false)
        setSendStatus("Generating lossless watermarked audio file…", StatusState.IN_PROGRESS, "CREATING FILE")

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
                    setSendStatus(
                        "✓ Watermarked audio file created!\n\n" +
                        "File: secret_watermarked_audio.wav (${exportFile.length() / 1024} KB)\n" +
                        "Profile: ${Config.activeMode.displayName}\n\n" +
                        "Opening share sheet — Send this file via WhatsApp, Telegram, or Drive to Person B (20 km away)!",
                        StatusState.SUCCESS,
                        "FILE READY"
                    )
                    binding.txtHomeRecentActivity.text = "Last exported file: '$message' for 20 km transfer"

                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "audio/wav"
                        putExtra(Intent.EXTRA_STREAM, contentUri)
                        putExtra(Intent.EXTRA_SUBJECT, "Secret Watermarked Audio File")
                        putExtra(Intent.EXTRA_TEXT, "Here is the encrypted watermarked audio file. Open it with Audio Watermark app to decode!")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(shareIntent, "Share Watermarked Audio (20 km)"))
                }
            } catch (e: Exception) {
                runOnUiThread {
                    setSendStatus("⚠ Failed to export audio: ${e.message}", StatusState.ERROR, "EXPORT FAILED")
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
        if (hasMic) {
            startListening()
        } else {
            micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
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
                    setReceiveStatus(
                        "🎙 Listening for sound (%s)…\n⏱ %d seconds remaining\n(Sender: press Transmit now!)".format(mode.displayName, remaining),
                        StatusState.IN_PROGRESS,
                        "LISTENING (${remaining}s)"
                    )
                }
            }
        )
        setReceiveStatus(
            "🎙 Listening for %s signal (%d s window)…\n(Sender: press Transmit now!)".format(mode.displayName, listenSec),
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
        setReceiveStatus("Select a watermarked WAV audio file to decode…", StatusState.IN_PROGRESS, "SELECTING FILE")
        filePickerLauncher.launch("audio/*")
    }

    private fun decodeSelectedAudioFile(uri: Uri) {
        setBothButtonsEnabled(false)
        binding.layoutDecodedResult.visibility = View.GONE
        setReceiveStatus("Loading audio file and decoding watermark…", StatusState.IN_PROGRESS, "DECODING FILE")

        Thread {
            try {
                val inputStream = contentResolver.openInputStream(uri)
                    ?: throw IllegalArgumentException("Cannot open audio file stream.")
                val samples = WavUtils.loadWavFromStreamAsDoubles(inputStream)

                runOnUiThread {
                    setReceiveStatus(
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
                    setReceiveStatus(
                        "❌ Failed to read audio file: ${e.message}\n\nMake sure the file is a 16-bit 44.1 kHz PCM WAV file.",
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
                binding.txtHomeRecentActivity.text = "Last recovered message: '${result.message}'"

                val snrQuality = when {
                    result.preamblePeakEnergy > 10.0 -> "🟢 Excellent signal"
                    result.preamblePeakEnergy > 4.0  -> "🟢 Good signal"
                    else                             -> "🟡 Weak / Borderline signal"
                }

                setReceiveStatus(
                    "✅ Message recovered successfully!\n\n" +
                    "Signal Quality: $snrQuality  (Energy: ${"%.1f".format(result.preamblePeakEnergy)})\n" +
                    "Profile:        ${result.mode.displayName}\n" +
                    "Carrier:        Ultrasonic (17–20 kHz)\n" +
                    "Security:       AES-128-CTR verified",
                    StatusState.SUCCESS,
                    "SUCCESS"
                )

                // Populate technical engineering details
                binding.txtEngineeringDetails.text =
                    "• Mode: ${result.mode.displayName}\n" +
                    "• Peak Preamble Energy: ${"%.2f".format(result.preamblePeakEnergy)} (Threshold: ${result.mode.detectionThreshold})\n" +
                    "• Preamble Lock Sample: #${result.preambleEndSample}\n" +
                    "• Normalization: PCM 32768.0\n" +
                    "• Key Derived: SHA-256 (first 16 bytes)"
            }

            is Decoder.DecodeResult.NoSignal -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setReceiveStatus(
                    "❌ No ultrasonic signal detected.\n\n" +
                    "Energy: ${"%.1f".format(result.maxPreambleEnergy)} (Threshold: ${result.threshold})\n\n" +
                    "How to fix:\n" +
                    "  1. Increase the sender phone's speaker volume.\n" +
                    "  2. Bring the phones closer together (10–50 cm).\n" +
                    "  3. Make sure both phones use the same Transmission Profile.",
                    StatusState.NO_SIGNAL,
                    "NO SIGNAL"
                )
            }

            is Decoder.DecodeResult.NoPreambleLock -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setReceiveStatus(
                    "❌ Signal detected, but could not lock onto message.\n\n" +
                    "Peak Energy: ${"%.1f".format(result.preamblePeakEnergy)} (Threshold: ${result.threshold})\n\n" +
                    "Check speaker volume, reduce background room noise, and verify both phones use the same profile.",
                    StatusState.NO_PREAMBLE_LOCK,
                    "LOCK FAILED"
                )
            }

            is Decoder.DecodeResult.DecryptFailed -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setReceiveStatus(
                    "❌ Unable to Decode\n\n" +
                    "Secret key mismatch or corrupted payload.\n" +
                    "The audio was detected, but the message could not be recovered with this secret key.\n\n" +
                    "Check: Verify that both sender and receiver are using the EXACT same Secret Key.",
                    StatusState.DECRYPT_FAILED,
                    "KEY MISMATCH"
                )
            }

            is Decoder.DecodeResult.GarbageOutput -> {
                binding.layoutDecodedResult.visibility = View.GONE
                setReceiveStatus(
                    "❌ Unable to Decode: Secret Key Mismatch!\n\n" +
                    "The audio was received, but decrypting with this secret key produced unreadable data.\n\n" +
                    "How to fix:\n" +
                    "  • Verify both phones have the EXACT same Secret Key entered.\n" +
                    "  • If keys match, acoustic room noise may have corrupted the sound.",
                    StatusState.GARBAGE_OUTPUT,
                    "WRONG KEY"
                )
            }
        }
    }

    // ── Status Styling Helpers ─────────────────────────────────────────

    private fun setSendStatus(text: String, state: StatusState = StatusState.IDLE, badge: String? = null) {
        val style = getStyleConfig(state)
        binding.cardSendStatus.setCardBackgroundColor(ContextCompat.getColor(this, style.bgColorRes))
        binding.cardSendStatus.strokeColor = ContextCompat.getColor(this, style.strokeColorRes)
        binding.imgSendStatusIcon.setImageResource(style.iconRes)
        binding.imgSendStatusIcon.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(this, style.iconTintRes))
        binding.txtSendStatusHeader.setTextColor(ContextCompat.getColor(this, style.titleColorRes))
        binding.txtSendStatus.setTextColor(ContextCompat.getColor(this, style.textColorRes))
        binding.txtSendStatus.text = text

        if (badge != null) {
            binding.txtSendStatusBadge.text = badge
            binding.txtSendStatusBadge.setBackgroundResource(style.badgeBgRes)
            binding.txtSendStatusBadge.setTextColor(ContextCompat.getColor(this, style.badgeTextRes))
        }
        binding.progressSend.visibility = if (style.showProgress) View.VISIBLE else View.GONE
    }

    private fun setReceiveStatus(text: String, state: StatusState = StatusState.IDLE, badge: String? = null) {
        val style = getStyleConfig(state)
        binding.cardReceiveStatus.setCardBackgroundColor(ContextCompat.getColor(this, style.bgColorRes))
        binding.cardReceiveStatus.strokeColor = ContextCompat.getColor(this, style.strokeColorRes)
        binding.imgReceiveStatusIcon.setImageResource(style.iconRes)
        binding.imgReceiveStatusIcon.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(this, style.iconTintRes))
        binding.txtReceiveStatusHeader.setTextColor(ContextCompat.getColor(this, style.titleColorRes))
        binding.txtReceiveStatus.setTextColor(ContextCompat.getColor(this, style.textColorRes))
        binding.txtReceiveStatus.text = text

        if (badge != null) {
            binding.txtReceiveStatusBadge.text = badge
            binding.txtReceiveStatusBadge.setBackgroundResource(style.badgeBgRes)
            binding.txtReceiveStatusBadge.setTextColor(ContextCompat.getColor(this, style.badgeTextRes))
        }
        binding.progressReceive.visibility = if (style.showProgress) View.VISIBLE else View.GONE
    }

    private fun getStyleConfig(state: StatusState): StyleConfig {
        return when (state) {
            StatusState.IDLE -> StyleConfig(
                R.color.status_idle_bg, R.color.status_idle_stroke, R.drawable.bg_badge_idle,
                R.color.status_idle_badge_text, R.color.status_idle_text, R.color.status_idle_title,
                R.color.status_idle_icon, R.drawable.ic_info, false
            )
            StatusState.IN_PROGRESS -> StyleConfig(
                R.color.status_progress_bg, R.color.status_progress_stroke, R.drawable.bg_badge_progress,
                R.color.status_progress_badge_text, R.color.status_progress_text, R.color.status_progress_title,
                R.color.status_progress_icon, R.drawable.ic_waveform, true
            )
            StatusState.SUCCESS -> StyleConfig(
                R.color.status_success_bg, R.color.status_success_stroke, R.drawable.bg_badge_success,
                R.color.status_success_badge_text, R.color.status_success_text, R.color.status_success_title,
                R.color.status_success_icon, R.drawable.ic_check_circle, false
            )
            StatusState.NO_SIGNAL -> StyleConfig(
                R.color.status_nosignal_bg, R.color.status_nosignal_stroke, R.drawable.bg_badge_nosignal,
                R.color.status_nosignal_badge_text, R.color.status_nosignal_text, R.color.status_nosignal_title,
                R.color.status_nosignal_icon, R.drawable.ic_signal_off, false
            )
            StatusState.NO_PREAMBLE_LOCK -> StyleConfig(
                R.color.status_preamble_bg, R.color.status_preamble_stroke, R.drawable.bg_badge_preamble,
                R.color.status_preamble_badge_text, R.color.status_preamble_text, R.color.status_preamble_title,
                R.color.status_preamble_icon, R.drawable.ic_warning, false
            )
            StatusState.DECRYPT_FAILED -> StyleConfig(
                R.color.status_decrypt_bg, R.color.status_decrypt_stroke, R.drawable.bg_badge_decrypt,
                R.color.status_decrypt_badge_text, R.color.status_decrypt_text, R.color.status_decrypt_title,
                R.color.status_decrypt_icon, R.drawable.ic_key_off, false
            )
            StatusState.GARBAGE_OUTPUT -> StyleConfig(
                R.color.status_garbage_bg, R.color.status_garbage_stroke, R.drawable.bg_badge_garbage,
                R.color.status_garbage_badge_text, R.color.status_garbage_text, R.color.status_garbage_title,
                R.color.status_garbage_icon, R.drawable.ic_code_off, false
            )
            StatusState.WARNING -> StyleConfig(
                R.color.status_nosignal_bg, R.color.status_nosignal_stroke, R.drawable.bg_badge_nosignal,
                R.color.status_nosignal_badge_text, R.color.status_nosignal_text, R.color.status_nosignal_title,
                R.color.status_nosignal_icon, R.drawable.ic_warning, false
            )
            StatusState.ERROR -> StyleConfig(
                R.color.status_error_bg, R.color.status_error_stroke, R.drawable.bg_badge_error,
                R.color.status_error_badge_text, R.color.status_error_text, R.color.status_error_title,
                R.color.status_error_icon, R.drawable.ic_error, false
            )
        }
    }

    private data class StyleConfig(
        val bgColorRes: Int,
        val strokeColorRes: Int,
        val badgeBgRes: Int,
        val badgeTextRes: Int,
        val textColorRes: Int,
        val titleColorRes: Int,
        val iconTintRes: Int,
        val iconRes: Int,
        val showProgress: Boolean
    )

    private fun setBothButtonsEnabled(enabled: Boolean) {
        binding.btnSend.isEnabled = enabled
        binding.btnExportAudio.isEnabled = enabled
        binding.btnListen.isEnabled = enabled
        binding.btnPickFile.isEnabled = enabled
    }
}
