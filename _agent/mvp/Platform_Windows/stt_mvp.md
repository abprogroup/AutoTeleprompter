---
name: STT MVP
type: component
platform: Windows
last_updated: 2026-04-29
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
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.session_stt.dart` | Extracted presenter STT start/stop, WebView loading, keyboard shortcut, remote session UI, and teardown methods after V5 file split |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.audio_debug_widgets.dart` | Extracted sound bar and STT starting indicator widgets after V5 file split |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.settings_panel.dart` | Presenter settings section that exposes Windows speech input selector |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.settings_widgets.dart` | Windows mic selector helper widget |

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

## Visible Skip Contract

| State | Contract |
|-------|----------|
| Default | `AppSettings.sttVisibleSkipEnabled` is false. STT alignment may recover locally up to 5 words for missed recognizer output, but must not jump to a later paragraph/section just because that phrase was spoken. |
| Strict progress | With visible skipping disabled, `WordAligner.align(...)` may scan only the next local 5-word recovery window. This preserves normal teleprompter flow when STT misses one or two words. |
| Visible skip enabled | When enabled, the presenter supplies the current rendered visible word window. STT may scan the full visible viewport, not just the old 1-2 row / 30-word safety window. |
| Nearby phrase priority | Visible skip is a fallback, not the first answer. Before jumping to a farther visible phrase, `WordAligner.align(...)` must prefer a strong nearby 3+ word phrase match inside the local phrase-priority window. |
| Safety cap | The visible window is an upper bound, not permission for unrestricted jumps. Single-word matches stay near-range only; longer visible jumps require multi-word sequence confirmation and aligner confidence checks. |
| Display-only tokens | Newlines, punctuation-only markers, and unspeakable display symbols must not expand the skip window or become skip targets. |

### 2026-05-05 Strict Bullet/Header Mode

- `AppSettings.sttStrictBulletMode` is false by default and is exposed only as
  an explicit Windows presenter setting.
- Strict mode is for bullet/header prompting, where the presenter may speak a
  heading or section cue rather than every word in the script.
- Strict mode keeps WebView2 STT, visible-skip bounds, locale assist, mic
  selection, and normal presenter lifecycle unchanged.
- Strict mode disables provider force-skip. Repeated no-match results must not
  walk the confirmed index through words the user did not say.
- Strict mode narrows local recovery to the next word and raises aligner
  thresholds. Local single-word guesses cannot skip several words.
- Strict mode still permits deliberate next-word progress and confirmed
  multi-word visible-window phrase/sequence jumps, including Hebrew phrases.
- Large single-word visible jumps remain blocked even in strict mode.
- Strict mode uses the presenter visible word window as its allowed phrase
  target even when the separate `Allow visible text skip` toggle is off. This
  keeps bullet/header prompting recoverable after improvisation, but still
  requires confirmed phrase/sequence evidence and never enables large
  single-word jumps.

### 2026-05-04 Regression Repair Addendum

- Alignment owns visible skip decisions before locale switching. The aligner
  must scan the full presenter visible word window when
  `maxSkipTargetIndex` is supplied.
- Visible skip off remains conservative: local recovery is limited to the
  next five words.
- Large visible jumps require phrase or sequence confidence. Single-word large
  jumps remain blocked.
- Windows WebView2 STT locale switching is secondary assistance only. The
  provider must not switch locale after a few no-match waits before the aligner
  has had a fair chance to match the current locale against the full visible
  window.
- Delayed visible-locale assistance may run only after repeated no-progress
  waits, after the aligner has failed to match the current transcript inside
  the visible window.
- The provider's normal 30-word advance cap is not applied to trusted
  visible-window phrase/sequence matches. Those targets are already bounded by
  the presenter visible window and confidence-gated by the aligner, so they must
  apply immediately. The 30-word cap remains active for non-visible STT progress.
- Windows visible-locale assistance uses a two-step arm/switch flow. A plausible
  active-locale visible transcript blocks the assist; wrong-language gibberish
  may switch to the next visible alternate locale on the second no-progress
  result.
- After a visible-locale assist, the assisted locale is pinned briefly. Heartbeat
  and one-word-ahead pre-switch logic must not switch back to the old script
  position until the pin expires or a successful advance/manual jump/reset clears
  it.

---

## Shared-File Ownership Notes

STT owns speech lifecycle and callback sections in `teleprompter_provider.dart`.
Teleprompter Engine owns confirmed index, force-skip, fluid advance, and visual
rendering. Settings owns `sttEngine` persistence; STT only consumes it.
---

## Windows v4.1.12 Final Seal Notes

- STT stop/start is a pause/resume lifecycle, not a reset lifecycle.
- `stopSession()` must tear down the recognizer/WebView session without
  resetting `confirmedWordIndex`.
- The next mic start must create a fresh recognizer path at the current
  provider index.
- Restart/reset is the only allowed path back to word `0`.
- External mic selection is part of the sealed Windows contract: WebView2 audio
  input enumeration, persisted device id/label, System Default fallback, and no
  script-position reset when the input changes.
- Stale WebView socket messages must be ignored so old connect/disconnect events
  cannot poison a new STT session.
- Volume-level state may feed the debug sound bar, but recurring volume-bar text
  rows must not return to the debug log.

---

## V5 File Split Notes

STT-owned presenter UI logic was moved out of the monolithic
`teleprompter_screen.dart` into same-library Dart parts. This is a mechanical
split only: `teleprompter_screen.session_stt.dart`,
`teleprompter_screen.audio_debug_widgets.dart`, and the mic sections inside the
settings parts must preserve the same lifecycle, callback guards, WebView
reload behavior, and external mic fallback semantics.
