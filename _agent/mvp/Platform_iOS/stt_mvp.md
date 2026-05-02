---
name: STT MVP
type: component
platform: iOS
last_updated: 2026-05-02
---

# STT MVP — iOS

Governs the full iOS speech-recognition pipeline: session lifecycle, bilingual section switching, error handling, and the word-alignment feedback loop that drives teleprompter advancement.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/platform/stt/abstract_stt_service.dart` | Platform-agnostic interface: `start()`, `stop()`, `setLocale()`, all callbacks |
| `Platform_iOS/lib/platform/stt/stt_service_factory.dart` | Creates `SttAppleAdapter` — the ONLY place the adapter is instantiated |
| `Platform_iOS/lib/platform/stt/stt_apple_adapter.dart` | Wraps `SpeechService` for iOS; sets `requiresImmediateListeningFlag=true` |
| `Platform_iOS/lib/platform/stt/ios_audio_input_service.dart` | MethodChannel wrapper for iOS `AVAudioSession` input route listing/selection |
| `Platform_iOS/lib/platform/stt/stt_desktop_adapter.dart` | Source-present desktop adapter; not the iOS runtime path |
| `Platform_iOS/lib/platform/stt/stt_android_adapter.dart` | Source-present Android adapter; not the iOS runtime path |
| `Platform_iOS/lib/features/teleprompter/services/speech_service.dart` | `speech_to_text` plugin wrapper: 4-stage error recovery, locale retries, `setLocale()` |
| `Platform_iOS/lib/features/teleprompter/services/native_speech_service.dart` | Source-present Android native speech service; not the iOS runtime path |
| `Platform_iOS/lib/features/teleprompter/services/word_aligner.dart` | Aligns heard transcript to script words, returns `confirmedWordIndex` |
| `Platform_iOS/lib/features/teleprompter/models/alignment_result.dart` | `AlignmentResult` model |
| `Platform_iOS/lib/features/teleprompter/services/whisper_speech_service_native.dart` | Whisper offline engine (optional, not active in v4.1) |
| `Platform_iOS/lib/features/teleprompter/providers/teleprompter_provider.dart` | Session state, bilingual section map, word advance logic, fluid advance timer |

---

## External API (what outside code may call)

| Method / Field | Caller |
|----------------|--------|
| `startSession(Script script)` | `TeleprompterScreen` — mic button / auto-start |
| `stopSession()` | `TeleprompterScreen` — mic button, `dispose()`, back navigation |
| `resetPosition()` | `TeleprompterScreen` — restart button |
| `state.confirmedWordIndex` | `TeleprompterScreen` — drives scroll position and word highlighting |
| `state.isListening` | `TeleprompterScreen` — mic button color |
| `state.hasError` | `TeleprompterScreen` — error banner |
| `state.statusMessage` | `TeleprompterScreen` — error message text |
| `state.missingLanguage` | `TeleprompterScreen` — language pack install prompt |
| `state.debugLogs` | `TeleprompterScreen` (debug mode only) — live log panel |

No other feature code touches the STT MVP directly. The script editor does NOT interact with STT.

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Mic / play button | `teleprompter_screen.dart` | `startSession()` / `stopSession()` |
| Restart button | `teleprompter_screen.dart` | `resetPosition()` |
| Screen dispose | `teleprompter_screen.dart` | `stopSession()` |
| Word highlight widget | `teleprompter_screen.dart` | Reads `state.confirmedWordIndex` |
| Error banner | `teleprompter_screen.dart` | Reads `state.hasError`, `state.statusMessage`, `state.missingLanguage` |

---

## Invariants

1. **Session guard**: `_sessionStopped=true` causes ALL incoming STT callbacks (`onResult`, `onStatusChange`, `onError`) to return immediately. Set at the top of `stopSession()`, never cleared until the next `startSession()`.

2. **Disposed guard**: `_disposed=true` causes all `_safeSetState` calls to no-op. Set in `ref.onDispose()`. Never reset.

3. **`SpeechService._isActive` controls auto-restart**: When `stop()` is called, `_isActive=false`. Any pending `_scheduleRestart` timer checks `if (!_isActive) return` at execution time. Do NOT bypass this check or call `start()` from a `.then()` chain after `stopSession()` may have fired.

4. **`setLocale()` is race-free**: It only updates `_localeId` and calls `_stt.cancel()` (which triggers the service's own internal restart). It does NOT call `stop()` or `start()`. Never replace `setLocale()` with a stop/start chain — that creates a race with `stopSession()`.

5. **Bilingual section map always populated**: `_sectionLocales` is always populated at `startSession()` via `_precomputeSectionLocales()`. Its length equals `script.words.length` (including newlines). `_checkAndSwitchLocale()` indexes into it with `confirmedWordIndex` — always check bounds before access.

6. **Section minimum run = 3 words**: `_precomputeSectionLocales` absorbs runs shorter than 3 words into the surrounding language. This prevents STT restarts for single foreign names. Do NOT lower this threshold — it causes thrashing on mixed proper-noun text.

7. **`_startingSession` guard**: Set to `true` immediately after `start()` returns (Apple's `SFSpeechRecognizer` fires status callbacks asynchronously). Auto-clears after 1500ms. While `true`, non-listening status updates are ignored to prevent the previous session's stale `notListening` from clearing the new session's `isListening=true`.

8. **Adapter instantiated only by factory**: `SttServiceFactory.create()` is the sole instantiation point for `SttAppleAdapter`. Feature code uses `AbstractSttService` type only. Never directly instantiate `SttAppleAdapter` in feature code.

9. **Voice commands take priority**: `_handleSttResult()` checks for voice commands (stop/start/faster/slower, Hebrew variants) before running `WordAligner.align()`. Do not move or reorder these checks.

10. **Force-skip threshold**: After `_googleSkipAfterStuck` (45) no-progress cycles, the engine force-advances to the next word to prevent stalling on mispronounced words. Do not raise above 60 or lower below 20.

11. **Fluid advance**: Jumps of > 3 words animate word-by-word at 80ms intervals via `_fluidAdvanceTimer`. `_fluidTarget` is updated by newer results mid-animation. Cancel and reset the timer in `stopSession()` and `resetPosition()`.

12. **`_checkAndSwitchLocale()` fires only on advance**: Called exclusively after a `confirmedWordIndex` advance inside `_handleSttResult()`. It must not fire from any other path — the section map index is only valid when the position actually moved forward.

---

## Forbidden Changes

- Do not replace `setLocale()` with a stop/start chain for locale switching — that creates a race with `stopSession()`. `setLocale()` triggers the service's own internal restart safely.
- Do not remove the `_sessionStopped` / `_disposed` guards from any callback — they are the only protection against callbacks firing after the widget tree is torn down.
- Do not remove `_precomputeSectionLocales()` from `startSession()` — without it `_sectionLocales` is empty and bilingual switching is completely disabled.
- Do not call `_checkAndSwitchLocale()` from anywhere other than after a position advance in `_handleSttResult()`.
- Do not pass `localeId` with a hyphen separator (`he-IL`) — keep underscore (`he_IL`) for consistency; the plugin normalizes internally but mixing separators causes confusion.
- Do not activate the Whisper code path in v4.1 — `_useWhisper` must remain `false` unless the user explicitly selects a Whisper engine in settings. Changes to STT error handling must not trigger the Whisper fallback.

---

## Known Fragilities

- **`_startingSession` expires unconditionally**: The guard auto-clears after 1500ms regardless of whether the session actually started. On slow devices, if startup takes > 1500ms, a stale `notListening` callback from the previous session can clear `isListening=true`.
- **`_scheduleRestart` after `setLocale()`**: `setLocale()` calls `_stt.cancel()` → `onStatus('done')` → `_scheduleRestart(150ms)`. If `stopSession()` fires during that 150ms, `_isActive=false` safely cancels the restart. If a NEW `startSession()` fires in that window, two restarts may overlap — always ensure the previous session is fully stopped before starting a new one.
- **Word aligner false positives near boundaries**: `WordAligner.align()` is fuzzy-match based. Short words (1-2 chars) near language section boundaries can produce false-positive advances, triggering a locale switch before the section is reached. The 3-word minimum section size (Invariant 6) mitigates this.
- **Whisper code path dormant but present**: `_whisperService`, `_useWhisper`, `_setupWhisperCallbacks()`, and `_autoFallbackToWhisper()` exist in the provider but are inactive in v4.1. Any refactor of the STT error path must not accidentally reach the Whisper branch.

---

## Windows v4.1.12 Final Migration Target

Before changing iOS STT, preserve iOS-specific Apple speech invariants above
and port only the product behavior proven on Windows:

- Stop/start is pause/resume. `stopSession()` must not reset
  `confirmedWordIndex`; only Restart resets to word `0`.
- Default STT local recovery may advance through up to 5 missed words so minor
  recognizer omissions do not stall the presenter.
- Longer skip behavior must be opt-in, bounded to the rendered visible word
  window, and fallback-only after nearby 3+ word phrase priority fails.
- Visible skip must never target offscreen text.
- Active-STT bookmark jumps are allowed and must resync transcript/no-progress
  state without restarting from the beginning.
- iOS external microphone selection must use native `AVAudioSession` route
  preference, not Windows WebView2 browser-device APIs.

Do not copy Windows WebView2/browser STT internals into iOS. Use
`SttAppleAdapter`, the iOS audio-buffer design, or a documented iOS-native
alternative.

---

## iOS External Microphone Selection - 2026-05-02

- Current iOS STT runtime path is `SttAppleAdapter` -> `SpeechService` ->
  `speech_to_text` -> Apple's `SFSpeechRecognizer`/system audio route.
- iOS exposes a best-effort in-app microphone route selector through
  `AVAudioSession.availableInputs` and `setPreferredInput(...)`.
- External microphones are selectable when iOS exposes them as available input
  routes: wired headset mics, USB audio interfaces, and Bluetooth/HFP input.
  Empty selection means System Default.
- If the active iOS route changes while STT is running and the plugin does not
  pick it up, the supported v4 recovery is stop/start resume: `stopSession()`
  tears down the recognizer without resetting `confirmedWordIndex`, and the
  next `startSession()` resumes from the same position on the selected/current
  route.
- A future SpeechBridge may own deeper `AVAudioSession`/`AVAudioEngine`
  verification, but the current v4 selector already applies route preference
  before `speech_to_text` starts.
- Forbidden regression: do not copy the Windows WebView2
  `navigator.mediaDevices` picker into iOS. iOS persists Apple
  `AVAudioSessionPortDescription.uid` values, not Chromium device IDs.

### 2026-05-02 implementation update

- The limitation above is now narrowed: iOS does have a native best-effort
  route selector through `AVAudioSession.availableInputs` and
  `setPreferredInput(...)`, so the app exposes that instead of waiting for the
  future SpeechBridge.
- `SttAppleAdapter.refreshAudioInputDevices()` lists available Apple input
  routes through `IosAudioInputService`. `setAudioInputDevice(...)` applies the
  selected route before `SpeechService.start(...)`.
- Empty input means System Default and calls `setPreferredInput(nil)`.
- iOS route IDs are `AVAudioSessionPortDescription.uid` values. They are not
  Windows WebView2/Chromium device IDs.
- Route selection remains Apple-owned and best-effort: if a saved route is
  disconnected or iOS refuses it, STT falls back to the active/current route.
  Stop/start resume remains the recovery path and must preserve
  `confirmedWordIndex`.

---

## iOS Stop/Resume Parity - 2026-04-30

- `stopSession()` is pause/resume-safe: it stops recognizers and clears
  transient transcript/no-progress state, but it does not reset
  `confirmedWordIndex`.
- `startSession()` resumes from the current `confirmedWordIndex` when the same
  `Script` instance is active. A different script still starts at `0`.
- `_stopInFlight` serializes quick stop/start taps so a new iOS recognizer does
  not start before the previous stop finishes.
- `_sessionToken` invalidates stale async start/stop completions. If an old
  Apple STT start finishes after a newer stop/start, it must stop itself and
  return without mutating state.
- Presentation screen entry may defensively stop a lingering recognizer, but it
  must not call `resetPosition()` or scroll to the top. If a saved
  `confirmedWordIndex` exists, the screen scrolls back to that word after the
  first layout frame.
- Forbidden regression: do not reset `confirmedWordIndex` from `startSession()`,
  `stopSession()`, or presentation screen entry. Only the explicit Restart
  control owns `resetPosition()`.

---

## iOS Default 5-Word Local Recovery - 2026-04-30

- `WordAligner.align(...)` now accepts an optional `int? maxSkipTargetIndex`
  parameter. When `null` (current iOS default), the aligner runs in strict
  local-recovery mode bounded by `_maxSingleJump = 5` non-newline words.
- The default scan window for both single-word and multi-word sequence matches
  is `searchStart + 5` when `maxSkipTargetIndex` is null. This permits normal
  recognizer omissions of one or two words to advance through up to five script
  words ahead, but it must NEVER jump to a later paragraph or section just
  because that text was spoken.
- The provider call site in `teleprompter_provider.dart` does not yet pass
  `maxSkipTargetIndex`, so the default 5-word recovery is the active behavior
  for v4.1.7. Item 3 (opt-in visible viewport skip) will introduce the
  provider/setting wiring that supplies the visible-window upper bound.
- Nearby phrase priority (`_nearPhrasePriorityMatch`) is implemented but only
  activates when `maxSkipTargetIndex` is supplied. It must always run before a
  visible-skip sequence fallback to keep recognized 3+ word phrases close to the
  current position from being lost to a farther similar phrase.
- The sequence loop tightens to the visible window (`sequenceEnd = windowEnd`)
  when visible skip is enabled, and `_maxSeqJump` is capped to
  `maxSkipTargetIndex - lastConfirmedIndex` so visible jumps cannot exceed the
  rendered window.
- Forbidden regression: do not widen the iOS default scan window beyond
  `_maxSingleJump` without the explicit `Allow visible text skip` opt-in. The
  legacy 50-word default window broke the strict-progress contract.

---

## iOS Resume Identity Repair - 2026-05-02

- `startSession(Script script)` must compare stable script identity, not only
  Dart object identity.
- Same-session resume is true when the previous and incoming scripts share a
  non-empty `sessionId`, or when title and raw text still match.
- This protects the editor -> present -> editor -> present flow where the same
  script may be rebuilt as a new `Script` object after editing.
- Starting STT from a reopened same-session presenter must preserve the current
  `confirmedWordIndex`; it must not silently reset to `0`.
- A genuinely different script may still start from `0`.

---

## iOS Opt-In Visible Viewport Skip - 2026-04-30

- `AppSettings.sttVisibleSkipEnabled` (default `false`) gates the visible-skip
  pathway. While disabled, alignment runs the strict 5-word default local
  recovery from Item 2 and refuses paragraph/section jumps.
- The provider stores the rendered visible word range in `_visibleWordStart`
  and `_visibleWordEnd`. The presenter pushes updates via the new public
  `setVisibleWordWindow(int? start, int? end)` method.
- `_handleSttResult()` builds `maxSkipTargetIndex` only when both
  `sttVisibleSkipEnabled` is true AND a visible window is reported. The value
  is `_visibleWordEnd`, capping the aligner's scan to currently rendered text.
- `startSession()` clears `_visibleWordStart`/`_visibleWordEnd` so the first
  STT result of a new session never uses a cached window from a previous
  presenter mount.
- The presenter calls `_scheduleVisibleWordWindowSync()` from build, which
  defers a `_syncVisibleWordWindow(force: true)` to the next frame. The sync
  walks `_wordKeys` against the viewport, skips newlines and unspeakable
  display tokens, and pushes the first/last visible indices to the provider.
  Throttled to ~150 ms unless forced.
- Default contract: with the toggle off, alignment must never jump to text
  below the rendered window. With it on, nearby phrase priority (3+ words,
  see Item 2) must always win before a farther visible match.
- Forbidden regression: do not pass `maxSkipTargetIndex` from outside the
  visible-skip path. The aligner's strict 5-word default protects the user
  from false jumps when the toggle is off.

---

## iOS Active-STT Scroll Lock & Row-Progress Follow - 2026-04-30

- `TeleprompterState` now exposes `isStarting` (default false). The provider
  sets it true at `startSession()` entry and clears it on the first real STT
  status callback, on stop, and on fatal/language/pack errors. The legacy
  private `_startingSession` guard (Invariant 7) is preserved.
- `_handleStoppedBrowsingScroll(ScrollNotification)` short-circuits while
  `isListening || isStarting` is true. The `SingleChildScrollView` physics
  switches to `NeverScrollableScrollPhysics` during that window, so manual
  drag scroll is impossible. Bookmark jumps and explicit controls still work
  because they call `jumpToPosition`/`_scrollToWordIndex` directly, not the
  user gesture path.
- `_scrollToWordIndex(index)` now adds a fractional row-progress offset
  computed by `_visualRowProgress` (uses `_boxForWordIndex` and a
  Y-tolerance walk). The auto-scroll glides smoothly across each row instead
  of snapping at line boundaries.
- Forbidden regression: do not gate the scroll lock on `isListening` alone —
  startup and recovery windows must also lock to prevent the active reading
  position from drifting off-screen.

---

## iOS Stopped Browsing & Resume-Point Selection - 2026-04-30

- `_handleStoppedBrowsingScroll` flips `_userBrowsingWhileStopped` true on
  user drag start/update events while STT is stopped, cancels in-flight
  smooth scroll/manual-scroll timers, and on `ScrollEndNotification` calls
  `_syncVisibleWordWindow(force: true)` and `_syncResumePointToReadingLine`.
- `_syncResumePointToReadingLine` walks `_wordKeys` for the non-newline word
  closest to the reading line (`scrollLead * viewportH`) and routes it
  through `TeleprompterNotifier.jumpToPosition(index, script: script)`.
- `jumpToPosition` clears `_accumulatedTranscript` and `_noProgressCount`,
  updates `state.confirmedWordIndex`, and — only when listening — calls
  `_syncLocaleForPosition` (a non-Invariant-12 helper that swaps
  `_activeLocale` to match the section at the new index without going
  through `_checkAndSwitchLocale`).
- Restart remains the only owner of `confirmedWordIndex = 0`. Stop is now
  pause-and-browse: position state survives, the next mic start resumes
  from the synced point.
- Forbidden regression: do not call `_checkAndSwitchLocale` from any manual
  jump path — Invariant 12 reserves it for natural advances inside
  `_handleSttResult`.
