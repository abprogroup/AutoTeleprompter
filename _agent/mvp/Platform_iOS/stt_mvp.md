---
name: STT MVP
type: component
platform: iOS
last_updated: 2026-04-29
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
- If iOS cannot select an external microphone in-app, document the OS routing
  limitation here before implementing any UI.

Do not copy Windows WebView2/browser STT internals into iOS. Use
`SttAppleAdapter`, the iOS audio-buffer design, or a documented iOS-native
alternative.
