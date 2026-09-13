# Audio Watermark Demo — UI/UX Design Document

> **App:** Audio Watermark Demo  
> **Platform:** Android (API 24+, Material Design 3)  
> **Package:** `com.spproject.audiowatermark`  
> **Version:** 1.0  

---

## 1. Design Philosophy

The app follows **Material Design 3** with a clean, professional aesthetic. The single-screen layout eliminates navigation complexity — everything is visible at once. The UI is divided into three clear zones:

| Zone | Purpose | Color Accent |
|------|---------|-------------|
| Person A — Transmit | Message input & playback | Blue (`#2563EB`) |
| Person B — Receive | Microphone capture & decode | Teal (`#0D9488`) |
| Status & Diagnostics | Real-time feedback | Dynamic (state-driven) |

---

## 2. Screen Layout

### 2.1 App Header
- **Title:** "Audio Watermark Demo" with waveform icon (`ic_waveform`)
- **Subtitle:** "Acoustic steganography via inaudible carrier embedding (Speaker -> Mic)"
- **Tech badges:**
  - `AES-CTR 128` — Blue (`bg_badge_primary`)
  - `20 kHz Carrier` — Teal (`bg_badge_secondary`)
  - `Goertzel Filter` — Purple (`bg_badge_tertiary`)

### 2.2 Person A — Transmit Card (`cardPersonA`)
- Background: White `#FFFFFF`, Border: Blue stroke `#BFDBFE`, corner radius 16dp
- Header: Lock icon + "PERSON A — TRANSMIT" in `#1E40AF`
- Input: `TextInputLayout` (OutlinedBox), max 30 chars, start icon = lock
- Button: filled `MaterialButton`, 52dp height, "Encrypt, Embed & Play"

### 2.3 Person B — Receive Card (`cardPersonB`)
- Background: White `#FFFFFF`, Border: Teal stroke `#99F6E4`, corner radius 16dp
- Header: Mic icon + "PERSON B — RECEIVE" in `#115E59`
- Button: tonal `MaterialButton`, 52dp height, "Listen & Decode (20 s)"
  - Background tint: `@color/secondary_container` (`#CCFBF1`)

### 2.4 Status & Diagnostics Card (`cardStatus`)
- Fully dynamic — all colors change with app state
- Components: icon + title + badge + progress bar (in-progress only) + divider + monospace text

---

## 3. Status State Design System

| State | Background | Stroke | Badge | Icon |
|-------|-----------|--------|-------|------|
| IDLE | `#F8FAFC` | `#E2E8F0` | Grey | `ic_info` |
| IN_PROGRESS | `#EFF6FF` | `#93C5FD` | Blue | `ic_waveform` + progress bar |
| SUCCESS | `#ECFDF5` | `#6EE7B7` | Green | `ic_check_circle` |
| NO_SIGNAL | `#FFFBEB` | `#FCD34D` | Amber | `ic_signal_off` |
| NO_PREAMBLE_LOCK | `#FFF7ED` | `#FDBA74` | Orange | `ic_lock_open` |
| DECRYPT_FAILED | `#FEF2F2` | `#FCA5A5` | Red | `ic_key_off` |
| GARBAGE_OUTPUT | `#FAF5FF` | `#D8B4FE` | Purple | `ic_code_off` |
| WARNING | `#FFFBEB` | `#FCD34D` | Amber | `ic_warning` |
| ERROR | `#FEF2F2` | `#FCA5A5` | Red | `ic_error` |

---

## 4. Color Palette

### Brand Colors
| Name | Hex | Usage |
|------|-----|-------|
| Primary | `#2563EB` | Buttons, Person A |
| Primary Variant | `#1D4ED8` | Pressed states |
| Primary Container | `#DBEAFE` | Progress bar track |
| Secondary | `#0D9488` | Person B accent |
| Secondary Container | `#CCFBF1` | Listen button bg |

### Surface & Text
| Name | Hex | Usage |
|------|-----|-------|
| App background | `#F8FAFC` | Window background |
| Card surface | `#FFFFFF` | Card backgrounds |
| Text primary | `#0F172A` | Titles |
| Text secondary | `#64748B` | Sub-labels |

---

## 5. Typography

| Element | Size | Style | Font |
|---------|------|-------|------|
| App title | 22sp | Bold | System |
| Card headers | 12sp | Bold, letter-spacing 0.05 | System |
| Button text | 15sp | Bold | System |
| Status text | 13sp | Normal, line-spacing 1.3 | Monospace |
| Badge text | 10sp | Bold | System |
| Input text | 14sp | Normal | System |

---

## 6. Icon Set (Vector Drawables in `res/drawable/`)

| File | Icon | State |
|------|------|-------|
| `ic_waveform.xml` | Waveform | Header, IN_PROGRESS |
| `ic_lock.xml` | Lock | Person A, input field |
| `ic_lock_open.xml` | Open lock | NO_PREAMBLE_LOCK |
| `ic_mic.xml` | Microphone | Person B |
| `ic_play_arrow.xml` | Play | Send button |
| `ic_check_circle.xml` | Check | SUCCESS |
| `ic_signal_off.xml` | No signal | NO_SIGNAL |
| `ic_key_off.xml` | No key | DECRYPT_FAILED |
| `ic_code_off.xml` | No code | GARBAGE_OUTPUT |
| `ic_warning.xml` | Warning | WARNING |
| `ic_error.xml` | Error | ERROR |
| `ic_info.xml` | Info | IDLE |

---

## 7. Badge Drawables

| File | Background Color | State |
|------|-----------------|-------|
| `bg_badge_idle.xml` | `#E2E8F0` (Grey) | IDLE |
| `bg_badge_progress.xml` | `#BFDBFE` (Blue) | IN_PROGRESS |
| `bg_badge_success.xml` | `#A7F3D0` (Green) | SUCCESS |
| `bg_badge_nosignal.xml` | `#FDE68A` (Amber) | NO_SIGNAL |
| `bg_badge_preamble.xml` | `#FED7AA` (Orange) | NO_PREAMBLE_LOCK |
| `bg_badge_decrypt.xml` | `#FECACA` (Red) | DECRYPT_FAILED |
| `bg_badge_garbage.xml` | `#E9D5FF` (Purple) | GARBAGE_OUTPUT |
| `bg_badge_error.xml` | `#FECACA` (Red) | ERROR |
| `bg_badge_primary.xml` | `#EFF6FF` (Blue) | AES-CTR tech badge |
| `bg_badge_secondary.xml` | `#CCFBF1` (Teal) | 20kHz tech badge |
| `bg_badge_tertiary.xml` | Purple bg | Goertzel tech badge |

---

## 8. Theme (`themes.xml`)

**Theme:** `Theme.AudioWatermark` extends `Theme.Material3.DayNight.NoActionBar`

```xml
<style name="Theme.AudioWatermark" parent="Theme.Material3.DayNight.NoActionBar">
    <item name="colorPrimary">@color/primary</item>           <!-- #2563EB -->
    <item name="colorSecondary">@color/secondary</item>       <!-- #0D9488 -->
    <item name="android:windowBackground">@color/bg_app</item><!-- #F8FAFC -->
    <item name="android:statusBarColor">@color/bg_app</item>
    <item name="android:windowLightStatusBar">true</item>
</style>
```

---

## 9. UX Flow Diagram

```
[App Launch]
     |
     v
[IDLE State] ---> User types message --> [Tap "Encrypt, Embed & Play"]
     |                                          |
     |                                          v
     |                              [ENCRYPTING] -> [LOADING AUDIO]
     |                                          |
     |                                          v
     |                              [EMBEDDING] -> [TRANSMITTING]
     |                                          |
     |                                          v
     |                              [PLAYBACK COMPLETE / SUCCESS]
     |
     +-----> [Tap "Listen & Decode"] --> [Permission check]
                                                |
                                   +------------+------------+
                                   |                         |
                             [Denied]                  [Granted]
                                   |                         |
                             [ERROR]            [LISTENING 20s countdown]
                                                             |
                                                             v
                                                     [Decode pipeline]
                                                             |
                              +----------+----------+--------+--------+
                              |          |          |                 |
                          [SUCCESS] [NO_SIGNAL] [NO_PREAMBLE] [DECRYPT_FAILED]
                                                            [GARBAGE_OUTPUT]
```

---

## 10. Accessibility

- All interactive elements >= 48dp touch target (buttons are 52dp)
- Text contrast meets WCAG AA for all state color combinations
- Disabled state uses 50% alpha for clear visual feedback
- Monospace status font for predictable layout during live updates
- No animations that would cause accessibility issues

---

## 11. Screen Mockups

See `docs/mockups/` for PNG exports:

| File | Description |
|------|-------------|
| `screen_idle.jpg` | Initial idle state |
| `screen_transmitting.jpg` | Person A transmitting |
| `screen_success.jpg` | Successful decode |
| `screen_error_states.jpg` | All 4 error/failure state cards |
| `system_architecture.jpg` | End-to-end system diagram |
