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
| `Platform_Windows/lib/platform/stt/abstract_stt_service.dart` | Platform-agnostic STT interface, callbacks, status contract, `sttWebViewUrl`, `requiresImmediateListeningFlag`, audio-input device contract |
| `Platform_Windows/lib/platform/stt/stt_service_factory.dart` | Sole adapter factory; Windows returns `SttBrowserAdapter()` for WebView2/Web Speech and audio-input routing |
| `Platform_Windows/lib/platform/stt/stt_desktop_adapter.dart` | Windows native/SAPI adapter wrapping `SpeechService`; preserved fallback/source-present path |
| `Platform_Windows/lib/platform/stt/stt_browser_adapter.dart` | Active Windows WebView2/Web Speech adapter on localhost port 8082, including device enumeration and selected input requests |
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
| `AbstractSttService.setAudioInputDevice(String? deviceId, {String? label})` | Settings/presenter mic selector; empty/null means system default |
| `AbstractSttService.onAudioInputDevicesChanged` | Provider updates `TeleprompterState.audioInputDevices` for the presenter settings panel |
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
| Presentation screen | `teleprompter_screen.dart` | Starts/stops provider session, uses hidden `sttWebViewUrl`, and displays the Windows mic selector |
| Debug panel | `teleprompter_screen.dart` | Reads provider `debugLogs`, `soundLevel`, `statusMessage` |
| Settings provider | `settings_provider.dart` | Persists `sttInputDeviceId` and `sttInputDeviceLabel` consumed before STT start |

---

## Invariants

1. **Factory is the only instantiation point**: Feature code must call
   `SttServiceFactory.create()`. Do not instantiate `SttDesktopAdapter` or
   `SttBrowserAdapter` directly in UI code.

2. **Windows default is WebView2/browser STT**: The factory currently returns
   `SttBrowserAdapter()` for Windows because it supports Web Speech, Hebrew
   recognition, WebView lifecycle reloads, and browser audio-input enumeration.

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
    speakable script word from the requested index, skipping newlines and
    display-only symbols whose `normalized` value is empty.

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

20. **External microphone selection is persisted and best-effort routed**:
    Windows stores `sttInputDeviceId` and `sttInputDeviceLabel`; before
    `startSession(...)`, the provider calls `setAudioInputDevice(...)` on the
    STT adapter. Empty ID means system default input. If WebView2 cannot open the
    selected external mic, the adapter must fall back to system default and log a
    diagnostic rather than failing the whole STT session.

21. **Only the current WebView socket may drive STT state**: Browser STT may
    briefly produce duplicate WebView/WebSocket connections during first load,
    reload, or stop/start. `SttBrowserAdapter` must close replaced socket
    clients, ignore messages from stale clients, and treat stale disconnects as
    non-events so an old WebView cannot poison the active listening session.

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
- Do not let display-only punctuation/symbol tokens control STT locale switches
  or force-skip targets.
- Do not remove the `?session=` reload token from browser STT URLs.
- Do not let Web Speech `onend` and locale-switch handlers both start new
  recognizers for the same language pivot.
- Do not remove `_stopInFlight` or `_sessionToken` restart guards; fast
  stop/start in the same presentation depends on them.
- Do not reset `confirmedWordIndex` from `stopSession()` or from STT adapter
  callbacks.
- Do not remove the system-default microphone fallback; external USB/Bluetooth
  devices can disappear between sessions.
- Do not persist a selected input device without also persisting its human label
  for settings/debug display.
- Do not process WebView STT messages from a socket that is no longer
  `_wsClient`, and do not let a replaced socket's disconnect log or mutate the
  active session.

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
- **Web Speech input routing is browser-owned**: WebView2 exposes
  `navigator.mediaDevices` for enumeration and capture constraints, but final
  speech-recognition routing remains Chromium/Web Speech behavior. The app must
  show the selected device and retain OS-default fallback.
- **Duplicate WebView connects can happen**: WebView2 can connect more than once
  during initial load/reload. The adapter must keep only the most recent socket
  authoritative.

---

## External Microphone Contract

| State | Contract |
|-------|----------|
| System default | Empty `sttInputDeviceId` means the adapter requests `{ audio: true }` and lets Windows/WebView2 choose the default input. |
| Explicit external mic | The presenter settings panel lists discovered WebView2 `audioinput` devices; selecting one persists its `deviceId` and label and sends `setAudioInputDevice` to the active adapter. |
| Runtime switch | If STT is running, changing the selector tells the browser adapter to reopen the visualizer stream with the new device and restart Web Speech without resetting `confirmedWordIndex`. |
| Missing device fallback | If the saved USB/Bluetooth/interface mic is gone, the browser page reports the failure, clears the exact device request, and continues on system default input. |
| Remaining caveat | Web Speech does not expose a direct `MediaStream` parameter; the app can request the selected audio input for WebView capture and diagnostics, while Chromium ultimately controls recognition routing. |

---

## Shared-File Ownership Notes

STT owns speech lifecycle and callback sections in `teleprompter_provider.dart`.
Teleprompter Engine owns confirmed index, force-skip, fluid advance, and visual
rendering. Settings owns `sttEngine` persistence; STT only consumes it.
