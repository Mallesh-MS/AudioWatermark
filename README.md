# AudioWatermark: Acoustic Steganography & Secure Audio Modem

[![Android](https://img.shields.io/badge/Platform-Android%20%28Kotlin%29-3DDC84?logo=android&logoColor=white)](UI/Android/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Security](https://img.shields.io/badge/Crypto-AES--128--CTR%20%2B%20SHA--256-blueviolet)](UI/Android/app/src/main/java/com/spproject/audiowatermark/AesCrypto.kt)
[![DSP](https://img.shields.io/badge/DSP-CPFSK%2017--20%20kHz-orange)](UI/Android/app/src/main/java/com/spproject/audiowatermark/ToneGenerator.kt)
[![Design](https://img.shields.io/badge/UI%2FUX-Material%203%20%28Day%2FNight%29-indigo)](UI/Android/app/src/main/res/layout/activity_main.xml)

**AudioWatermark** is a production-quality acoustic audio watermarking and digital steganography application. It enables two devices to exchange confidential encrypted text messages through **near-ultrasonic sound waves (17–20 kHz)** over physical air gaps, or across **worldwide geographical distances (20 km / global)** through lossless audio file steganography.

---

## 📱 Application Overview & Architecture

```
  PERSON A (Transmitter)                                 PERSON B (Receiver)
  ┌────────────────────────┐                             ┌────────────────────────┐
  │  Plaintext Message     │                             │  Microphone / Audio WAV│
  │  "HELLO"               │                             │  44.1 kHz Mono Stream  │
  └───────────┬────────────┘                             └───────────┬────────────┘
              │                                                      │
  ┌───────────▼────────────┐                                         ▼
  │  User Secret Key       │                             ┌────────────────────────┐
  │  SHA-256 Derivation    │                             │  Goertzel Energy Filter│
  │  AES-128-CTR Encrypt   │                             │  17 kHz Preamble Lock  │
  └───────────┬────────────┘                             └───────────┬────────────┘
              │                                                      │
  ┌───────────▼────────────┐                                         ▼
  │  Length Header + Data  │                             ┌────────────────────────┐
  │  CPFSK Tone Generator  │                             │  Dual-Bin Bit Slicing  │
  │  17k / 18k / 19.5k Hz  │                             │  18 kHz vs 19.5 kHz    │
  └───────────┬────────────┘                             └───────────┬────────────┘
              │                                                      │
  ┌───────────▼────────────┐                                         ▼
  │  Acoustic Speaker OR   │                             ┌────────────────────────┐
  │  Lossless WAV Export   │                             │  Reassemble Ciphertext │
  │  (Air-Gap / 20 km Msg) ├────────────────────────────►│  Extract Length Header │
  └────────────────────────┘        Acoustic Air Gap     └───────────┬────────────┘
                                   OR Digital File Share             │
                                                                     ▼
                                                         ┌────────────────────────┐
                                                         │  User Secret Key       │
                                                         │  AES-128-CTR Decrypt   │
                                                         └───────────┬────────────┘
                                                                     │
                                                         ┌───────────▼────────────┐
                                                         │  UTF-8 Sanity Check    │
                                                         │  ✓ Success: "HELLO"    │
                                                         │  ✗ Fail: WRONG KEY /   │
                                                         │          CORRUPTED     │
                                                         └────────────────────────┘
```

---

## 🌟 Key Features

### 1. Modern 4-Tab Bottom Navigation Interface
- **🏠 Home**:
  - Friendly header: *"Secure Audio Message — Hide text in sound • Recover securely"*.
  - Dismissable onboarding guide for first-time users.
  - Large touch-friendly cards: **📤 Send a Message** and **📥 Receive a Message**.
  - Real-time recent activity recaps and 3-step visual guide.
- **📤 Send (Guided 4-Step Flow)**:
  - **Step 1 — Enter Message**: Secret message input + character counter (`8 / 30`) + 4 presets with descriptions (`HELLO`, `PASS_2026`, `PAY_100`, `SHARE_20KM`).
  - **Step 2 — Audio Method**: Toggle between **🔊 Pure Ultrasonic Sound** (17–20 kHz) and **🎶 Embed in Music**, with an expandable `ⓘ How does this work?` explanation.
  - **Step 3 — Reliability Mode**: Toggle between **⚡ Standard** (Fast · 10 bps · ~4.2s) and **📡 High Robustness** (More reliable · 5 bps · ~7.8s) with helpful tip: *"💡 Not sure? Use High Robustness in noisy rooms."*
  - **Step 4 — Security & Secret Key**: Password toggle (👁), quick chips (`🔑 Default Key`, `🛡 Custom Pass`, `❌ Test Wrong Key`), and plain-English protection notice.
  - **Primary Actions**: Large 56dp **🔊 SEND MESSAGE OVER SPEAKER** button + **🌍 Share Audio File (20 km / Any Distance)** button.
- **📥 Receive (Dedicated Experience)**:
  - Visual sound transfer guide diagram (`🔊 Speaker ━━━━ 📡 Ultrasonic Sound ━━━━► 🎤 Mic`).
  - **Method 1**: **🎙 Listen Nearby via Mic (20 s)** with live countdown.
  - **Method 2**: **📁 Open Audio File (20 km / Shared File)** for instant WAV decoding.
  - **Success Card**: Prominent green banner, recovered text, **📋 Copy Text** button, and human-friendly signal quality (🟢 Good signal · `SNR: 24.6 dB`).
  - **Failure Handling**: Multi-modal error card (❌ Icon + Text + Color) that explains key mismatches or room noise with retry guidance.
  - **Level 3 Engineering Panel**: Expandable `▼ Advanced technical details` (peak preamble energy, lock sample #, normalization constant, and SHA-256 derivation).
- **⚙ Settings & Help**:
  - **Accessibility**: Reduce Motion and High Contrast switches.
  - **Audio Hardware**: Real-time microphone permission check, sample rate (44.1 kHz 16-bit Mono), and `UNPROCESSED` filter-bypass display.
  - **Plain-English FAQ**: Clear explanations for *"What is audio steganography?"*, *"What is a secret key?"*, and *"Why can't I decode?"*.

---

### 2. Cryptographic Security & Passphrase System
- **Key Derivation:** Applies SHA-256 to user passphrases to derive 128-bit AES keys ($K = \text{SHA-256}(\text{Passphrase})[0\dots 15]$).
- **Stream Cipher:** AES-128 in CTR mode (no block padding overhead).
- **Mismatch Detection:** Decrypting with an incorrect key yields pseudorandom binary entropy. The decoder's UTF-8 sanity checker detects non-readable characters, issuing a clean `WRONG KEY / CORRUPTED PAYLOAD` diagnostic without crashing.

---

### 3. Continuous Phase Frequency Shift Keying (CPFSK)
- **Carrier Frequencies:**
  - `17,000 Hz`: Preamble / Synchronization pilot tone
  - `18,000 Hz`: Binary `0`
  - `19,500 Hz`: Binary `1`
- **Continuous Phase:** Phase transitions are calculated continuously ($\theta[n] = (\theta[n-1] + 2\pi f / f_s) \pmod{2\pi}$), eliminating audible clicking transients and spectral splatter.

---

### 4. Dual Transmission Modes
| Profile | Symbol Duration | Bitrate | Preamble Length | Detection Threshold | Best Suited For |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **⚡ Standard** | 100 ms | 10 bps | 200 ms | 5.0 | Fast, nearby transfers (0–1.5 m) in quiet environments (~4.2 s) |
| **📡 High Robustness** | 200 ms | 5 bps | 400 ms | 2.5 | Noisy environments, extended range (2–5 m+), +6 dB processing gain (~7.8 s) |

---

### 5. 20 km / Worldwide Digital Audio Steganography
- Physical sound propagation across 20 km in air is physically impossible due to Stokes' law of sound attenuation.
- **Audio File Steganography:** Encrypts and embeds the watermark into a lossless **16-bit 44.1 kHz PCM WAV file** and triggers the Android system share sheet.
- Users can share the file via **WhatsApp (as Document)**, **Telegram**, **Email**, or **Google Drive** across 20 km or anywhere globally. The receiver opens the file via `Open Audio File` and decodes the message with 100% fidelity.

---

## 🛠 Project Structure

```
AudioWatermark/
├── UI/
│   └── Android/                     # Native Android Application (Source of Truth)
│       ├── app/
│       │   ├── src/main/
│       │   │   ├── java/com/spproject/audiowatermark/
│       │   │   │   ├── MainActivity.kt       # 4-Tab Navigation & UI Controller
│       │   │   │   ├── AudioReceiver.kt      # Mic capture (UNPROCESSED, 32768.0 norm)
│       │   │   │   ├── AudioTransmitter.kt   # AudioTrack speaker playback
│       │   │   │   ├── ToneGenerator.kt      # CPFSK tone synthesis
│       │   │   │   ├── Decoder.kt            # Two-stage Goertzel detector & bit-slicer
│       │   │   │   ├── Goertzel.kt           # Goertzel DFT filter algorithm
│       │   │   │   ├── AesCrypto.kt          # AES-128-CTR + SHA-256 key derivation
│       │   │   │   ├── Config.kt             # Frequencies, thresholds, and modes
│       │   │   │   ├── TransmissionSizing.kt # Dynamic duration calculator
│       │   │   │   ├── WavUtils.kt           # 16-bit PCM WAV parser and writer
│       │   │   │   └── Embedder.kt           # Audio steganography music embedder
│       │   │   ├── res/
│       │   │   │   ├── layout/activity_main.xml # Material 3 4-Tab CoordinatorLayout
│       │   │   │   ├── menu/bottom_nav_menu.xml # Bottom Navigation Menu
│       │   │   │   ├── values/colors.xml        # Light Mode Palette
│       │   │   │   ├── values-night/colors.xml  # Dark Mode Palette
│       │   │   │   └── values/themes.xml        # Theme.Material3.DayNight
│       │   │   └── AndroidManifest.xml          # Permissions & FileProvider
│       │   └── build.gradle.kts
│       └── gradlew.bat
├── Testing/                         # Dart & DSP verification test suites
│   ├── test/                        # Adversarial audit test groups (A, B, C, D)
│   └── AUDIT.md                     # Comprehensive security and DSP audit report
├── PROJECT_DEVELOPMENT_AND_TESTING_REPORT.md  # Detailed engineering report
└── README.md                        # Master project documentation
```

---

## 🚀 Building & Installing

### Prerequisites
- **JDK 17 or JDK 21**
- **Android SDK (API 34 / compileSdk 34, minSdk 24)**
- **ADB (Android Debug Bridge)**

### 1. Build Debug APK
Navigate to `UI/Android` and run:
```powershell
cd UI\Android
.\gradlew.bat assembleDebug
```
The compiled APK will be generated at:
`UI/Android/app/build/outputs/apk/debug/app-debug.apk`

### 2. Deploy to Connected Android Devices
List connected devices via ADB:
```powershell
adb devices
```

Install and launch on connected phones:
```powershell
$adb = "C:\Users\LENOVO\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$apk = "D:\GIT\AudioWatermark\UI\Android\app\build\outputs\apk\debug\app-debug.apk"

# Install on Device 1
& $adb -s <DEVICE_ID_1> install -r $apk
& $adb -s <DEVICE_ID_1> shell am start -n com.spproject.audiowatermark/.MainActivity

# Install on Device 2
& $adb -s <DEVICE_ID_2> install -r $apk
& $adb -s <DEVICE_ID_2> shell am start -n com.spproject.audiowatermark/.MainActivity
```

---

## 🧪 Physical Hardware Test Results

Real-world acoustic over-the-air tests were conducted between two distinct physical smartphone platforms:
- **Phone 1:** OnePlus Nord AC2001 (`7f77334a`) — OxygenOS (Android 12/13)
- **Phone 2:** Samsung Galaxy SM-A576B (`RZGL8267RXW`) — One UI (Android 14/15)

| Test Case | Distance | Carrier Mode | Profile | Secret Key | Result | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TC-01: Tabletop Direct** | 10 cm | Pure Ultrasonic | Standard | Matching | **`✓ DECODE SUCCESS`** | Energy: 18.4 (High SNR) |
| **TC-02: Normal Desk** | 0.8 m | Pure Ultrasonic | Standard | Matching | **`✓ DECODE SUCCESS`** | Energy: 7.9 (Good SNR) |
| **TC-03: Across Room** | 2.5 m | Pure Ultrasonic | Standard | Matching | **`✗ LOCK FAILED`** | Attenuation drops signal below 5.0 |
| **TC-04: Across Room (Robust)** | 2.5 m | Pure Ultrasonic | High Robustness | Matching | **`✓ DECODE SUCCESS`** | 5 bps integration delivers +6 dB gain |
| **TC-05: Music Embed** | 0.5 m | Embed in Music | Standard | Matching | **`✓ DECODE SUCCESS`** | Inaudible watermark under music |
| **TC-06: Wrong Secret Key** | 0.5 m | Pure Ultrasonic | Standard | Mismatched | **`✗ WRONG KEY`** | Decrypts to non-readable bytes; clean failure |
| **TC-07: Digital Steganography**| 20 km | Export WAV | Standard | Matching | **`✓ DECODE SUCCESS`** | 100% bit fidelity across any distance |

---

## 📖 Additional Documentation
- [**Master Engineering & Testing Report (`PROJECT_DEVELOPMENT_AND_TESTING_REPORT.md`)**](PROJECT_DEVELOPMENT_AND_TESTING_REPORT.md): Comprehensive analysis of the normalization bug fix (`32768.0`), hardware filter bypass, Stokes' law attenuation, and git diff audit.
- [**Security & DSP Audit Report (`Testing/AUDIT.md`)**](Testing/AUDIT.md): In-depth adversarial audit covering cryptanalysis, Goertzel bin alignment, and WAV fuzzing.

---

## 📄 License
This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
