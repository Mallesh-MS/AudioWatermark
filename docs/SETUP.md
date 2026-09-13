# Audio Watermark Demo — Setup & Developer Guide

---

## Prerequisites

| Tool | Version | Download |
|------|---------|----------|
| Android Studio | Hedgehog (2023.1.1) or newer | https://developer.android.com/studio |
| JDK | 17 | Bundled with Android Studio |
| Android SDK | API 34 | Via Android Studio SDK Manager |
| ffmpeg | Any recent | https://ffmpeg.org/download.html |
| Git | 2.x | https://git-scm.com |

---

## 1. Clone the Repository

```bash
git clone https://github.com/Mallesh-MS/AudioWatermark.git
cd AudioWatermark
```

---

## 2. Prepare the Host Song

The app requires a host WAV file in a specific format. **This file is NOT included in the repository** (too large for git).

### Convert with ffmpeg
```bash
ffmpeg -i your_song.mp3 -ar 44100 -ac 1 -sample_fmt s16 host_song.wav
```

Required format:
- Sample rate: **44,100 Hz**
- Channels: **Mono (1 channel)**
- Bit depth: **16-bit PCM**
- Format: **WAV (RIFF)**
- Minimum duration: **~30 seconds** (to accommodate a 30-char message)

### Online alternative
Use an online audio converter with these settings:
- Output format: WAV
- Sample rate: 44100 Hz
- Channels: Mono
- Bit depth: 16 bit

### Place the file
```
app/src/main/res/raw/host_song.wav
```
Then delete `app/src/main/res/raw/PUT_HOST_SONG_HERE.txt` (if present).

---

## 3. Build & Install

### Option A: Android Studio
1. Open Android Studio → File → Open → select the `AudioWatermarkProject/` folder
2. Wait for Gradle sync (downloads ~200 MB on first run)
3. Connect an Android phone (USB debugging enabled) OR start an emulator
4. Click **Run** (green triangle) or press `Shift+F10`

### Option B: Command Line
```bash
./gradlew installDebug
```
Or build a release APK:
```bash
./gradlew assembleRelease
```

---

## 4. Running the Demo

### Same-Device Test (sanity check)
1. Install on one phone
2. Tap **Encrypt, Embed & Play**
3. Immediately tap **Listen & Decode** on the SAME phone (speaker next to its own mic)
4. Wait for the 20-second recording to complete

### Two-Device Test
1. Install on both phones (same APK or both built from the same source)
2. **Person A:** Types a message, taps "Encrypt, Embed & Play"
3. **Person B:** Taps "Listen & Decode" (request starts 20s countdown)
4. Hold phones 10–30 cm apart, speakers facing each other
5. When decode finishes, the recovered message appears in the status card

### Tuning Tips
- If **NO SIGNAL**: increase `Config.WATERMARK_AMPLITUDE` (try 0.12), move phones closer
- If **PREAMBLE LOCK FAILED**: reduce speaker volume slightly, ensure listening starts before playback
- If **DECRYPT FAILED**: check Logcat Goertzel energy tables, reduce room echo

---

## 5. Project File Structure

```
AudioWatermarkProject/
├── app/
│   ├── build.gradle.kts                    # App-level build config
│   ├── proguard-rules.pro
│   └── src/main/
│       ├── AndroidManifest.xml             # RECORD_AUDIO permission, activity declaration
│       ├── java/com/spproject/audiowatermark/
│       │   ├── Config.kt                   # Shared parameters
│       │   ├── AesCrypto.kt                # AES-128 CTR encryption/decryption
│       │   ├── Goertzel.kt                 # Single-frequency energy detector
│       │   ├── ToneGenerator.kt            # Bytes -> FSK audio tones
│       │   ├── Embedder.kt                 # Mix watermark into host song
│       │   ├── WavUtils.kt                 # WAV file I/O
│       │   ├── AudioTransmitter.kt         # Play audio via AudioTrack
│       │   ├── AudioReceiver.kt            # Capture audio via AudioRecord
│       │   ├── Decoder.kt                  # FSK audio -> bits -> plaintext
│       │   ├── TransmissionSizing.kt       # Duration calculation utility
│       │   └── MainActivity.kt             # UI + wiring
│       └── res/
│           ├── layout/
│           │   └── activity_main.xml       # Single screen layout (NestedScrollView)
│           ├── drawable/
│           │   ├── ic_*.xml                # 12 vector icons (Material icons)
│           │   └── bg_badge_*.xml          # 11 badge background drawables
│           ├── values/
│           │   ├── colors.xml              # Full color palette (105 colors)
│           │   ├── strings.xml             # App name string
│           │   └── themes.xml              # Material3 theme
│           └── raw/
│               └── host_song.wav           # [YOU MUST ADD THIS]
├── build.gradle.kts                        # Root build config
├── settings.gradle.kts                     # Module includes
├── gradle.properties                       # Kotlin/JVM flags
├── gradlew.bat                             # Windows Gradle wrapper
├── README.md                               # Quick start guide
└── docs/
    ├── UI_UX_DESIGN.md                     # UI/UX design specification
    ├── ARCHITECTURE.md                     # Technical architecture
    ├── SETUP.md                            # This file
    ├── CONTRIBUTING.md                     # Contribution guidelines
    └── mockups/
        ├── screen_idle.jpg                 # Idle state mockup
        ├── screen_transmitting.jpg         # Transmitting state mockup
        ├── screen_success.jpg              # Success state mockup
        ├── screen_error_states.jpg         # Error states mockup
        └── system_architecture.jpg         # System architecture diagram
```

---

## 6. Key Configuration Parameters

Edit `Config.kt` to tune the system:

```kotlin
object Config {
    const val SAMPLE_RATE = 44100            // Do NOT change — must match host WAV
    const val PREAMBLE_FREQ = 17000.0        // Hz — preamble sync tone
    const val FREQ_BIT_0 = 18000.0           // Hz — bit 0 tone
    const val FREQ_BIT_1 = 19500.0           // Hz — bit 1 tone
    const val PREAMBLE_DURATION_MS = 300     // ms — longer = more reliable lock
    const val SYMBOL_DURATION_MS = 100       // ms — shorter = faster but less reliable
    const val WATERMARK_AMPLITUDE = 0.08     // 0.05–0.15 range; tune for your room
    const val SHARED_PASSPHRASE = "signal-processing-project-2026"  // MUST match both phones
}
```

Also see `Decoder.PREAMBLE_DETECT_THRESHOLD = 300.0` — tune upward to reduce false positives in noisy environments.

---

## 7. Debugging with Logcat

Filter by these tags in Android Studio Logcat:

| Tag | Logs |
|-----|------|
| `AudioTransmitter` | Playback start/stop, sample count |
| `AudioReceiver` | Recording start/stop, sample count |
| `Decoder` | Preamble lock position, energy tables for each bit |
| `Embedder` | Clipping warnings, peak mix level |

Enable verbose Goertzel energy table logging by ensuring `Log.isLoggable("Decoder", Log.DEBUG)` returns true (Debug builds do by default).

---

## 8. Common Issues & Fixes

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| App crashes immediately | Missing host_song.wav | Place WAV in `res/raw/`, rebuild |
| "Host song too short" error | Song < required duration | Use longer song or shorten message |
| NO SIGNAL consistently | Amplitude too low, phones too far | Increase `WATERMARK_AMPLITUDE`, move closer |
| PREAMBLE LOCK FAILED | Signal clipped or distorted | Reduce speaker volume, check `Embedder` clipping log |
| DECRYPT FAILED always | Passphrase mismatch or bit errors | Verify Config.SHARED_PASSPHRASE identical on both phones |
| GARBAGE OUTPUT | Multiple bit errors | Move phones closer, reduce room echo |
| App stops responding | Background thread crash | Check Logcat for stack traces |
