---
name: STT MVP
type: component
platform: Windows
last_updated: 2026-04-28
---

# STT MVP - Windows

Governs the Windows speech-recognition pipeline: adapter selection, native SAPI
and browser fallback adapters, callback wiring, session lifecycle interaction
with `TeleprompterNotifier`, and word-alignment input. The teleprompter engine
owns how confirmed indices are rendered after STT produces results.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/platform/stt/abstract_stt_service.dart` | Platform-agnostic STT interface, callbacks, status contract, `sttWebViewUrl`, `requiresImmediateListeningFlag` |
| `Platform_Windows/lib/platform/stt/stt_service_factory.dart` | Sole adapter factory; Windows must return `SttDesktopAdapter()` unless explicitly changing engine strategy |
| `Platform_Windows/lib/platform/stt/stt_desktop_adapter.dart` | Windows native/SAPI adapter wrapping `SpeechService` |
| `Platform_Windows/lib/platform/stt/stt_browser_adapter.dart` | Dormant WebView2/Web Speech adapter on localhost port 8082 |
| `Platform_Windows/lib/platform/stt/stt_apple_adapter.dart` | Source-present Apple adapter; not a Windows runtime path |
| `Platform_Windows/lib/platform/stt/stt_android_adapter.dart` | Source-present Android adapter; not a Windows runtime path |
| `Platform_Windows/lib/features/teleprompter/services/speech_service.dart` | `speech_to_text` wrapper, `SpeechResult`, `SpeechStatus`, locale/error/status callbacks |
| `Platform_Windows/lib/features/teleprompter/services/native_speech_service.dart` | Android-native legacy service present in Windows tree; do not wire into Windows factory |
| `Platform_Windows/lib/features/teleprompter/services/whisper_speech_service_native.dart` | Dormant Whisper path; build-sensitive on Windows |
| `Platform_Windows/lib/features/teleprompter/services/word_aligner.dart` | Alignment helper consuming STT transcripts and script words |
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | `_sttService`, `_setupSttCallbacks`, `_setupWhisperCallbacks`, `startSession`, `stopSession`, locale switching, callback guards |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `SttServiceFactory.create()` | `TeleprompterNotifier.build()` |
| `AbstractSttService.start({String? localeId})` | `TeleprompterNotifier.startSession()` |
| `AbstractSttService.stop()` | `stopSession()` and provider disposal |
| `AbstractSttService.setLocale(String)` | Dynamic bilingual switching heartbeat |
| `AbstractSttService.onResult` | `_setupSttCallbacks()` forwards to `_handleSttResult()` |
| `onStatusChange`, `onError`, `onSoundLevelChange`, `onLanguageUnavailable`, `onDiagnostic` | `_setupSttCallbacks()` |
| `AbstractSttService.sttWebViewUrl` | `TeleprompterState.sttWebViewUrl` for browser adapter |
| `requiresImmediateListeningFlag` | Startup guard behavior in `startSession()` |
| `WordAligner.align(...)` | `_handleSttResult()` |
| `_stopInFlight` / `_sessionToken` | Provider-internal restart serialization and stale-callback rejection |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Teleprompter provider build | `teleprompter_provider.dart` | Creates adapter through `SttServiceFactory.create()` |
| Session start | `teleprompter_provider.dart` | Calls `start(localeId: ...)`, reads success and actual locale |
| Session stop/dispose | `teleprompter_provider.dart` | Calls `_sttService.stop()` |
| Bilingual heartbeat | `teleprompter_provider.dart` | Calls `_sttService.setLocale(upcomingLocale)` |
| Presentation screen | `teleprompter_screen.dart` | Starts/stops provider session, may use `sttWebViewUrl` for browser STT UI |
| Debug panel | `teleprompter_screen.dart` | Reads provider `debugLogs`, `soundLevel`, `statusMessage` |

---

## Invariants

1. **Factory is the only instantiation point**: Feature code must call
   `SttServiceFactory.create()`. Do not instantiate `SttDesktopAdapter` or
   `SttBrowserAdapter` directly in UI code.

2. **Windows default is native desktop adapter**: The factory currently returns
   `SttDesktopAdapter()` for Windows. Browser STT is preserved but dormant.

3. **Callback guards are mandatory**: Every STT callback in
   `teleprompter_provider.dart` must return immediately when `_disposed` or
   `_sessionStopped` is true.

4. **Stop disables future mutation**: `stopSession()` sets `_sessionStopped=true`
   before awaiting adapter stops. Pending callbacks must not update state.

5. **Browser STT port is 8082**: `SttBrowserAdapter` owns localhost port `8082`.
   Remote Control owns port `8080`; do not merge them.

6. **Adapter callback shape is stable**: All adapters must surface results via
   `SpeechResult`, statuses via `SpeechStatus`, and errors as raw strings.

7. **Windows `requiresImmediateListeningFlag` is false for native SAPI**:
   `SttDesktopAdapter` relies on normal status callbacks. Only browser/Apple
   style async startup paths should set this true.

8. **Voice commands precede alignment**: `_handleSttResult()` must check voice
   commands before calling `WordAligner.align()`.

9. **Locale separators are adapter-sensitive**: Provider locales use underscore
   style (`he_IL`, `en_US`); browser adapter converts to hyphen style for Web
   Speech (`he-IL`, `en-US`).

10. **Whisper remains dormant unless explicitly selected**: Windows build history
    marks Whisper as dependency-sensitive. Do not activate it casually.

11. **Browser STT dashboard is headless when Flutter owns the visualizer**:
    `teleprompter_screen.dart` may keep the WebView2 STT page mounted at a
    1x1 transparent render target so microphone/Web Speech processing stays
    alive, but the visible grey dashboard chrome must not remain above the
    debug console when the Flutter sound bar is the canonical visualizer.

12. **Locale pivots must produce a new listening callback**: Browser STT
    `setLocale()` resets its `_everListened` guard before sending the locale
    command so the restarted Web Speech recognizer can report `listening` again
    and clear the provider `isStarting` state.

13. **Sound level telemetry is UI state, not log spam**: Once the Flutter sound
    bar is mounted, `onSoundLevelChange` may update `TeleprompterState.soundLevel`
    and silent-mic timestamps, but must not append recurring `VOL: [...]` rows to
    `debugLogs`.

14. **Mixed-language switching follows the next expected word**: Windows STT
    must not switch locale from a broad Hebrew/English ratio while English words
    are still next in sequence. `_detectLanguageAhead()` follows the next
    non-newline script word from the requested index.

15. **Browser STT sessions must reload the WebView**: Every browser-STT
    `start()` increments a session id and exposes `sttWebViewUrl` with a
    `?session=` query. The presentation screen must clear `_loadedWebViewUrl`
    when provider state clears `sttWebViewUrl`, otherwise a stop/start cycle can
    leave WebView2 connected to a stale page and the next mic start will fail.

16. **Locale switch has exactly one restart path**: The Web Speech page may
    abort the current recognizer to switch language, but `onend` must not also
    schedule a second restart while the explicit locale-switch timer is pending.

17. **Stop/start in one presentation is supported**: Pressing mic stop pauses
    recognition, not the presentation session. A later mic start in the same
    screen must wait for any previous stop teardown, preserve
    `confirmedWordIndex`, and create a fresh recognizer at that resume point.

18. **STT teardown is serialized**: `_stopInFlight` must be awaited before
    `startSession(...)` constructs a new recognition session. `_sessionToken`
    must reject stale async start/status callbacks that complete after a newer
    stop or start.

19. **Stop preserves position**: `stopSession()` may clear transient transcript,
    no-progress counters, sound level, startup flags, and WebView URL state, but
    it must not reset `confirmedWordIndex`. Only the explicit restart/reset
    control may return the text to index `0`.

20. **External microphone status is currently OS-owned**: Until an explicit
    input-device selector is implemented, Windows STT uses the microphone chosen
    by Windows/WebView/native speech as the default input device. MVP docs and UI
    must not claim in-app external mic selection exists yet.

---

## Forbidden Changes

- Do not wire Android `NativeSpeechService` into Windows factory.
- Do not replace factory-based adapter creation with UI-level platform checks.
- Do not remove `_sessionStopped`, `_disposed`, or `_safeSetState` guards.
- Do not reuse port `8082` for Remote or other services.
- Do not enable browser STT or Whisper by default without explicit user scope and
  build verification.
- Do not make `setLocale()` perform provider-level stop/start chains; adapters
  own their own hot-switch behavior.
- Do not restore the visible WebView2 dashboard box after the Flutter sound bar
  has replaced it; keep the WebView mounted invisibly instead.
- Do not reintroduce recurring volume-bar debug rows while the sound bar exists.
- Do not pivot to Hebrew based only on a distant lookahead ratio when the next
  expected speakable word is still English.
- Do not remove the `?session=` reload token from browser STT URLs.
- Do not let Web Speech `onend` and locale-switch handlers both start new
  recognizers for the same language pivot.
- Do not remove `_stopInFlight` or `_sessionToken` restart guards; fast
  stop/start in the same presentation depends on them.
- Do not reset `confirmedWordIndex` from `stopSession()` or from STT adapter
  callbacks.
- Do not document explicit external mic selection as implemented until the
  platform can enumerate/select/persist input devices in app.

---

## Known Fragilities

- **Windows privacy settings**: Native SAPI/speech recognition depends on Windows
  Speech and microphone/privacy settings outside Flutter.
- **Browser fallback permissions**: WebView2 microphone permission may require
  preference pregrant or user action.
- **Mixed adapter remnants**: Android, Apple, browser, desktop, and Whisper files
  exist in the Windows tree due platform split history; only the factory mapping
  decides the active Windows path.
- **Callback timing differs by adapter**: Browser STT can require immediate UI
  listening state, while native desktop adapter should not.
- **Mixed-language boundary timing**: Hebrew/English transitions must not wait
  solely for the 5-second heartbeat. Provider-side boundary waits may request a
  locale switch immediately while preserving `confirmedWordIndex`.
- **Fast stop/start race**: Browser/WebView/native recognizers can finish
  teardown after the user has already pressed mic again. Restart serialization is
  required so the old stop cannot poison the new session.
- **External mic routing gap**: Connected USB/Bluetooth/interface microphones
  can work when selected as the OS default input, but there is no guaranteed
  in-app microphone picker/status contract yet.

---

## External Microphone Contract Gap

| State | Contract |
|-------|----------|
| Current Windows behavior | STT uses the active OS/WebView/native default microphone. External microphones are expected to work when Windows routes the default input to them. |
| Not yet implemented | In-app enumeration, active device display, USB/Bluetooth/interface device picker, and persisted preferred microphone. |
| Required future behavior | Add a device-selection layer before `startSession(...)` so STT starts with an explicitly chosen input device when the platform API allows it, otherwise surface a clear OS-default fallback message. |

---

## Shared-File Ownership Notes

STT owns speech lifecycle and callback sections in `teleprompter_provider.dart`.
Teleprompter Engine owns confirmed index, force-skip, fluid advance, and visual
rendering. Settings owns `sttEngine` persistence; STT only consumes it.
