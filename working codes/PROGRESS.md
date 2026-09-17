# Progress Log

## [Stage 0] Project Scaffolding Session
- **Completed:**
  - Decided on full system architecture: FSK watermarking, AES-128-CTR encryption, QR-based random key exchange, near-ultrasonic band (17-20 kHz)
  - Validated and rejected several intermediate design ideas (amplitude modulation as carrier, modulating the host song's own content, light-polarization-inspired overlap fix) — see DECISIONS.md for full reasoning on each
  - Built and verified a working Kotlin/Android Studio prototype of the full pipeline, including a real AES-128-CTR worked example (message "HI" → ciphertext `25 AD`, verified via actual Goertzel algorithm run)
  - Compiled full calculations reference (key space, QR capacity, frequency/Goertzel bin alignment, transmission timing, amplitude/dB, detection thresholds)
  - Compiled troubleshooting/fallback strategy document (tiered fixes if hardware doesn't support target frequencies)
  - Decided to pivot from Kotlin/Android Studio to Flutter/Dart to share a single codebase with teammate's Stitch-generated UI
  - Set up Flutter project folder structure and initialized memory files (this session)
- **In Progress:**
  - Porting DSP/crypto logic from Kotlin to Dart (Stage 1)
- **Notes / Discoveries:**
  - Key finding: data rate is governed by Shannon-Hartley (bandwidth × log(1+SNR)), NOT by how high the frequency is — a common misconception worth remembering when planning the future multi-tone/file-transfer upgrade
  - Real acoustic phone-call audio injection is blocked by OS-level security restrictions on both Android and iOS — any "embed in calls" future work must go through a self-built in-app VoIP feature (e.g. WebRTC), not the OS's native call audio
  - Teammate is handling UI independently via Google Stitch; integration point is a clean Dart interface to be finalized at Stage 8

## [Stage 1] Crypto Core (Dart)
- **Completed:**
  - Ported AES-128-CTR encryption/decryption from Kotlin to Dart using the `encrypt` package
  - Implemented `WatermarkCrypto` class with `encrypt`, `decrypt`, `generateKey`, `keyToHex`, `keyFromHex`
  - Fixed 16-byte zero IV per ADR 005
  - Unit tests pass: round-trip across multiple plaintext lengths, hex key conversion round-trip

## [Stage 2] Bit/Tone Mapping (Dart, pure math)
- **Completed:**
  - Implemented `ToneGenerator`: preamble generation, symbol generation, `bitsToSamples`, `bitsToSamplesWithHeader` (24-bit redundant length header), `bytesToBits`/`bitsToBytes` helpers
  - Implemented `Decoder`: Goertzel magnitude detector, `findPreambleEnd`, `readBits`, `majorityVoteHeader` (triple-redundant 8-bit header with majority vote), `decodeLengthPrefixedBits`
  - Protocol constants in `protocol.dart` matching PROTOCOL.md exactly
  - Updated timing formula to T = 2.7 + 0.8L (accounts for 24-bit redundant header: 0.3s preamble + 2.4s header + 0.8L payload)
  - Unit tests pass: sine round-trip, Goertzel discrimination, redundant header round-trip, majority vote repair, byte/bit helpers, end-to-end crypto+tone compose

## [Stage 3] Embedding & Offline Round-Trip
- **Completed:**
  - Created `lib/audio/wav_utils.dart`: pure `dart:io`/`dart:typed_data` WAV reader/writer — reads 16-bit PCM mono/stereo (stereo downmixed to mono), writes 16-bit PCM mono, handles RIFF/WAVE/fmt/data chunk parsing directly
  - Created `lib/audio/embedder.dart`: full embedding/extraction pipeline — `embed` (sample-level mixing with clipping), `embedMessage` (encrypt → tone-encode → embed), `extractMessage` (preamble scan → decode → decrypt)
  - Extended `Decoder` with `findPreambleEndFrom`: two-phase preamble scanner (coarse symbol-step scan + boundary refinement) for locating watermarks embedded at arbitrary positions within a full-length host signal
  - All 6 Stage 3 tests pass: full pipeline round-trip, offset embedding, amplitude clipping, host-too-short error, WAV read/write quantization, end-to-end through 16-bit PCM
  - All Stage 1 and Stage 2 tests still pass (no regressions)
- **Notes / Discoveries:**
  - Naive sample-by-sample preamble scanning triggers early due to Goertzel window overlap — the two-phase approach (coarse scan then boundary refinement) fixes this and is also dramatically faster (0ms vs hundreds of ms)
  - 16-bit PCM quantization does NOT corrupt the watermark — the watermark survives the write→read round-trip cleanly, confirming viability for real audio file workflows

## [Stage 4] Real Audio Hardware, Isolated Calibration Test
- **Completed:**
  - Added `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS` permissions to `android/app/src/main/AndroidManifest.xml`
  - Added `ToneGenerator.generatePureTone(freq, durationMs, {amplitude})` for playing continuous multi-second pure sine tones for speaker/mic calibration
  - Enhanced `WavUtils` with in-memory `writeWavBytes` and `readWavBytes` methods for seamless zero-disk WAV playback via `flutter_sound`
  - Implemented `lib/audio/calibration_screen.dart`:
    - Tone emission buttons for Preamble (17.0 kHz), Bit 0 (18.0 kHz), and Bit 1 (19.5 kHz) using `FlutterSoundPlayer`
    - Live microphone PCM streaming (44.1 kHz, 16-bit mono) via `FlutterSoundRecorder`
    - Rolling window buffer + real-time `Decoder.goertzelMagnitude` calculations
    - Live numerical readouts, relative energy bar graphs, and dominant frequency detection indicators
  - Mounted `CalibrationScreen` in `lib/main.dart` as default entry point for direct device testing
  - Created `docs/stage4_calibration_results.md` containing full test protocol and calibration log template
  - Added `test/calibration_dsp_test.dart` verifying tone generation, WAV byte serialization, and Goertzel magnitude discrimination on byte buffers (all 23 unit tests pass)
- **Notes / Discoveries:**
  - Modern `flutter_sound` (v9.6+) directly accepts `StreamSink<Uint8List>` for `startRecorder(toStream: ...)`, avoiding legacy `FoodData` wrappers.
  - In-memory WAV generation via `WavUtils.writeWavBytes` completely eliminates the need for temporary disk files when playing audio through `FlutterSoundPlayer`.

## [Stage 5] Full Pipeline on Real Hardware, Same Device
- **Completed:**
  - Implemented `lib/audio/audio_transmitter.dart`:
    - Full transmission flow: message encryption (AES-128-CTR) → watermark embedding (`Embedder.embedMessage`) → zero-disk WAV byte generation (`WavUtils.writeWavBytes`) → speaker playback via `FlutterSoundPlayer`
    - Progress callbacks (`onStatus`, `onDone`) with start/stop control
  - Implemented `lib/audio/audio_receiver.dart`:
    - Full listening flow: continuous 44.1 kHz PCM microphone capture via `FlutterSoundRecorder`
    - Incremental preamble and length-prefixed payload scanning (`Decoder.findPreambleEndFrom` with overlap memory)
    - Full payload extraction, bit reconstruction, and AES-128-CTR decryption
    - Automatic stop and `onResult` dispatch upon successful recovery
  - Added real music host asset `assets/host_songs/acoustic_breeze.wav` and `assets/host_song.wav` registered in `pubspec.yaml`
  - Created `lib/audio/pipeline_test_screen.dart`:
    - Interactive message input, random AES-128 key generation, host carrier selector (Asset / Synthesized / Quiet)
    - Send (Transmitter), Listen (Receiver), and "Run Single-Device Loopback (Listen + Send)" one-tap test controls
    - Live pipeline status updates and verified message match indicators
    - Navigation bar shortcut to `CalibrationScreen`
  - Updated `lib/main.dart` to launch `PipelineTestScreen` as home screen
  - Added `test/audio_pipeline_unit_test.dart` verifying short, medium, and long sentence round-trips through synthetic music hosts and WAV byte serialization (all 29 unit tests pass)
- **Notes / Discoveries:**
  - Incremental sliding search with `_searchOffset` and overlap memory prevents O(N^2) re-scanning overhead on long listening sessions while ensuring preambles that cross chunk boundaries are never missed.
