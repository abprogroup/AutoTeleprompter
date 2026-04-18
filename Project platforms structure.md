# AutoTeleprompter — Platform Structure

## Overview

AutoTeleprompter is a single Flutter project that builds natively for four
platforms: **Android**, **iOS**, **macOS**, and **Windows (PC)**.

All platforms share one codebase. Platform-specific behavior is isolated
in a dedicated `lib/platform/` layer.

**Total Separation Protocol (CI/CD Hot-Patching):**
To ensure `pubspec.yaml` plugin requirements (like Windows C++ limitations vs iOS/Android features) do not contaminate or break each other, this project uses **Build-Time Cloud Patching**:
- The permanent `pubspec.yaml` is optimized for the **Mobile Baseline** (Android/iOS).
- Desktop builds (e.g., Windows via GitHub Actions) dynamically strip out incompatible mobile plugins before compiling.
- This guarantees zero risk to the shared `.dart` source code while achieving 100% platform isolation at release time.

---

## Folder Structure

```
AutoTeleprompter/                        ← project root
│
├── AutoTeleprompter/                    ← Flutter project (all 4 platforms)
│   ├── android/                         ← Android native layer (Gradle)
│   ├── ios/                             ← iOS native layer (Xcode / CocoaPods)
│   ├── macos/                           ← macOS native layer (Xcode / CocoaPods)
│   ├── windows/                         ← Windows native layer (CMake)  [future]
│   │
│   └── lib/
│       ├── main.dart                    ← Entry point — calls PlatformPermissions.requestAll()
│       ├── app.dart                     ← Shared app shell (routing, theme)
│       │
│       ├── platform/                    ← ★ PLATFORM LAYER — one folder per feature ★
│       │   ├── stt/                     ← Speech-to-Text service per platform
│       │   │   ├── abstract_stt_service.dart    ← common interface
│       │   │   ├── stt_android_adapter.dart     ← Android: Google on-device STT
│       │   │   ├── stt_apple_adapter.dart       ← iOS + macOS: Apple SFSpeechRecognizer
│       │   │   ├── stt_desktop_adapter.dart     ← Windows: Windows SAPI via speech_to_text
│       │   │   └── stt_service_factory.dart     ← creates the right adapter at runtime
│       │   │
│       │   ├── file_import/             ← Supported import formats per platform
│       │   │   └── platform_file_import.dart    ← extensions list + dialog label
│       │   │
│       │   └── permissions/             ← OS permission requests per platform
│       │       └── platform_permissions.dart    ← requestAll() called at app start
│       │
│       ├── features/                    ← Shared feature code (platform-agnostic)
│       │   ├── script/                  ← Script editing + file import
│       │   ├── teleprompter/            ← Teleprompter playback + STT routing
│       │   ├── settings/                ← App settings
│       │   ├── auth/                    ← Authentication
│       │   ├── splash/                  ← Splash screen
│       │   └── remote/                  ← Remote control service
│       │
│       ├── core/                        ← Shared utilities (extensions, widgets, services)
│       └── shared/                      ← Shared models / helpers
│
├── Project backup for android stable development/  ← Stable Android baseline snapshot
│   └── AutoTeleprompter/                ← Flutter project as of Android-stable state
│
├── releases/                            ← Built IPA / APK artifacts
├── development/                         ← Dev notes and spike work
├── guidelines_and_planning/             ← Product planning docs
├── schemes/                             ← Build schemes / CI config
│
├── AI_PROTOCOL.md                       ← AI session rules and directives
├── DAILY_LOG.md                         ← Append-only development log
├── MASTER_TODO_V4.md                    ← Task list v4
├── MASTER_TODO_V5.md                    ← Task list v5
└── README.md                            ← Project overview
```

---

## Platform → Feature Mapping

| Feature | Android | iOS | macOS | Windows |
|---|---|---|---|---|
| STT Engine | Google on-device (NativeSpeechService) | Apple SFSpeechRecognizer | Apple SFSpeechRecognizer | Windows SAPI (speech_to_text) |
| File import: .pages | No | Yes | Yes | No |
| Permissions at launch | No-op (system handles) | Mic + Speech request | Mic + Speech request | No-op |
| Keyboard "Done" bar | No | Yes | No (desktop keyboard) | No (desktop keyboard) |
| Build artifact | .apk / .aab | .ipa | .app | .exe |

---

## Development Rules

1. **Never add `Platform.isXxx` checks inside `lib/features/` code.**
   All platform branching belongs in `lib/platform/`.

2. **To add a platform-specific feature:**
   - Add an abstract method or getter to the relevant `lib/platform/` interface
   - Add the implementation in the platform-specific adapter/file
   - Call it from feature code via the interface — no platform checks needed there

3. **The Android baseline backup** (`Project backup for android stable development/`)
   preserves the last known-good Android state. Use it as a reference when
   Android regressions need to be investigated.

4. **macOS shares the Apple STT adapter with iOS** (`stt_apple_adapter.dart`).
   Both use Apple's SFSpeechRecognizer — minimal divergence expected.

5. **Windows support** requires `flutter create --platforms=windows .` to generate
   the `windows/` native layer. The Dart platform layer (`stt_desktop_adapter.dart`,
   `platform_file_import.dart`, `platform_permissions.dart`) is already in place.

---

## Build Targets

| Platform | How to build | Output |
|---|---|---|
| iOS | GitHub Actions (free) → Sideloadly | `.ipa` in `releases/` |
| Android | `flutter build apk` or GitHub Actions | `.apk` |
| macOS | `flutter build macos` on a Mac | `.app` |
| Windows | `flutter build windows` on Windows | `.exe` |
