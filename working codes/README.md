# Project: Encrypted Audio Watermark Transmission

## Overview
An Android/iOS app (Flutter) that hides an encrypted text message inside an
ordinary song using near-ultrasonic audio watermarking. One phone plays the
watermarked song through its speaker; another phone's microphone captures it,
extracts the hidden tones, and decrypts the original message — recoverable only
by someone holding the correct AES key (exchanged via QR code, out-of-band from
the acoustic channel). Originally proposed as a signal-processing course project
(derived from pre-approved topic SP24/SP23), now being built as a real two-person
Flutter app.

## Tech Stack
- **UI:** Flutter (Dart) — built by teammate using Google Stitch, integrated here
- **DSP/Crypto logic:** Flutter (Dart) — built by [your name] using VS Code + GitHub Copilot
- **Audio I/O:** `flutter_sound` (raw PCM record/playback via Dart streams)
- **Encryption:** `encrypt` package (wraps `pointycastle`), AES-128-CTR
- **QR key exchange:** `qr_flutter` (generate) + `mobile_scanner` (scan)
- **Platforms targeted:** Android first, iOS if time permits

## Directory Structure
- `lib/dsp/` — Pure Dart signal processing + crypto logic (no Flutter/UI dependency, unit-testable)
- `lib/audio/` — Thin wrappers around `flutter_sound` for real speaker/mic I/O
- `lib/ui/` — Flutter widgets/screens (teammate's Stitch-generated work lives here)
- `lib/main.dart` — App entry point, wires UI to DSP/audio layers
- `test/` — Dart unit tests for `lib/dsp/`
- `docs/` — Reference material, including `docs/copilot_prompts/` (prompts used to scaffold each stage)
- `assets/host_songs/` — Sample WAV host songs for testing

## Memory Files (read before starting any work session)
- `STATUS.md` — current phase, active task, blockers
- `PROGRESS.md` — chronological log of what's been done
- `DECISIONS.md` — why things were built the way they were (avoid re-litigating settled choices)
- `PROTOCOL.md` — the exact shared parameters both transmitter and receiver logic MUST match

**Update `STATUS.md` and `PROGRESS.md` at the end of every work session. Read all
four memory files at the start of every new session before writing code.**
