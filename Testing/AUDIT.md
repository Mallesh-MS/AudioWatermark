# Security, DSP, and Protocol Audit Report: AudioWatermark

## Executive Summary
An in-depth adversarial audit was conducted on the ultrasonic audio watermarking system at `github.com/Mallesh-MS/AudioWatermark`. The core system comprises a pure Dart digital signal processing (DSP) and cryptographic pipeline (`DSP/lib/`), a Flutter mobile client (`UI/Flutter/lib/`), and a test suite (`Testing/`).

All tests were performed in strict compliance with the audit constraints: no production source files were modified, all DSP simulations were executed deterministically and offline without hardware I/O, and cross-implementation Kotlin parity testing (Group E) was excluded.

### Audit Test Suite Overview
Four comprehensive test suites were created under `Testing/test/` to be collected and run natively by `dart test`:
- `Testing/test/audit_group_a_test.dart` (Crypto & Integrity: Keystream reuse, Malleability, Key material, Replay, AES vectors)
- `Testing/test/audit_group_b_test.dart` (Protocol & Framing: Fuzz length headers, Preamble collision, Broadband noise false positives, Frame offset alignment)
- `Testing/test/audit_group_c_test.dart` (DSP & Modulation: Goertzel bin alignment, Leakage, 48k vs 44.1k mismatch, Phase continuity, Int16 saturation, Robustness sweep)
- `Testing/test/audit_group_d_test.dart` (WAV Parsing & Fuzzing: Truncated headers, Spoofed chunk sizes, Zero channels, Zero sample rate, 24-bit / 32-bit float rejection)

---

## Findings Summary Table

| ID | Category | Vulnerability / Issue | Severity | Status | Demonstrating Test |
|---|---|---|---|---|---|
| **A.1** | Crypto | Keystream Reuse Across Sessions (ADR 005 Zero-IV) | Weakness | Confirmed (Known Tradeoff) | `audit_group_a_test.dart` > `A.1: Keystream Reuse` |
| **A.2** | Integrity | Keyless Ciphertext Malleability & CRC-8 Forgery | **Break** | Confirmed Exploit | `audit_group_a_test.dart` > `A.2: Malleability Forgery` |
| **A.3** | Crypto | Key Material Randomness & QR Envelope | Pass | Verified Sound | `audit_group_a_test.dart` > `A.3: Key Material` |
| **A.4** | Integrity | Unmitigated Acoustic Replay Attacks | **Break** | Confirmed Exploit | `audit_group_a_test.dart` > `A.4: Replay Attacks` |
| **A.5** | Crypto | AES Vectors & Boundary Negative Handling | Pass | Verified Sound | `audit_group_a_test.dart` > `A.5: AES Vectors` |
| **B.6** | Protocol | Truncated Length-Prefixed Stream Unhandled RangeError | Weakness | Confirmed Defect | `audit_group_b_test.dart` > `B.6: Fuzz Frame Parsing` |
| **B.7** | Protocol | False Mid-Payload Preamble Desynchronization | Weakness | Confirmed Risk | `audit_group_b_test.dart` > `B.7: Payload Matching` |
| **B.8** | Protocol | Broadband Noise Triggers False Preamble Detections | **Break** | Confirmed Defect | `audit_group_b_test.dart` > `B.8: False Positives` |
| **C.9** | DSP | Goertzel Bin Center Alignment & Leakage | Pass | Verified Sound | `audit_group_c_test.dart` > `C.9: Goertzel Bin Alignment` |
| **C.10**| DSP | Silent Failure on 48 kHz / 44.1 kHz Sample Rate Mismatch | Weakness | Confirmed Defect | `audit_group_c_test.dart` > `C.10: Sample-Rate Mismatch` |
| **C.11**| DSP | Inter-Symbol Boundary Phase Discontinuities | Hardening | Confirmed Risk | `audit_group_c_test.dart` > `C.11: Phase Continuity` |
| **C.12**| DSP | Int16 Clamping & Normalization Overflow Saturation | Pass | Verified Sound | `audit_group_c_test.dart` > `C.12: Embedder Int16 Saturation` |
| **D.14**| Input | Unhandled RangeError & OOM on Spoofed WAV Chunk Size | Weakness | Confirmed Defect | `audit_group_d_test.dart` > `D.14: Fuzzing WavUtils` |
| **D.14b**| Input | Zero Channels Triggers IntegerDivisionByZeroException | Weakness | Confirmed Defect | `audit_group_d_test.dart` > `D.14: Fuzzing WavUtils` |
| **F.15**| Lifecycle | Key Material & Audio History Retained in Static Memory | Hardening | Confirmed Defect | Manual Code Audit (audio_receiver.dart) |

---

## Detailed Vulnerability Analysis

### Finding A.1: Keystream Reuse Across Multiple Sessions
- **Severity**: **Weakness** (Confirmed Known Limitation per ADR 005)
- **Demonstrating Test**: `Testing/test/audit_group_a_test.dart` -> `Priority Group A.1: Keystream Reuse (ADR 005 Zero-IV)`
- **Observed Behaviour**: For two different plaintexts P1 and P2 encrypted with the same session key K, `C1 ^ C2 == P1 ^ P2` holds for 100% of bytes. Knowing P1 allows instant algebraic recovery of P2 via `P2 = C1 ^ C2 ^ P1`.
- **Expected Behaviour**: Cryptographically secure stream ciphers require unique nonces/IVs across sessions so that `C1 ^ C2 != P1 ^ P2`.
- **Root Cause**: `WatermarkCrypto._fixedIV` in `DSP/lib/dsp/aes_crypto.dart` hardcodes a static 16-byte zero IV (`IV(Uint8List(16))`) to avoid transmitting 16 bytes of IV overhead over a low-bandwidth (~10 bps) acoustic channel.
- **Suggested Fix**: Transmit a 2-byte random session salt in the frame header to perturb the initial CTR counter block.

---

### Finding A.2: Keyless Ciphertext Malleability & CRC-8 Forgery
- **Severity**: **Break**
- **Demonstrating Test**: `Testing/test/audit_group_a_test.dart` -> `Priority Group A.2: Malleability Forgery (CTR + CRC-8)`
- **Observed Behaviour**: A keyless attacker intercepted `'Transfer 1000 USD to Alice!'`, flipped the bit corresponding to `'1' ^ '9'`, added the precalculated differential CRC byte `delta_CRC = CRC8(delta)`, and transmitted the modified tone burst. `Embedder.extractMessage` verified the CRC as authentic and decrypted `'Transfer 9000 USD to Alice!'` with zero errors.
- **Expected Behaviour**: Altered ciphertexts must fail cryptographic authentication and be discarded as invalid.
- **Root Cause**: AES-CTR is malleable (bit-flips in ciphertext translate directly to decrypted plaintext), and CRC-8 is linear over GF(2) with XOR, offering zero integrity protection against active adversaries.
- **Suggested Fix**: Replace CRC-8 with an authenticated MAC (e.g. HMAC-SHA256 truncated to 4 bytes or Poly1305).

---

### Finding A.4: Unmitigated Acoustic Replay Attacks
- **Severity**: **Break**
- **Demonstrating Test**: `Testing/test/audit_group_a_test.dart` -> `Priority Group A.4: Replay Attacks`
- **Observed Behaviour**: The receiver decoded the exact same captured PCM audio buffer repeatedly, outputting the message on every playback.
- **Expected Behaviour**: Replayed audio packets must be rejected after their initial receipt.
- **Root Cause**: The physical frame format contains only `[Preamble] + [Length Header] + [Ciphertext] + [CRC-8]`. It lacks timestamps, sequence numbers, ephemeral nonces, or challenge-response tracking.
- **Suggested Fix**: Embed a 16-bit monotonic sequence counter in the authenticated payload and track received counters in `AudioReceiver`.

---

### Finding B.8: Broadband Noise Triggers False Preamble Detections
- **Severity**: **Break**
- **Demonstrating Test**: `Testing/test/audit_group_b_test.dart` -> `Priority Group B.8: Preamble False Positives and Offset Robustness`
- **Observed Behaviour**: 60 seconds of synthetic White Noise triggered a false preamble detection at sample `48510` in `findPreambleEndFrom`. 60 seconds of synthetic Pink Noise triggered a false preamble detection at sample `52920` in `findPreambleEndFrom`. Sample-by-sample scanning (`findPreambleEnd`) triggered a false alarm at sample `40661`.
- **Expected Behaviour**: Unwatermarked environmental noise and acoustic hiss should produce zero false preamble hits.
- **Root Cause**: The preamble detection rule relies solely on energy ratio `M_17000 > 2 * max(M_18000, M_19500)` and `M_17000 > 1.0`. Random noise fluctuations regularly meet this criterion over extended listening periods.
- **Suggested Fix**: Replace the single continuous 17 kHz tone with a pseudo-random chirp sequence or Barker code (e.g. 11-bit or 13-bit Barker sequence).

---

### Finding B.6: Truncated Length-Prefixed Stream Crashes with Unhandled RangeError
- **Severity**: **Weakness**
- **Demonstrating Test**: `Testing/test/audit_group_b_test.dart` -> `Priority Group B.6: Fuzz Frame Parsing with Malformed Length Fields`
- **Observed Behaviour**: If a frame header declares a length of 255 bytes but the incoming sample buffer contains fewer samples than required (255 * 8 * 4410), `Decoder.decodeLengthPrefixedBits` throws an unhandled RangeError.
- **Expected Behaviour**: The decoder should check that `samples.length >= preambleEnd + headerSamples + (byteLength * 8 * symbolSamples)` before indexing, returning empty or throwing a typed exception.
- **Root Cause**: Missing bounds validation in `Decoder.decodeLengthPrefixedBits` before invoking `readBits`.
- **Suggested Fix**: Add `if (payload.length < byteLength * 8 * _symbolSamples) return [];` in `Decoder.decodeLengthPrefixedBits`.

---

### Finding C.10: Silent Failure on Sample Rate Mismatch
- **Severity**: **Weakness**
- **Demonstrating Test**: `Testing/test/audit_group_c_test.dart` -> `Priority Group C.10: Sample-Rate Mismatch Handling`
- **Observed Behaviour**: Audio synthesized at 48000 Hz and decoded at 44100 Hz fails silently, returning null without indicating incompatible sample rates.
- **Expected Behaviour**: The pipeline should inspect `WavData.sampleRate` or reject non-44.1 kHz buffers with an explicit warning or resample them.
- **Root Cause**: `sampleRate = 44100` is hardcoded as a global constant across all Goertzel frequency calculations in `protocol.dart`.
- **Suggested Fix**: Pass sample rate dynamically to `Decoder.goertzelMagnitude` or resample input audio buffers to 44.1 kHz via linear interpolation.

---

### Finding C.11: Phase Discontinuity Across Symbol Boundaries
- **Severity**: **Hardening**
- **Demonstrating Test**: `Testing/test/audit_group_c_test.dart` -> `Priority Group C.11: Phase Continuity across Symbol Boundaries`
- **Observed Behaviour**: The step difference between the last sample of a symbol and the first sample of the next symbol reaches 0.0136 (over 54% of full tone amplitude).
- **Expected Behaviour**: Continuous-phase FSK (CPFSK) should maintain smooth phase progression across symbol transitions to minimize out-of-band spectral splatter.
- **Root Cause**: `ToneGenerator._generateTone` resets the sine time index to 0 at every symbol boundary rather than maintaining an ongoing phase accumulator.
- **Suggested Fix**: Maintain an ongoing phase accumulator across successive symbol generations in `ToneGenerator`.

---

### Finding D.14: WAV Parser Crash on Spoofed Data Chunk Sizes
- **Severity**: **Weakness**
- **Demonstrating Test**: `Testing/test/audit_group_d_test.dart` -> `Priority Group D.14: Fuzzing WavUtils Robustness`
- **Observed Behaviour**: Supplying a WAV header with declared `dataSize = 100000` on a 44-byte buffer causes `WavUtils.readWavBytes` to allocate a 50,000-element double list and then throw an unhandled RangeError on `data.getInt16(44)`.
- **Expected Behaviour**: The parser should validate `dataOffset + dataSize <= bytes.length` and throw `ArgumentError("Truncated WAV data chunk")`.
- **Root Cause**: `WavUtils.readWavBytes` reads `dataSize` from the header and uses it directly for array sizing without validating against actual buffer length.
- **Suggested Fix**: Add `if (dataOffset + dataSize > bytes.length) throw ArgumentError("Declared data size exceeds buffer");`.

---

### Finding D.14b: Integer Division by Zero on Zero Audio Channels
- **Severity**: **Weakness**
- **Demonstrating Test**: `Testing/test/audit_group_d_test.dart` -> `Priority Group D.14: Fuzzing WavUtils Robustness`
- **Observed Behaviour**: A header declaring `numChannels = 0` causes an unhandled IntegerDivisionByZeroException (`UnsupportedError`) on line 89 of `wav_utils.dart`.
- **Expected Behaviour**: Should validate `numChannels >= 1` and throw `ArgumentError`.
- **Root Cause**: Lack of sanity checking on channel count in `WavUtils.readWavBytes`.
- **Suggested Fix**: Add `if (numChannels < 1 || numChannels > 2) throw ArgumentError("Only mono and stereo supported");`.

---

### Finding F.15: Static Memory Retention of Key Material and Recorded Samples
- **Severity**: **Hardening**
- **Demonstrating Test**: Manual Code Inspection of `DSP/lib/audio/audio_receiver.dart`
- **Observed Behaviour**: When `AudioReceiver.stopListening()` or `dispose()` is executed, `_activeKey` is not set to null or zeroized, and `_accumulatedSamples` is not cleared.
- **Expected Behaviour**: Teardown should zeroize private cryptographic keys and flush audio recording buffers from RAM.
- **Root Cause**: `_activeKey` and `_accumulatedSamples` are static fields that omit cleanup in `stopListening()` and `dispose()`.
- **Suggested Fix**: Add `_activeKey = null; _accumulatedSamples.clear();` inside `AudioReceiver.stopListening()`.

---

## Item 13: Robustness Sweep Results Table

The robustness sweep was empirically measured using offline synthetic acoustic simulation in `Testing/test/audit_group_c_test.dart`:

| Channel Condition / Impairment | Test Parameter | Decode Success Rate | Failure Mechanism / Diagnostic |
|---|---|:---:|---|
| **Clean Channel (Baseline)** | 0 dB attenuation, silent carrier | **100%** | Baseline clean decode |
| **Additive White Gaussian Noise** | **20 dB SNR** | **100%** | CRC-8 intact, clean decode |
| **Additive White Gaussian Noise** | **10 dB SNR** | **100%** | CRC-8 intact, clean decode |
| **Additive White Gaussian Noise** | **5 dB SNR** | **100%** | CRC-8 intact, clean decode |
| **Additive White Gaussian Noise** | **0 dB SNR** | **100%** | Goertzel coherent integration (N=4410) overcomes 0 dB broadband noise |
| **TX/RX Clock Drift (Resampling)** | **+0.5% Clock Mismatch** | **0%** | Symbol boundary drift exceeds Goertzel window integration bounds |
| **TX/RX Clock Drift (Resampling)** | **-0.5% Clock Mismatch** | **0%** | Inter-symbol interference and cumulative frame offset misalignment |
| **Acoustic Low-Pass Filter (Voice band)** | **Cutoff = 4,000 Hz** (Steep 24 dB/oct) | **0%** | Carrier stripped; 17–19.5 kHz tones are outside phone voice speaker passband |
| **Acoustic Low-Pass Filter** | **Cutoff = 8,000 Hz** (Steep 24 dB/oct) | **0%** | Carrier stripped; all watermark frequencies attenuated below detection threshold |
| **Ultrasonic Microphone Roll-Off** | **Cutoff = 16,000 Hz** | **0%** | Hardware microphone roll-off attenuates 17–19.5 kHz; preamble not detected |

---

## Defense & Viva Strategy Guide

### 1. The Zero-IV Tradeoff (ADR 005)
- **Question**: *"Why did you use a fixed zero-IV for AES-CTR instead of generating a random IV per message?"*
- **Defense**: *"At our acoustic bitrate of ~10 bps (100 ms per symbol), transmitting a 16-byte random IV would add 12.8 seconds of transmission delay to every message. For our demo use case of short text messages exchanged between two nearby phones, ADR 005 accepted this tradeoff under the condition that session keys are ephemeral and generated fresh per transaction via QR code. As our audit proves, if an attacker observes two messages under the same key, keystream cancellation completely compromises confidentiality. A robust next version would transmit a 2-byte salt or derive a session counter to eliminate reuse while adding only 1.6s of overhead."*

### 2. CRC-8 vs. Cryptographic MAC
- **Question**: *"Why does the frame use CRC-8 instead of HMAC or AES-GCM?"*
- **Defense**: *"CRC-8 was chosen for physical transmission channel error detection (detecting random burst errors and microphone packet drops over the air). However, as our adversarial audit proved in Finding A.2, CRC-8 does not provide cryptographic integrity. Because AES-CTR is bitwise malleable and CRC-8 is linear over XOR, a keyless attacker can flip bits in the ciphertext and update the CRC byte without knowing the key. In production, CRC-8 must be replaced by a truncated HMAC or an AEAD mode."*

### 3. Acoustic Clock Drift Sensitivity
- **Question**: *"Why does the decoder fail at +-0.5% sample-rate clock drift?"*
- **Defense**: *"At 44.1 kHz, a 0.5% clock mismatch shifts the receiver by 22 samples every 100 ms symbol. Over a 20-byte transmission (~160 symbols), the cumulative error exceeds 3,500 samples—almost an entire symbol window. Without adaptive phase tracking or symbol synchronization, the Goertzel filter samples across symbol boundaries, causing complete signal loss."*
