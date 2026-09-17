# Contributing to Audio Watermark Demo

Thank you for contributing! This document describes how to work with this codebase effectively.

---

## Code Style

- **Language:** Kotlin (no Java files)
- **Style:** Follow official [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)
- **Comments:** All public functions must have KDoc comments
- **Objects vs Classes:**
  - Use `object` for stateless utilities (`AesCrypto`, `Goertzel`, etc.)
  - Use `class` only when instance state is needed (`AudioTransmitter`, `AudioReceiver`)

---

## Making Changes

### Adding new status states
1. Add the new enum value to `MainActivity.StatusState`
2. Create a matching `bg_badge_*.xml` drawable in `res/drawable/`
3. Add the state colors to `res/values/colors.xml`
4. Add a `when` branch in `MainActivity.setStatus()` returning a `StyleConfig`
5. Update `UI_UX_DESIGN.md` with the new state's color theme

### Modifying signal parameters
All shared parameters live in `Config.kt`. **Never hardcode** frequency or timing values elsewhere. Any change to `Config` must be deployed identically on both the transmitter and receiver phone, or decoding will fail.

### Adding new decode result types
1. Add a new `data class` in `Decoder.DecodeResult`
2. Return it from `Decoder.decode()` where appropriate
3. Handle it in `MainActivity.handleDecodeResult()` with a new `when` branch

---

## Testing

### Manual test procedure
1. Build and install the debug APK on two Android phones
2. Run the same-device sanity check first (see SETUP.md)
3. Run the two-device test at 10cm, 30cm, and 1m distances
4. Test with background noise (music playing in the room)
5. Test edge cases: blank message, max-length (30 char) message

### Logcat verification
- Verify preamble energy > 1,000,000 at close range
- Verify per-bit Goertzel energies in the energy table (mag@18k vs mag@19.5k should differ by at least 2x)
- Verify no clipping logged by `Embedder`

---

## File Checklist Before Submitting

- [ ] `Config.kt` constants unchanged (or both devices updated)
- [ ] No hardcoded strings in Kotlin (use constants or string resources)
- [ ] KDoc on all public/internal functions
- [ ] No `TODO` or `FIXME` comments without an associated issue
- [ ] Logcat is clean (no unexpected errors or warnings)
- [ ] `docs/` updated if architecture or UI design changed

---

## Project-Specific Pitfalls

| Pitfall | Avoidance |
|---------|-----------|
| Changing `SYMBOL_DURATION_MS` without updating preamble scan step | Always audit `Decoder.findPreambleEnd()` |
| Using STATIC mode in AudioTrack | STATIC caps buffer; always use STREAM mode for songs |
| Calling `AudioRecord.read()` on the main thread | Always record on a background thread |
| Forgetting to call `recorder.release()` | Use try/finally or a wrapper |
| Assuming WAV is always mono | `WavUtils` handles stereo → mono downmix |
