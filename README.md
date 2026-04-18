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
| Windows | v4.1.x | Active development |

---

## Installing Builds

**iOS** — Download the `.ipa` artifact from GitHub Actions → install via Sideloadly.

**Android** — Download the `.apk` artifact from GitHub Actions → install directly on device.

**macOS** — Download the `.zip` artifact from GitHub Actions → unzip and run.

**Windows** — Download the `.zip` artifact from GitHub Actions → unzip and run `autoteleprompter.exe`.
