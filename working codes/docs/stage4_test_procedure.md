# Stage 4: Phone Hardware Frequency Test

Stage 4 tests only the physical speaker and microphone path. It does not use encryption, framing, song embedding, or the Stage 3 pipeline.

## Setup

- Use two separate physical phones. Do not use same-device loopback; that is Stage 5.
- Install and run the app on both phones.
- Place the phones at the target demo distance and orientation.
- Check that microphone permission is granted on Phone B.

## Procedure

1. On Phone B, tap **Record & Analyze**.
2. Immediately on Phone A, tap **Play Test Tones**. Starting the recording just before playback is also fine.
3. Wait for the five-second recording to finish.
4. Review the raw sliding-window readings for 17,000 Hz, 18,000 Hz, and 19,500 Hz.

Phone A plays 17 kHz for 300 ms, waits one second, plays 18 kHz for one second, waits one second, and plays 19.5 kHz for one second. The analyzer uses 100 ms windows with 50 ms hops.

## What pass looks like

The 18 kHz magnitude should produce a clear spike during its play window, and the 19.5 kHz magnitude should produce a separate spike during its own window. Both should be distinguishable from each other and from background/silent windows. As a rough starting threshold, compare the active-tone window with a silent window and look for a ratio of at least **5x to 10x**. Treat this as a guideline, not an automatic verdict; record the actual values.

The app intentionally displays raw magnitudes rather than only pass/fail so device, distance, volume, and room effects can be judged directly.

## If results are weak or ambiguous

Record the phone models, distance, volume, and observed magnitude readings in `STATUS.md` or `DECISIONS.md`. Do not proceed to Stage 5 based on an ambiguous result. Ask for the frequency-shift fallback before changing the protocol: retest with the frequency table shifted down, for example using approximately 13,000 Hz and 14,500 Hz for the bit frequencies and an appropriately separated preamble frequency.

Codespaces cannot validate this stage because it has no access to the target phones' speaker and microphone. This test must be run manually on real hardware; an Android emulator with audio passthrough is only a secondary fallback.