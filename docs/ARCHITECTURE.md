# Audio Watermark Demo — Architecture & Technical Design

> Signal Processing Project 2026 | Android | Kotlin

---

## 1. System Overview

The Audio Watermark Demo implements **acoustic steganography**: a secret text message is AES-encrypted, converted to inaudible ultrasonic tones (17–19.5 kHz), and superimposed on a host music file. The watermarked audio is transmitted acoustically via speaker; a second phone captures it via microphone and recovers the original message.

```
┌──────────────────────────┐    speaker  mic   ┌──────────────────────────┐
│       Phone A            │  ══════════════>  │       Phone B            │
│                          │  Acoustic Channel │                          │
│  1. Secret Message       │                   │  1. AudioReceiver        │
│  2. AES-128 CTR encrypt  │                   │  2. Goertzel decode      │
│  3. FSK tone generation  │                   │  3. AES-128 CTR decrypt  │
│  4. Mix into host song   │                   │  4. Recovered message    │
│  5. Play via AudioTrack  │                   │                          │
└──────────────────────────┘                   └──────────────────────────┘
```

---

## 2. Module Architecture

### 2.1 Package Structure

```
com.spproject.audiowatermark/
├── Config.kt              — Shared constants (frequencies, timing, passphrase)
├── AesCrypto.kt           — AES-128 CTR encryption/decryption
├── ToneGenerator.kt       — Bytes → FSK audio samples
├── Embedder.kt            — Mix watermark into host song
├── WavUtils.kt            — WAV file I/O (read/write 44100Hz mono 16-bit PCM)
├── AudioTransmitter.kt    — Play audio via AudioTrack (streaming mode)
├── AudioReceiver.kt       — Record 20s via AudioRecord
├── Decoder.kt             — FSK audio → bits → decrypted message
├── TransmissionSizing.kt  — Calculate required audio duration
└── MainActivity.kt        — Single-screen UI, wires all modules together
```

### 2.2 Dependency Graph

```
MainActivity
    ├── AudioTransmitter
    │       └── [AudioTrack - Android SDK]
    ├── AudioReceiver
    │       ├── [AudioRecord - Android SDK]
    │       └── Decoder
    │               ├── Goertzel
    │               ├── ToneGenerator (bitsToBytes helper)
    │               └── AesCrypto
    └── (on send click):
            ├── AesCrypto (encrypt)
            ├── ToneGenerator (buildWatermarkSequence)
            ├── WavUtils (loadWavAsDoubles)
            ├── TransmissionSizing (duration check)
            └── Embedder (mix)
```

---

## 3. Signal Processing Pipeline

### 3.1 Transmission Wire Format

```
┌──────────────┬──────────────────────────┬──────────────────────────────┐
│  Preamble    │  Length Header (8 bits)   │  Payload (N×8 bits)          │
│  300 ms      │  8 × 100 ms = 800 ms     │  cipherLen × 800 ms          │
│  17,000 Hz   │  18k / 19.5k Hz per bit  │  18k / 19.5k Hz per bit     │
└──────────────┴──────────────────────────┴──────────────────────────────┘
```

**Encoding scheme:** Binary FSK (Frequency Shift Keying)
- Bit 0 → 18,000 Hz sine tone for 100 ms
- Bit 1 → 19,500 Hz sine tone for 100 ms
- Preamble → 17,000 Hz sine tone for 300 ms (3× symbol width)

**Byte order:** MSB-first (Big Endian) within each byte

### 3.2 Goertzel Frequency Math

```
Sample rate (Fs)   = 44,100 Hz
Symbol duration    = 100 ms → N = 4,410 samples
Frequency resolution (Δf) = Fs / N = 44100 / 4410 = 10.0 Hz exactly

Tone frequencies and bin indices:
  PREAMBLE  17,000 Hz → k = 4410 × 17000 / 44100 = 1700.0 (exact bin)
  BIT_0     18,000 Hz → k = 4410 × 18000 / 44100 = 1800.0 (exact bin)
  BIT_1     19,500 Hz → k = 4410 × 19500 / 44100 = 1950.0 (exact bin)

Bin separation:
  BIT_1 − BIT_0    = 150 bins = 1,500 Hz  >> 2 bins minimum
  BIT_0 − PREAMBLE = 100 bins = 1,000 Hz  >> 2 bins minimum
```

All three frequencies land exactly on DFT bin centres, eliminating inter-bin spectral leakage.

### 3.3 Embedding Level

```
WATERMARK_AMPLITUDE = 0.08 (8% of full scale = -21.9 dBFS)

Worst-case mix:  0.92 (host peak) + 0.08 (watermark) = 1.00 FS (no clipping)
After speaker→air→mic (-20 to -30 dB attenuation):
  Received level ≈ -42 to -52 dBFS
  Mic noise floor ≈ -65 dBFS on Android
  SNR at receiver ≈ 13 to 23 dB  (good)
```

---

## 4. Module Details

### 4.1 Config.kt
Central constants shared by both transmitter and receiver. **Both phones must use identical values.**

| Constant | Value | Description |
|----------|-------|-------------|
| `SAMPLE_RATE` | 44100 | Hz — must match host WAV |
| `PREAMBLE_FREQ` | 17000.0 | Hz — receiver sync tone |
| `PREAMBLE_DURATION_MS` | 300 | ms — 3× symbol width |
| `FREQ_BIT_0` | 18000.0 | Hz — binary 0 data tone |
| `FREQ_BIT_1` | 19500.0 | Hz — binary 1 data tone |
| `SYMBOL_DURATION_MS` | 100 | ms — 10 bits/sec raw throughput |
| `WATERMARK_AMPLITUDE` | 0.08 | Fraction of full scale |
| `SHARED_PASSPHRASE` | `"signal-processing-project-2026"` | AES key derivation |

### 4.2 AesCrypto.kt
- **Algorithm:** AES-128 in CTR mode (`AES/CTR/NoPadding`)
- **Key derivation:** SHA-256(passphrase) → first 16 bytes
- **IV:** Fixed all-zero 16-byte IV
- **Ciphertext length:** Equals plaintext length exactly (CTR property)
- **Known limitation:** Fixed IV reuse is a cryptographic weakness; acceptable for course demo

### 4.3 ToneGenerator.kt
- `generateTone(freq, durationMs)` → sinusoidal DoubleArray at WATERMARK_AMPLITUDE
- `bytesToBits(bytes)` → MSB-first bit list (shared with Decoder)
- `bitsToBytes(bits)` → reconstructed byte array (shared with Decoder)
- `buildWatermarkSequence(cipherBytes)` → complete preamble + header + payload audio

### 4.4 Embedder.kt
- Simple additive mixing: `mixed[i] = host[i] + watermark[i]`
- Clamping to [-1.0, 1.0] with clipping count logged via `Log.w`
- Host song treated as read-only; returns new array

### 4.5 WavUtils.kt
- Reads RIFF/WAVE chunks iteratively (handles non-standard chunk ordering)
- Supports mono and stereo input (stereo downmixed to mono by averaging L+R)
- Validates: PCM format, 16-bit depth, correct sample rate
- `writeWav()` saves watermarked audio to internal storage for Audacity inspection

### 4.6 AudioTransmitter.kt
- Uses `AudioTrack` in **STREAM mode** (avoids STATIC mode buffer size cap)
- Writes 4096-sample chunks on a background daemon thread
- Invokes `onDone` callback on main thread via `Handler(Looper.getMainLooper())`
- `release()` is idempotent — safe to call from `onDestroy`

### 4.7 AudioReceiver.kt
- Uses `AudioRecord` with `MediaRecorder.AudioSource.MIC`
- Captures a fixed 20-second window into a pre-allocated `ShortArray`
- Converts to normalized DoubleArray (`/ 32768.0`) before passing to Decoder
- Optional `onProgressSec` callback fires each second for countdown display

### 4.8 Decoder.kt
Decode pipeline:

1. **Preamble scan:** sliding window of PREAMBLE_LEN (13,230 samples), step = SYMBOL_LEN/2
2. **Lock detection:** window with max Goertzel energy @ 17 kHz above PREAMBLE_THRESHOLD (300.0)
3. **Length header:** decode 8 bits starting at preamble end → payload byte count (1–255)
4. **Payload decode:** N×8 bits, each bit = argmax(mag@18k, mag@19.5k)
5. **AES decrypt:** recover plaintext from cipher bytes
6. **Sanity check:** verify ≥75% printable ASCII (guard against silent bit errors)

**DecodeResult sealed class:**
- `Success(message, preamblePeakEnergy, preambleEndSample)`
- `NoSignal(maxPreambleEnergy, threshold)`
- `NoPreambleLock(preamblePeakEnergy, threshold)`
- `DecryptFailed(preambleEndSample, cipherLength, reason)`
- `GarbageOutput(preambleEndSample, rawDecrypted)`

### 4.9 TransmissionSizing.kt
- Computes total samples = preamble + (8 + cipherLen×8) × symbolLen
- Converts to seconds for UI display and host-song length validation

### 4.10 MainActivity.kt
- Single `AppCompatActivity` with ViewBinding
- Person A flow: background thread for encrypt/embed, main thread for UI updates
- Person B flow: `micPermissionLauncher` → `startListening()` → `handleDecodeResult()`
- `setStatus(text, state, badge)` drives all visual state transitions via `StyleConfig` data class
- Both buttons disabled during any operation; re-enabled on completion or error

---

## 5. Threading Model

```
Main Thread
    └── UI updates (setStatus, setBothButtonsEnabled)

MainActivity-send (daemon)
    └── AES encrypt → build tones → load WAV → embed → AudioTransmitter.play()

AudioTransmitter-write (daemon)
    └── AudioTrack.write() loop in 4096-sample chunks

AudioReceiver-record (daemon)
    └── AudioRecord.read() loop → Decoder.decode() → main thread callback
```

---

## 6. Permissions

| Permission | Reason | When requested |
|-----------|--------|---------------|
| `RECORD_AUDIO` | Microphone capture for Person B | Runtime, on first "Listen & Decode" tap |

No other permissions required. No network access, no storage read/write (host song is bundled in `res/raw/`).

---

## 7. Build Configuration

| Property | Value |
|----------|-------|
| `compileSdk` | 34 (Android 14) |
| `minSdk` | 24 (Android 7.0 Nougat) |
| `targetSdk` | 34 |
| Language | Kotlin |
| JVM target | Java 17 |
| Build system | Gradle 8.7 with Kotlin DSL |
| ViewBinding | Enabled |

### Dependencies
| Library | Version | Purpose |
|---------|---------|---------|
| `androidx.core:core-ktx` | 1.13.1 | Kotlin extensions |
| `androidx.appcompat:appcompat` | 1.7.0 | AppCompatActivity |
| `com.google.android.material:material` | 1.12.0 | Material Design 3 |
| `androidx.activity:activity-ktx` | 1.9.0 | Permission launcher |
| `androidx.constraintlayout:constraintlayout` | 2.1.4 | Layout |

---

## 8. Known Limitations

| # | Limitation | Impact | Mitigation |
|---|-----------|--------|------------|
| 1 | Fixed AES IV (CTR mode) | Keystream reuse vulnerability | Use fresh random nonce per message in production |
| 2 | Hardcoded passphrase | No forward secrecy | Use proper key exchange (ECDH) in production |
| 3 | Fixed 20s receive window | Must start listening before sender | Implement streaming preamble detection |
| 4 | No error correction | 1 bit error corrupts entire message | Add Reed-Solomon or parity coding |
| 5 | 1-byte length header | Max 255 bytes payload (~30 chars) | Extend to 2-byte header for longer messages |
| 6 | No background noise estimation | Threshold is static | Implement adaptive threshold based on noise floor |

---

## 9. Performance Characteristics

| Operation | Typical Duration |
|-----------|----------------|
| AES encrypt (30 chars) | < 1 ms |
| Build watermark sequence | < 50 ms |
| Load host WAV (53s song) | ~500 ms |
| Embed watermark | ~200 ms |
| 20s recording | 20 s |
| Preamble scan + decode | < 500 ms |
| AES decrypt | < 1 ms |
| **Total Person A flow** | **~22 s (dominated by playback)** |
| **Total Person B flow** | **~21 s (dominated by recording)** |
