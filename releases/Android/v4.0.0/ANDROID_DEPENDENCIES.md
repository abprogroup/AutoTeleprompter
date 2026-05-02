# AutoTeleprompter v4.0 — Android Dependencies & Device Compatibility

## Minimum Device Requirements

| Requirement | Value | Notes |
|-------------|-------|-------|
| **Minimum Android Version** | Android 6.0 (Marshmallow) | `minSdk = 23` |
| **Target Android Version** | Android 14 (Upside Down Cake) | `targetSdk = 34` |
| **Compile SDK** | 34 | |
| **CPU Architecture** | ARM 32-bit, ARM 64-bit, x86_64 | APK includes `armeabi-v7a`, `arm64-v8a`, `x86_64` native libs |
| **RAM** | 2GB+ recommended | Whisper models need additional memory when active |
| **Storage** | ~60MB for app | +75MB–1.5GB if Whisper models downloaded (v5.0 feature) |

## Android Version Compatibility Matrix

| Android Version | API | Core App | Google STT | On-Device STT (SODA) | Whisper Fallback |
|----------------|-----|----------|------------|---------------------|-----------------|
| 6.0 Marshmallow | 23 | Yes | Yes (regular recognizer) | No (requires API 31+) | Yes |
| 7.0–7.1 Nougat | 24–25 | Yes | Yes | No | Yes |
| 8.0–8.1 Oreo | 26–27 | Yes | Yes | No | Yes |
| 9.0 Pie | 28 | Yes | Yes | No | Yes |
| 10 | 29 | Yes | Yes | No | Yes |
| 11 | 30 | Yes | Yes | No | Yes |
| 12 | 31 | Yes | Yes | Yes (if SODA pack installed) | Yes |
| 12L | 32 | Yes | Yes | Yes | Yes |
| 13 | 33 | Yes | Yes | Yes | Yes |
| 14 | 34 | Yes | Yes | Yes + `triggerModelDownload()` | Yes |
| 15+ | 35+ | Should work | Yes | Yes | Yes |

## Required Permissions

| Permission | Purpose | When Requested | Required? |
|-----------|---------|----------------|-----------|
| `RECORD_AUDIO` | Speech recognition (Google STT / Whisper) | When starting teleprompter presentation | Yes — core feature |
| `CAMERA` | Content Creator mode (video recording) | When opening record screen | No — hidden in v4.0 |
| `INTERNET` | Google Fonts loading, Google STT (regular recognizer) | On app launch / STT start | Yes — for fonts; STT works offline with on-device |
| `BLUETOOTH_CONNECT` | Bluetooth microphone/headset support | Implicit with audio | No — passive permission |
| `WRITE_EXTERNAL_STORAGE` | File saving (API ≤ 32 only) | When saving/importing scripts | Yes on older Android |
| `READ_EXTERNAL_STORAGE` | File loading (API ≤ 32 only) | When importing scripts | Yes on older Android |

## Speech Recognition: Device-Specific Behavior

### Works Out of the Box
- **Samsung** (One UI): Google STT regular recognizer works at Stage 3. Tested and confirmed.
- **Google Pixel**: Google STT works. On-device SODA available on API 31+.
- **Most stock Android**: Regular recognizer at Stage 3.

### Known Restrictions
- **Oppo / Realme / OnePlus (ColorOS)**: Google app's `RECORD_AUDIO` restricted to `foreground` via `appops`. All Google STT stages fail:
  - Stage 0–1: On-device SODA returns error 12/13 (language pack not found — SODA packs are separate from Speech Services packs shown in settings).
  - Stage 2–3: Regular recognizer returns error 9 (mic permission denied — ColorOS blocks Google app's background mic access).
  - Auto-fallback to Whisper (if model downloaded, v5.0 feature).
- **Xiaomi / MIUI**: Similar mic restrictions possible. Untested — same fallback chain applies.
- **Huawei (no GMS)**: Google STT unavailable. Whisper fallback only option.

### Speech Services vs SODA Packs
**Important distinction**: The offline speech packs visible in `Settings > Google > Speech Services by Google > Manage Languages` are for the TTS/dictation service's own recognizer. They are **NOT** the same as the SODA packs used by `SpeechRecognizer.createOnDeviceSpeechRecognizer()`. A user may have English downloaded in Speech Services but still get SODA error 13 because the system-level SODA model is not installed or not accessible to third-party apps.

## Flutter & Build Dependencies

| Component | Version |
|-----------|---------|
| **Flutter SDK** | 3.22.3 (stable) |
| **Dart SDK** | 3.4.4 |
| **Kotlin** | 1.9.22 |
| **Gradle** | 8.9 |
| **Android Gradle Plugin (AGP)** | 8.1.0 |
| **NDK** | 27.0.11902837 |
| **Java** | JDK 17 |

## Flutter Package Dependencies

### Core (Required for v4.0)
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.5.1 | State management |
| `shared_preferences` | ^2.3.2 | Settings persistence, auth state, recent scripts |
| `scrollable_positioned_list` | ^0.3.8 | Teleprompter word-by-word scrolling |
| `permission_handler` | ^11.3.1 | Runtime permission requests |
| `wakelock_plus` | ^1.2.8 | Keep screen on during presentation |
| `file_picker` | ^8.1.2 | Script import (TXT, DOCX, RTF) |
| `intl` | ^0.19.0 | Date formatting for recent activity |
| `flutter_animate` | ^4.5.0 | Splash screen and UI animations |
| `flutter_colorpicker` | ^1.1.0 | Color picker in style editor |
| `path_provider` | ^2.1.5 | App directory paths |
| `google_fonts` | ^6.2.1 | Font selection in editor |
| `archive` | ^3.6.1 | DOCX parsing (ZIP extraction) |
| `xml` | ^6.5.0 | DOCX/RTF XML parsing |

### Speech Recognition (Active in v4.0 backend, UI hidden)
| Package | Version | Purpose |
|---------|---------|---------|
| `speech_to_text` | ^7.0.0 | Imported but not directly used — types only (`SpeechResult`, `SpeechStatus`) |
| `whisper_flutter_new` | ^1.0.1 | Whisper.cpp inference for offline STT |
| `record` | ^5.0.0 | Audio recording for Whisper input (PCM 16-bit, 16kHz, mono) |

### Premium Features (Hidden in v4.0, needed for v5.0)
| Package | Version | Purpose |
|---------|---------|---------|
| `camera` | 0.10.5+9 | Content Creator video recording |
| `gal` | ^2.3.2 | Save recorded video to device gallery |
| `network_info_plus` | ^5.0.0 | Get device IP for Remote Control server |
| `web_socket_channel` | ^3.0.3 | Remote Control WebSocket communication |
| `shelf` | ^1.4.1 | Remote Control HTTP server |
| `shelf_router` | ^1.1.4 | Remote Control URL routing |
| `shelf_web_socket` | ^2.0.1 | Remote Control WebSocket handler |

### Dependency Overrides
| Package | Pinned Version | Reason |
|---------|---------------|--------|
| `record_platform_interface` | 1.2.0 | Compatibility fix with `record` ^5.0.0 |

## Native Code (MethodChannel)

| Channel | File | Methods |
|---------|------|---------|
| `autoteleprompter/stt` | `MainActivity.kt` | `isAvailable`, `start`, `stop` → callbacks: `onResult`, `onStatus`, `onError`, `onNeedLanguagePack` |
| `autoteleprompter/clipboard` | `MainActivity.kt` | `setHtml` — sets HTML + plain text to clipboard |
| `autoteleprompter/system` | `MainActivity.kt` | `openSpeechSettings` — opens SODA language pack manager or fallback settings |

## APK Details

| Property | Value |
|----------|-------|
| **Application ID** | `com.autoteleprompter.autoteleprompter` |
| **APK Size** | ~53.4MB (release) |
| **Signing** | Debug keys (not production signed) |
| **Native Architectures** | `armeabi-v7a`, `arm64-v8a`, `x86_64` |
| **Native Libraries** | `libapp.so` (Dart AOT), `libflutter.so` (engine), `libwhisper.so` (whisper.cpp) |

---
*Created: 2026-04-13 — AutoTeleprompter v4.0 Stable Release*
