---
name: Platform Shell MVP
type: component
platform: iOS
last_updated: 2026-05-02
---

# Platform Shell MVP - iOS

Governs iOS app boot, ProviderScope/App shell, splash route, platform
permissions, platform keyboard helper, import format helper, and platform STT
factory boundaries that must remain outside feature-specific business logic.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/main.dart` | Flutter binding/app boot and root `ProviderScope` |
| `Platform_iOS/lib/app.dart` | Root `AutoTeleprompterApp`, theme, routing shell |
| `Platform_iOS/lib/features/splash/widgets/splash_screen.dart` | Startup splash/navigation shell |
| `Platform_iOS/lib/platform/permissions/platform_permissions.dart` | Speech permission checks and iOS/macOS SFSpeech authorization trigger |
| `Platform_iOS/ios/Runner/AppDelegate.swift` | Native MethodChannel for `AVAudioSession` input route listing/selection |
| `Platform_iOS/lib/platform/keyboard/platform_keyboard.dart` | Platform keyboard helper |
| `Platform_iOS/lib/platform/file_import/platform_file_import.dart` | Platform import format list |
| `Platform_iOS/lib/platform/stt/stt_service_factory.dart` | Platform STT adapter selection |
| `Platform_iOS/lib/core/extensions/string_extensions.dart` | Shared string helpers |

## External API

| Method / Field | Caller |
|----------------|--------|
| `main()` | Runtime entry point |
| `AutoTeleprompterApp` | Root widget |
| `V3SplashScreen` | App route/startup flow |
| `PlatformPermissions.requiresSpeechPermissionCheck` | Teleprompter start flow |
| `PlatformPermissions.ensureSpeechPermission()` | Teleprompter permission gate |
| `PlatformKeyboard` helpers | Editor/text input surfaces |
| `PlatformFileImport` | File I/O MVP |
| `SttServiceFactory.create()` | STT MVP |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Flutter runtime | `main.dart` | Starts app |
| App shell | `app.dart` | Provides root Material app/routing |
| Teleprompter screen | `teleprompter_screen.dart` | Calls permission helpers |
| File I/O | Import/editor files | Reads platform extension list |
| STT provider | `teleprompter_provider.dart` | Uses factory-created STT service |

## Invariants

1. Platform-specific checks stay in `platform/*`, not feature widgets.
2. iOS speech permission checks must trigger the Apple speech authorization path.
3. Root ProviderScope must wrap app state.
4. Splash/navigation must not erase settings or auth state.
5. STT factory is the only adapter creation point.

## Forbidden Changes

- Do not instantiate STT adapters directly in feature code.
- Do not scatter `Platform.isIOS` checks through editor/teleprompter code when
  platform helpers can own the decision.
- Do not bypass speech permission checks before starting iOS STT.
- Do not change boot routing without documenting affected MVP callers.

## Known Fragilities

- iOS permissions can fail asynchronously or remain denied after Settings changes.
- Root app and splash changes affect every feature.
- Platform helpers are shared contracts across feature MVPs.

## Shared-File Ownership Notes

Platform Shell owns boot and platform helper boundaries; feature MVPs own the
business behavior that calls those helpers.

---

## iOS External Microphone Platform Policy - 2026-05-02

- Platform Shell owns microphone and speech permission boundaries through
  `PlatformPermissions.requestAll()` and
  `PlatformPermissions.requiresSpeechPermissionCheck`.
- iOS external microphone support is route-preference based in v4: the app
  requests microphone/speech permission, then the native channel lists
  `AVAudioSession.availableInputs` and applies `setPreferredInput(...)`.
- Platform Shell must not add feature-level `Platform.isIOS` mic-routing hacks
  inside editor or presenter widgets.
- The MethodChannel boundary is `autoteleprompter/ios_audio_input`. It must
  stay platform-owned and must not leak `AVAudioSession` calls into widgets.
- Do not implement iOS mic selection by copying Windows WebView2
  browser-device logic.
