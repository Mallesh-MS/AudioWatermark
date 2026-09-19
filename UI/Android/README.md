# Android Acoustic Watermarking & Steganography Application

**Package:** `com.spproject.audiowatermark`  
**Target SDK:** Android 14 (API 34)  
**Minimum SDK:** Android 7.0 (API 24)  
**Language:** Kotlin 1.9.0 / Java 17  
**Architecture:** Material Design 3 (Day/Night) with CoordinatorLayout, BottomNavigationView, and Native DSP

---

## Overview

The `UI/Android` application is the production mobile client for the **AudioWatermark** project. It combines ultrasonic acoustic modem capabilities with digital audio file steganography.

### Primary Screen Structure:
- **`tabHome`**: Guided launchpad with large action cards for *Send Message* and *Receive Message*, recent activity history, and a 3-step primer.
- **`tabSend`**: Guided 4-step wizard:
  - Step 1: Plaintext message input (`editMessage`) with 4 presets (`HELLO`, `PASS_2026`, `PAY_100`, `SHARE_20KM`).
  - Step 2: Audio Method toggle (`switchCarrierMode`): Pure Ultrasonic (17–20 kHz) vs Embed in Music (`host_song.wav`).
  - Step 3: Reliability profile toggle (`btnModeStandard` vs `btnModeLongRange`).
  - Step 4: Secret Key passphrase input (`editSecretKey`) with visibility toggle (👁) and preset chips (`Default Key`, `Custom Pass`, `Test Wrong Key`).
  - Actions: **Send Message over Speaker** (`btnSend`) & **Share Audio File (20 km)** (`btnExportAudio`).
- **`tabReceive`**: Dedicated reception dashboard:
  - Visual proximity diagram (`Speaker 🔊 ━━━━► 🎤 Mic`).
  - **Listen Nearby via Mic** (`btnListen`) with 20-second countdown.
  - **Open Audio File** (`btnPickFile`) for file-based steganography decoding.
  - Decoded message container with **Copy Text** button (`btnCopyMessage`) and plain-English signal quality indicators.
  - Expandable Level 3 Engineering details panel.
- **`tabSettings`**: Accessibility controls (Reduce Motion, High Contrast), hardware audio diagnostics, and plain-English FAQ.

---

## Core Kotlin Source Files

| File | Role |
| :--- | :--- |
| **`MainActivity.kt`** | Drives bottom navigation, guided workflows, status rendering, and bridges UI to DSP. |
| **`AudioReceiver.kt`** | Records mono 16-bit 44.1 kHz PCM audio using `MediaRecorder.AudioSource.UNPROCESSED` and normalizes via `/ 32768.0`. |
| **`AudioTransmitter.kt`**| Streams generated audio doubles to the phone speaker via `AudioTrack` in streaming mode. |
| **`ToneGenerator.kt`** | Synthesizes continuous-phase FSK (CPFSK) waveforms to eliminate high-frequency clicks. |
| **`Decoder.kt`** | Performs two-stage preamble acquisition (coarse search + 5ms fine alignment), bit slicing via Goertzel filter, and AES decryption. |
| **`Goertzel.kt`** | Single-frequency DFT magnitude estimator used for 17 kHz, 18 kHz, and 19.5 kHz energy measurements. |
| **`AesCrypto.kt`** | AES-128 in CTR mode with SHA-256 derived keys from user passphrases. |
| **`Config.kt`** | Holds frequency definitions, sampling rate (`44,100 Hz`), and `RangeMode` definitions (`STANDARD` vs `LONG_RANGE`). |
| **`TransmissionSizing.kt`**| Calculates estimated playback duration based on payload size and active profile. |
| **`WavUtils.kt`** | Reads and writes standard 16-bit mono 44.1 kHz PCM WAV files. |
| **`Embedder.kt`** | Injects ultrasonic watermark samples beneath host music audio. |

---

## Build & Run

```powershell
# Build debug APK
.\gradlew.bat assembleDebug

# Install on connected device
adb install -r app\build\outputs\apk\debug\app-debug.apk

# Launch app
adb shell am start -n com.spproject.audiowatermark/.MainActivity
```
