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
---

## Current Platform Separation Note (Added 2026-04-29)

This document contains older shared-codebase language. The active repository
protocol is the root `README.md`, `AI_PROTOCOL.md`, and `_agent/mvp/README.md`:
each `Platform_*` folder is an isolated Flutter project, and platform changes
must stay inside the active platform unless the user explicitly requests a port.

Windows v4 is sealed at `4.1.12+12`. Its behavior is now the migration source
for the remaining platforms:

- STT stop/start resumes from current position; only Restart resets to the
  beginning.
- Bookmarks sync between editor and presenter and work while STT is active.
- Search jumps to visible text locations, not hidden markup offsets.
- Active STT controls presenter scrolling; stopped STT allows browsing and
  resume point selection.
- One font-size metadata value is shared across editor, presenter, style tags,
  and export.
- Spacing controls, blank-line preservation, symbol preservation, external mic
  handling, debug UI, and markup-safe export are now Windows baseline behavior.

Refactor gate before V5 expansion: every platform has editor/presenter screens
above the preferred 1000-line limit. Split them only as behavior-preserving,
platform-local refactors after reading the relevant MVP docs.

## Windows v4 Final Handoff Update (Added 2026-04-29)

Windows v4.1.12 is user verified and complete. The active Windows baseline is
commit `160d137`, with successful workflow run `25110648732`.

Windows has already completed the behavior-preserving editor/presenter split
that the earlier note described as future work. Every Dart file under
`Platform_Windows/lib` is below 800 lines. The remaining split/refactor gate now
applies to iOS, Android, and macOS before major V5 feature work.

The Windows behavior to migrate is platform behavior, not shared source code:

- STT stop/start resumes current position; Restart is the only reset.
- Default STT local recovery allows up to 5 missed words.
- Longer STT skips require the opt-in visible-skip setting, must remain inside
  the rendered viewport, and must prefer nearby 3+ word phrase matches first.
- Bookmarks, search, scroll behavior, font metadata, spacing, blank-line/symbol
  preservation, external mic policy, and markup-safe export must each be ported
  through the target platform's MVP docs.

Next active platform is iOS. Keep all implementation inside `Platform_iOS/`
unless the user explicitly requests a cross-platform port.
