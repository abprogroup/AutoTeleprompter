---
name: Audio Buffer MVP
type: component
platform: iOS
status: DESIGN — not yet implemented
last_updated: 2026-04-27
depends_on: STT MVP
---

# Audio Buffer MVP — iOS

Provides seamless, gap-free language switching during STT recognition by capturing
audio into a short in-memory buffer at the moment a locale switch is triggered,
then feeding that buffer to the new recognizer before handing off to the live
microphone. The STT MVP calls one method; this MVP handles everything else.

---

## The Problem It Solves

When `setLocale()` fires today:
1. `_stt.cancel()` is called — recognition stops
2. `_scheduleRestart(150ms)` fires — new `listen()` starts with the new locale
3. During that ~300ms gap, speech is spoken but nothing captures it
4. The word aligner gets no results → force-skip fires after 45 cycles (~slow)

For 3-word foreign sections this is a hard UX problem: the entire section falls in the gap.
For rapid multi-switches (Hebrew → English → Hebrew) it compounds each time.

---

## Critical Architecture Constraint

The `speech_to_text` plugin already owns an `AVAudioEngine` instance and installs a
tap on the input node. iOS only allows **one tap per audio node**. We cannot add a
second tap from our own code while the plugin is active.

**Resolution**: Replace `speech_to_text` for iOS with a custom native Swift bridge
(`SpeechBridge.swift`) that owns the `AVAudioEngine` directly. This gives full
control over audio taps, buffer management, and `SFSpeechAudioBufferRecognitionRequest`.
The external Dart API stays identical to the current `SpeechService` so the STT MVP
requires zero interface changes.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/ios/Runner/SpeechBridge.swift` | Native: `AVAudioEngine`, audio tap, `SFSpeechRecognizer`, buffer management |
| `Platform_iOS/lib/platform/stt/speech_bridge_service.dart` | Dart: MethodChannel wrapper — drop-in replacement for `SpeechService` on iOS |
| `Platform_iOS/lib/platform/stt/stt_apple_adapter.dart` | Updated to instantiate `SpeechBridgeService` instead of `SpeechService` |

The `speech_to_text` pub dependency is **removed from iOS** once this MVP ships.
`SpeechService.dart` (the plugin wrapper) is retired for iOS; it stays for any future
platform that still needs it.

---

## External API (what the STT MVP calls)

Identical to the current `SpeechService` — no changes to the STT MVP interface.

| Method | Behaviour |
|--------|-----------|
| `start({String? localeId})` | Initialize `AVAudioEngine`, start recognition, return `SpeechStartResult` |
| `stop()` | Cancel recognition, stop engine, flush buffer |
| `setLocale(String locale)` | **Atomic buffer-switch**: snapshot buffer → init new recognizer → feed buffer → continue live |
| `isListening` | True while engine is running and `AVAudioSession` is active |

Callbacks: `onResult`, `onStatusChange`, `onError`, `onLanguageUnavailable` — unchanged.

---

## How `setLocale()` Works Internally

```
T=0   setLocale("en_IL") called
      ┌─────────────────────────────────────────────┐
      │ 1. Mark buffer start timestamp               │
      │ 2. Continue tapping AVAudioEngine → buffer   │  ← no gap here
      │ 3. Cancel current SFSpeechRecognizer         │
      │ 4. Init new SFSpeechRecognizer("en_IL")      │
      │    + SFSpeechAudioBufferRecognitionRequest   │
T=~300ms  new recognizer ready                       │
      │ 5. Replay buffer into new recognizer         │  ← catches missed words
      │ 6. Switch tap output: buffer → new request   │  ← live audio continues
      └─────────────────────────────────────────────┘
T=300+ ms  recognition live in new locale, no gap
```

The audio tap on `AVAudioEngine.inputNode` runs throughout — it never stops.
Only the **destination** of the tap output changes: first a short in-memory buffer,
then `SFSpeechAudioBufferRecognitionRequest.append()`.

---

## Buffer Spec

| Property | Value | Reason |
|----------|-------|--------|
| Max duration | 800ms | Longer = processing debt before live catch-up |
| Format | `AVAudioPCMBuffer` at native sample rate | Matches `SFSpeechAudioBufferRecognitionRequest` requirements |
| Start condition | Triggered at `setLocale()` call | NOT pre-rolling — avoids old-language audio contaminating new recognizer |
| End condition | New recognizer confirmed listening | Buffer is flushed and discarded |
| Memory | ~128 KB for 800ms at 16kHz mono | Negligible |

---

## Invariants

1. **Single engine**: One `AVAudioEngine` instance per session. Never create a second
   instance or install a second tap — conflicts with `AVAudioSession`.

2. **Buffer max 800ms**: The buffer window must never exceed 800ms. If the new
   recognizer takes longer than 800ms to initialize (device overload), discard the
   oldest frames to stay within budget.

3. **Tap never stops**: The `AVAudioEngine` input tap runs continuously while the
   session is active. Only the DESTINATION (buffer vs. recognizer request) changes.
   Stopping and restarting the tap introduces audio glitches.

4. **Sequential, not parallel**: The buffer is fed to the NEW recognizer. The OLD
   recognizer is cancelled before buffer replay starts. Never feed the same audio
   to two recognizers simultaneously.

5. **No pre-rolling**: Buffer capture starts ONLY when `setLocale()` is called.
   No audio from the previous locale section enters the new recognizer.

6. **Session isolation**: The buffer is created and destroyed within a single
   `start()` / `stop()` session. Carry-over between sessions is forbidden.

7. **Graceful fallback**: If the native bridge fails to initialize (permissions,
   device unsupported, `SFSpeechRecognizer` unavailable for locale), the error
   must surface via `onError` / `SpeechStartResult(success: false)` — never crash.
   The STT MVP's existing error handling then shows the appropriate UI.

8. **`requiresImmediateListeningFlag` stays true**: Apple status callbacks are still
   async. The `_startingSession` guard in the STT MVP provider must NOT be removed
   when adopting this bridge.

---

## Interface to STT MVP

The STT MVP (`teleprompter_provider.dart`) calls `_sttService.setLocale(newLocale)`.
That is the **only** call site. The Audio Buffer MVP is entirely internal to that call.

The STT MVP context doc (`stt_mvp.md`) Invariant 4 ("setLocale() is race-free") still
holds: `setLocale()` does not call `stop()` or `start()` from the provider's perspective.
Internally the bridge may cancel and restart the recognizer, but this is invisible to
the provider.

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| STT provider locale switch | `Platform_iOS/lib/features/teleprompter/providers/teleprompter_provider.dart` | Calls `_sttService.setLocale(newLocale)` through the STT MVP contract |
| Apple STT adapter | `Platform_iOS/lib/platform/stt/stt_apple_adapter.dart` | Will instantiate the bridge-backed speech service when this design ships |
| Native bridge channel | `Platform_iOS/lib/platform/stt/speech_bridge_service.dart` | Planned Dart MethodChannel wrapper for native buffer switching |

No editor, history, settings, or file I/O code should call Audio Buffer directly.
The STT MVP remains the only feature-level caller.

---

## Forbidden Changes

- Do not add a `startBuffering()` / `stopBuffering()` call to the STT MVP provider —
  the buffer lifecycle is owned entirely by this MVP and managed inside `setLocale()`.
- Do not use `speech_to_text` plugin and `SpeechBridgeService` simultaneously for the
  same session — they will conflict over the `AVAudioSession`.
- Do not pre-roll the buffer (start capturing before `setLocale()` is called) — old-
  language audio will contaminate the new recognizer and produce incorrect results.
- Do not exceed 800ms buffer duration — processing debt causes a perceived recognition lag.
- Do not share the `SFSpeechAudioBufferRecognitionRequest` instance across locale
  switches — each switch creates a new request and a new recognizer.

---

## Implementation Phases

| Phase | Scope | Risk |
|-------|-------|------|
| 1 | `SpeechBridge.swift` — basic `AVAudioEngine` + `SFSpeechRecognizer`, same feature set as current `SpeechService` (no buffer yet) | Medium — replaces plugin, must verify all callbacks |
| 2 | Add audio tap + in-memory buffer to `SpeechBridge.swift` | Low — additive change |
| 3 | Implement `setLocale()` with buffer replay | Medium — timing-sensitive |
| 4 | Remove `speech_to_text` from iOS `pubspec.yaml` | Low — cleanup |

Phase 1 must be verified working (all existing STT features intact) before Phase 2
is started. Each phase is a separate commit with its own build verification.

---

## Known Risks

- **`AVAudioSession` category conflict**: The current app sets the audio session
  category for both recording and playback. Verify that the custom engine uses the
  same category / mode as the plugin did, or audio routing will break.
- **Background audio permission**: If the user backgrounds the app mid-session, iOS
  may suspend `AVAudioEngine`. The existing `_sessionStopped` guard handles this at
  the provider level; the bridge must also handle engine interruption notifications.
- **`SFSpeechRecognizer` availability for locale**: Not all locales support on-device
  recognition. The bridge must call `SFSpeechRecognizer.isAvailable(for: locale)`
  before starting and surface `onLanguageUnavailable` if false.
- **iOS 16 minimum**: `SFSpeechAudioBufferRecognitionRequest` has been available since
  iOS 13, but verify the exact APIs used are available on the project's minimum target.

---

## Known Fragilities

- **Native bridge not implemented yet**: This MVP is marked `DESIGN`; the owned
  Swift and Dart bridge files are planned and must be created before runtime use.
- **Single audio tap constraint**: Adding any second tap to the same
  `AVAudioEngine.inputNode` will conflict with the bridge design.
- **Locale switch timing**: Buffer replay is timing-sensitive and must preserve
  the STT MVP's race-free `setLocale()` contract.
- **Permission/interruption handling**: iOS speech and audio-session
  interruptions must surface through existing STT error callbacks, not crashes.

---

## External Microphone Bridge Consideration - 2026-05-02

- The current v4 iOS STT adapter can request preferred input routes through
  `AVAudioSession.availableInputs` / `setPreferredInput(...)`, but it still
  relies on `speech_to_text`/Apple speech to honor the selected route.
- If this Audio Buffer / SpeechBridge MVP ships, it is the correct place to
  investigate explicit route handling through `AVAudioSession` and
  `AVAudioEngine`.
- Any explicit mic selector must verify real iOS route ownership first:
  wired/headset, USB audio interface, Bluetooth/HFP input, route-change
  notifications, permission denial, and stop/start resume behavior.
- Do not promise Windows-style Chromium device selection. A future native
  bridge should verify that the selected `AVAudioSession` route is actually
  feeding `SFSpeechRecognizer` / `SFSpeechAudioBufferRecognitionRequest`.
