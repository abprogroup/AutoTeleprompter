---
name: STT MVP
type: component
platform: macOS
last_updated: 2026-04-27
---

# STT MVP - macOS

Governs macOS speech-recognition lifecycle, Apple adapter selection, speech
callbacks, optional Whisper path, and the word-alignment feedback loop that
advances the teleprompter.

## Owned Files

| File | Role |
|------|------|
| `Platform_macOS/lib/platform/stt/abstract_stt_service.dart` | Platform-agnostic STT contract and callbacks |
| `Platform_macOS/lib/platform/stt/stt_service_factory.dart` | Factory selecting Apple adapter on macOS |
| `Platform_macOS/lib/platform/stt/stt_apple_adapter.dart` | Adapter around `SpeechService` for SFSpeechRecognizer |
| `Platform_macOS/lib/platform/stt/stt_desktop_adapter.dart` | Desktop fallback source present; not primary macOS path |
| `Platform_macOS/lib/platform/stt/stt_android_adapter.dart` | Android adapter source present; not macOS runtime path |
| `Platform_macOS/lib/features/teleprompter/services/speech_service.dart` | `speech_to_text`/Apple speech wrapper |
| `Platform_macOS/lib/features/teleprompter/services/native_speech_service.dart` | Android-native service source present; not macOS runtime path |
| `Platform_macOS/lib/features/teleprompter/services/whisper_speech_service_native.dart` | Optional/dormant Whisper offline path |
| `Platform_macOS/lib/features/teleprompter/services/word_aligner.dart` | Fuzzy alignment of transcript to script words |
| `Platform_macOS/lib/features/teleprompter/models/alignment_result.dart` | Alignment/teleprompter state model |
| `Platform_macOS/lib/features/teleprompter/providers/teleprompter_provider.dart` | STT callbacks, session lifecycle, result handling |
| `Platform_macOS/lib/platform/permissions/platform_permissions.dart` | macOS speech permission gate |

## External API

| Method / Field | Caller |
|----------------|--------|
| `SttServiceFactory.create()` | `TeleprompterNotifier` |
| `AbstractSttService.start({localeId})` | STT session start |
| `AbstractSttService.stop()` / `pause()` / `resume()` | Teleprompter lifecycle |
| `AbstractSttService.setLocale(String)` | Language switch paths |
| `onResult`, `onStatusChange`, `onError`, `onSoundLevel` | Teleprompter callbacks |
| `WordAligner.align(...)` | Result handler |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Teleprompter provider | `teleprompter_provider.dart` | Creates service, starts/stops session, consumes callbacks |
| Teleprompter screen | `teleprompter_screen.dart` | Starts/stops via provider and shows errors |
| Platform permissions | `platform_permissions.dart` | Gates Apple speech permission |
| Settings provider | `settings_provider.dart` | Supplies STT engine/debug settings |

## Invariants

1. macOS factory must choose `SttAppleAdapter`; feature code uses
   `AbstractSttService`.
2. Callbacks must be ignored after stop/dispose.
3. Voice commands are processed before alignment.
4. Locale/engine switches must not create overlapping active sessions.
5. Whisper path is dormant unless explicitly selected/restored.
6. Android/desktop adapter files are source-present but not macOS runtime owners.

## Forbidden Changes

- Do not instantiate `SpeechService` or adapters directly from UI.
- Do not bypass macOS speech permission checks before starting STT.
- Do not make macOS use Android native speech code.
- Do not activate Whisper fallback without settings and dependency review.

## Known Fragilities

- macOS SFSpeech authorization can fail asynchronously.
- Callback timing can lag UI lifecycle.
- Whisper service is present but dormant and dependency-sensitive.
- Word aligner can false-positive on very short words.

## Shared-File Ownership Notes

STT owns adapter callbacks and result handling in `teleprompter_provider.dart`;
Teleprompter Engine owns visual advancement state after alignment.

## 2026-05-04 Windows 385911e Parity Port

macOS received the Windows/iOS STT contract shape without receiving
Windows-only runtime behavior:

- `AbstractSttService` includes optional input-device and browser-URL hooks so
  shared provider code can compile, but Apple-native adapters leave those as
  no-ops/null.
- `SttServiceFactory` still returns `SttAppleAdapter` for macOS.
- `WordAligner.align(...)` now accepts the visible-skip cap used by the
  presenter visible-text-skip feature and default safe local recovery.
- Missing-language and permission dialogs are macOS-safe; they do not open
  Windows Settings, do not mention WebView2, and do not offer Windows speech
  pack actions.

Any future Windows mic-selector/WebView STT work must remain excluded from
macOS unless a native macOS equivalent is explicitly designed.

## 2026-05-05 Windows v4.1.14 Transfer Pending

Windows v4.1.14 added verified STT behavior after this macOS parity pass:
full visible-window skip repair, trusted visible phrase jumps, faster but safer
locale assist, and strict bullet/improvisation relock. The port plan lives in
`_agent/mvp/Platform_macOS/windows_v4_1_14_transfer_packet.md`.

macOS should port the behavior model only:

- `WordAligner` visible-skip and strict-bullet thresholds.
- Provider-side trusted visible match handling and improvisation no-match
  suppression.
- Apple-safe locale assist/pin behavior.
- Presenter setting for strict bullet/header prompting.

macOS must not port Windows WebView2/browser STT or Windows microphone picker
internals.

## 2026-05-05 Windows v4.1.14 STT Port Implemented

macOS now carries the Windows v4.1.14 behavior model while keeping Apple STT:

- Full visible-window phrase/sequence matching for visible skip.
- Conservative local recovery when visible skip is off.
- Strict bullet/header mode for presenter users who improvise between visible
  headings.
- Provider-side trusted visible-match cap bypass and improvisation no-match
  suppression.
- Apple-safe `setLocale(...)` restart path through `SttAppleAdapter` and
  `SpeechService`, with stale-result guarding during language switches.

Still excluded: Windows WebView2 STT, Windows mic selector UI, Windows
speech-pack dialogs, and Windows-specific environment/settings actions.
