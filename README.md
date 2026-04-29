# AutoTeleprompter — 4-Platform Monorepo

A professional teleprompter app for iOS, Android, macOS, and Windows.
Each platform is a fully independent Flutter project — zero shared code, zero cross-dependencies.

---

## Repository Structure

```
AutoTeleprompter/               ← repo root
│
├── Platform_iOS/               ← iOS Flutter project (Xcode / App Store)
│   └── AutoTeleprompter/
│       ├── lib/                ← Dart source (iOS-specific)
│       ├── ios/                ← Xcode native project
│       └── pubspec.yaml
│
├── Platform_Android/           ← Android Flutter project (Gradle / Play Store)
│   └── AutoTeleprompter/
│       ├── lib/                ← Dart source (Android-specific)
│       ├── android/            ← Gradle native project
│       └── pubspec.yaml
│
├── Platform_macOS/             ← macOS Flutter project (Xcode)
│   ├── lib/                    ← Dart source (macOS-specific)
│   ├── macos/                  ← Xcode native project
│   └── pubspec.yaml
│
├── Platform_Windows/           ← Windows Flutter project (CMake / MSVC)
│   ├── lib/                    ← Dart source (Windows-specific)
│   ├── windows/                ← CMake/MSVC native project
│   └── pubspec.yaml
│
└── .github/
    └── workflows/
        ├── build-ios.yml       ← iOS CI (runs on macOS runner)
        ├── build-android.yml   ← Android CI (runs on ubuntu runner)
        ├── build-macos.yml     ← macOS CI (runs on macOS runner)
        └── build-windows.yml   ← Windows CI (runs on windows runner)
```

---

## Platform Rules — What Goes Where

| Belongs in git | Does NOT belong in git |
|---|---|
| `lib/` Dart source | `ios/` inside a non-iOS platform |
| Platform native dir (`ios/`, `android/`, `macos/`, `windows/`) | `macos/` inside a non-macOS platform |
| `pubspec.yaml`, `pubspec.lock` | `android/` inside a non-Android platform |
| `analysis_options.yaml` | `web/` inside any platform |
| `README.md` | `_agent/`, `.claude/` (AI workflow files) |
| `.gitignore`, `.metadata` | `backups/`, `releases/`, `schemes/`, `test/` |
| | `AI_PROTOCOL.md`, `DAILY_LOG.md`, `MASTER_TODO*.md` |
| | Nested `.github/` inside a platform folder |

**The only `.github/workflows/` folder is at the repo root.** Never create a `.github/` folder inside a platform directory.

---

## CI/CD — Platform Isolation

Each workflow is path-filtered so it only triggers on its own platform's changes:

| Workflow | Trigger paths | Runner |
|---|---|---|
| `build-ios.yml` | `Platform_iOS/**` | `macos-latest` |
| `build-android.yml` | `Platform_Android/**` | `ubuntu-latest` |
| `build-macos.yml` | `Platform_macOS/**` | `macos-latest` |
| `build-windows.yml` | `Platform_Windows/**` | `windows-latest` |

**Important:** Push one platform per `git push`. If you push multiple platforms in one push, GitHub evaluates the paths filter against only the last commit — earlier platform commits may be missed.

---

## Platform Versions

| Platform | Version | Status |
|---|---|---|
| iOS | v4.1.4 | Sealed |
| Android | v4.0 | Sealed |
| macOS | v4.1 | Active |
| Windows | v4.1.12 | Sealed |

---

## Installing Builds

**iOS** — Download the `.ipa` artifact from GitHub Actions → install via Sideloadly.

**Android** — Download the `.apk` artifact from GitHub Actions → install directly on device.

**macOS** — Download the `.zip` artifact from GitHub Actions → unzip and run.

**Windows** — Download the `.zip` artifact from GitHub Actions → unzip and run `autoteleprompter.exe`.
---

## Windows v4.1.12 Sealed Baseline (2026-04-29)

Windows v4 is sealed at `Platform_Windows/pubspec.yaml` version `4.1.12+12`
and workflow title `Build Windows EXE (v4.1.12)`. Final backup:
`backups/final_windows_v4/20260429_103357`.

Migration-critical Windows behavior now ready to port to iOS, Android, and
macOS:

- STT stop/start resumes from the current reading position; only Restart resets
  to word `0`.
- Present-mode bookmarks are shared with editor mode, support multiple anchors,
  visible markers, explicit remove buttons, and active-STT bookmark jumps.
- Present-mode search and editor search jump to visible text locations rather
  than raw markup offsets.
- Active STT owns presenter scrolling; stopped STT allows browsing and resume
  point selection.
- Smooth STT follow uses row-progress motion; direct commands such as search,
  bookmark previous/next, tap, and restart jump immediately.
- External microphone selection is implemented through the Windows WebView2 STT
  path with System Default fallback.
- Debug mode includes a collapsible debug output window and a mounted sound bar;
  recurring volume debug rows are intentionally suppressed.
- Font size has one source of truth across editor metadata, presenter settings,
  style tags, and export. Presenter may render larger for readability, but it
  must not save the enlarged display value.
- Line, word, and letter spacing ranges are synchronized between editor and
  presenter controls.
- Export converts internal markup into document styling for RTF/DOCX and writes
  visible text only for plain formats. App-private tags must not leak into saved
  files.
- Standalone symbols, quotes, punctuation, and intentional blank lines must be
  preserved in editor, presenter, import, and export paths.

Before starting V5 or porting this baseline, split oversized editor/presenter
files as behavior-preserving refactors. Current files above the preferred
1000-line limit include `script_editor_screen.dart` and
`teleprompter_screen.dart` on every platform; Windows currently has the largest
versions at 2885 and 2528 lines.

---

## Windows v4.1.12 Final User-Verified Handoff (2026-04-29)

Correction to the earlier pre-split note above: Windows has now completed the
behavior-preserving V5-prep split. Every Dart file under `Platform_Windows/lib`
is below 800 lines. The largest current Windows source files are:

| File | Lines |
|---|---:|
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.build.dart` | 720 |
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | 717 |
| `Platform_Windows/lib/features/settings/providers/settings_provider.dart` | 700 |
| `Platform_Windows/lib/features/teleprompter/services/word_aligner.dart` | 660 |
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | 641 |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | 579 |

Latest verified Windows v4 commit: `160d137`.
Verified workflow run: `Build Windows EXE (v4.1.12)` / `25110648732`.
Final-ready backup target:
`backups/Final Sealed Versions/windows_v4.1.12_FINAL-Ready_for_v5_Development_20260429_202903.tar`.

Final migration-critical rules for iOS and future V5:

- Default STT can recover locally up to 5 missed words.
- Longer visible skips are opt-in, bounded to rendered on-screen text, and
  fallback-only after nearby 3+ word phrase priority fails.
- Active STT owns scrolling; stopped STT allows browsing and resume selection.
- Bookmarks/search/restart/direct navigation jump immediately.
- Bookmarks, font metadata, spacing, symbol/blank-line preservation, external
  mic policy, and markup-safe export must be ported platform-by-platform under
  the matching `_agent/mvp/Platform_*` contracts.
