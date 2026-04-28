---
name: Teleprompter Engine MVP
type: component
platform: Windows
last_updated: 2026-04-28
---

# Teleprompter Engine MVP - Windows

Governs the Windows presentation runtime: word index advancement, smooth
scrolling, manual controls, presentation rendering, display settings, and the
state contract consumed by the teleprompter screen. STT capture itself belongs
to STT MVP; this MVP owns what the app does with confirmed words.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | `TeleprompterNotifier`, `TeleprompterState`, confirmed index, force-skip, fluid advance, reset/stop state |
| `Platform_Windows/lib/features/teleprompter/models/alignment_result.dart` | `TeleprompterState` model and copy semantics |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Presentation rendering, manual controls, settings panel, scroll animation, word highlighting |
| `Platform_Windows/lib/features/teleprompter/services/word_aligner.dart` | Tokenization/alignment helper shared with STT; advancement thresholds are STT-owned but output drives engine state |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `teleprompterProvider` | `TeleprompterScreen` |
| `startSession(Script script)` | `TeleprompterScreen._requestAndStart()` |
| `stopSession()` | Mic button, back navigation, `TeleprompterScreen.dispose()` |
| `resetPosition()` | Restart/reset UI |
| `jumpToPosition(int index)` | Presentation word tap / resume-point selection |
| `_showSearchDialog()` / `_jumpToSearchMatch(String query)` | Present-mode `Ctrl+Shift+F` search and jump-to-word resume selection |
| `_handleStoppedBrowsingScroll(ScrollNotification)` | Stopped-session browsing; cancels stale follow-scroll and updates resume point from reading line |
| `TeleprompterState.confirmedWordIndex` | Word highlight and scroll target |
| `TeleprompterState.isListening` | Mic button/control bar state |
| `TeleprompterState.isStarting` | STT startup/loading indicator and startup-safe control state |
| `TeleprompterState.statusMessage` / `hasError` | Error banners and dialogs |
| `TeleprompterState.soundLevel` | Audio-level UI |
| `TeleprompterState.sttWebViewUrl` | Windows browser STT view when that adapter is active |
| `TeleprompterState.audioInputDevices` | Windows presenter mic selector; populated by STT adapter discovery |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Presentation screen | `teleprompter_screen.dart` | Reads provider state, starts/stops/resets session |
| Control bar | `teleprompter_screen.dart` | Calls `stopSession()`, toggles manual presentation behavior locally |
| Settings panel | `teleprompter_screen.dart` | Reads/writes settings while presentation runs |
| Windows mic selector | `teleprompter_screen.dart` | Reads `audioInputDevices`, persists preferred mic, and forwards live changes to provider |
| STT callbacks | `teleprompter_provider.dart` | Call `_handleSttResult()` after `SpeechResult` arrives |
| Remote hooks | `teleprompter_provider.dart` | Placeholder `_setupRemoteCallbacks()` intersects with future remote control |

---

## Preserved Internal States & Tuning Constants

These constants and public session methods were already documented by the
earlier Windows MVP file and remain part of the engine contract:

| Variable | Value / Type | Purpose |
|----------|--------------|---------|
| `_googleSkipAfterStuck` | 45 seconds | Wait bounds for Google/STT stalls |
| `_whisperSkipAfterStuck` | 10 seconds | Wait bounds for custom/Whisper-style isolates |
| `_maxAdvancePerUpdate` | 30 words | Throttle limits for frame calculations |

| Method | Purpose |
|--------|---------|
| `startSession(Script script)` | Initializes audio/STT processing against a script |
| `stopSession()` | Cleans background listeners, timers, and active session state |
| `resetPosition()` | Resets confirmed word position without changing script content |

---

## Invariants

1. **Confirmed index is bounded**: `confirmedWordIndex` must always remain within
   the active script word list bounds.

2. **Voice commands run before alignment**: Stop/start/faster/slower commands are
   handled before `WordAligner.align()` so spoken commands do not advance the
   script.

3. **No-progress force skip is bounded**: `_googleSkipAfterStuck`,
   `_whisperSkipAfterStuck`, and `_maxAdvancePerUpdate` prevent both indefinite
   stalls and runaway jumps.

4. **Fluid advance is cancelable**: `_fluidAdvanceTimer` must be canceled on
   stop, reset, dispose, or when a new fluid target supersedes it.

5. **Stop is authoritative**: After `stopSession()`, pending callbacks and timers
   must not mutate visible state.

6. **Manual scrolling is UI-local**: Manual scroll timers and local indices in
   `teleprompter_screen.dart` must not corrupt provider `confirmedWordIndex`.

7. **Settings override rendering only**: Presentation settings affect display and
   scroll behavior; they must not mutate `Script.rawText`.

8. **Read-word visual policy is centralized in presentation rendering**: Current,
   future, past, fade, highlight, and markup colors must be resolved in the
   teleprompter render path, not in the script provider.

9. **Sound bar visibility is non-destructive**: The voice visualizer/sound bar in
   `teleprompter_screen.dart` must remain mounted and be hidden with
   `Opacity(opacity: settings.debugMode ? 1.0 : 0.0)` plus
   `IgnorePointer(ignoring: !settings.debugMode)`. Do not guard it with
   `if (settings.debugMode)` or otherwise unload its render tree.

10. **State indices are never dropped**: Visibility toggles, debug-mode changes,
    and overlay layout updates must not reset or discard index-bearing state such
    as `confirmedWordIndex`, `_manualWordIndex`, `_wordKeys`, or scroll targets.

11. **STT startup has explicit UI state**: `TeleprompterState.isStarting` is the
    only presentation contract for "recognizer is booting / locale is pivoting".
    Do not fake this by resetting `isListening`, `confirmedWordIndex`, or scroll
    targets.

12. **Embedded STT WebView is not a user-facing panel**: When browser STT is
    active, its WebView must remain mounted for processing but stay visually
    hidden behind a tiny transparent target. The Flutter sound bar and debug
    console are the visible diagnostics.

13. **Exiting presentation stops STT**: The presentation screen must request
    `stopSession()` when leaving presentation mode through the control bar, OS
    back navigation, or widget disposal. Do not rely only on the next session
    start to clean up a lingering recognizer.

14. **STT WebView reload state is part of restart safety**: When
    `TeleprompterState.sttWebViewUrl` becomes null, `teleprompter_screen.dart`
    must clear its private `_loadedWebViewUrl` cache so a later session can load
    the fresh browser-STT URL even if the localhost path is otherwise identical.

15. **Stop/start resumes from current position**: `stopSession()` is a pause of
    speech recognition, not a restart of the text. `startSession()` must use the
    current `confirmedWordIndex` as the resume point. Only `resetPosition()` /
    the restart button may intentionally move the script back to index `0`.

16. **Presentation taps set the resume point**: Tapping a word in presentation
    mode calls `jumpToPosition(index)`, scrolls the tapped word to the reading
    line, clears stale transcript/no-progress state, and preserves that index
    for the next mic start.

17. **Search sets the resume point**: In presentation mode,
    `Ctrl+Shift+F` must open script search. Selecting a match must jump to the
    matching word, update `confirmedWordIndex` through `jumpToPosition(...)`,
    scroll to the reading line, and make the next mic start resume there.

18. **Stopped STT allows free browsing**: When `TeleprompterState.isListening`
    and `isStarting` are both false, user scroll in presentation mode must not
    be pulled back to an old STT scroll target. User drag starts must cancel the
    smooth-scroll timer, and scroll end must sync the resume point to the word
    nearest the reading line.

19. **Auto-follow is active-STT-only**: Speech-mode auto-scroll from
    `confirmedWordIndex` changes is allowed only while STT is actively
    listening. Stopped/paused presentation mode is a browsing/position-picking
    state, not an auto-follow state.

20. **Debug console collapse is visual only**: Debug-mode minimize/expand changes
    only the debug output window height. It must not clear `debugLogs`, unmount
    STT processing, reset `soundLevel`, or move the resume point.

21. **Mic selection must not reset presentation position**: Choosing a Windows
    external microphone from the presenter settings panel may restart/reopen STT
    capture internals, but it must not call `resetPosition()`, clear
    `confirmedWordIndex`, scroll to the top, or discard the current resume
    point.

---

## Forbidden Changes

- Do not move raw STT adapter lifecycle into the screen. It belongs in the
  provider/STT MVP.
- Do not allow a single STT update to advance beyond `_maxAdvancePerUpdate`
  without a documented threshold change.
- Do not remove timer cancellation from `stopSession()`, `resetPosition()`, or
  provider disposal.
- Do not mutate script text while rendering presentation mode.
- Do not restore remote command mutation without reading Remote MVP.
- Do not activate hidden Whisper paths on Windows without checking build and
  dependency constraints.
- Do not remove the STT startup/loading indicator without replacing the
  `isStarting` state contract everywhere it is consumed.
- Do not wire the presentation back button directly to `Navigator.pop()` without
  stopping the active STT session first.
- Do not keep `_loadedWebViewUrl` pointing at an old browser-STT page after
  provider state has cleared `sttWebViewUrl`.
- Do not reset `confirmedWordIndex` inside `startSession()`.
- Do not call `resetPosition()` from `teleprompter_screen.dart initState()` just
  because presentation mode opened. Reset belongs to the explicit restart
  control.
- Do not let stopped-session scroll notifications call `_scrollToWordIndex()` or
  restart smooth auto-follow. Stopped scrolling is user navigation.
- Do not make present-mode search editor-only. `Ctrl+Shift+F` must work in both
  editor and presentation contexts.
- Do not collapse the debug console by disabling debug mode or deleting the log
  list state. Collapse is a UI-height toggle only.
- Do not hide the Windows mic selector behind debug mode. External input choice
  is a runtime presentation control, not only a diagnostic.

---

## Known Fragilities

- **Provider is multi-owner**: `teleprompter_provider.dart` contains STT,
  teleprompter advancement, remote placeholders, debug logging, and settings
  integration.
- **Async callback races**: STT callbacks can arrive after screen disposal or
  stop. Guards must remain in place.
- **Large jumps**: Word alignment can jump forward; fluid advance exists to keep
  the user visually oriented.
- **Windows STT alternatives**: Native SAPI and browser STT paths have different
  callback timing and WebView behavior.
- **Presenter focus capture**: Full-screen presentation can lose Flutter focus to
  overlays, controls, or WebView surfaces. Present-mode search therefore uses a
  hardware-key fallback in addition to `Shortcuts`/`Actions`.
- **Stopped browsing resume accuracy**: Stopped-session scrolling chooses the
  visible word nearest the reading line. Very large font sizes, mirrored output,
  or extreme spacing can make the nearest-word heuristic more sensitive.

---

## Recent Windows Contracts Added 2026-04-28

| Feature | Contract |
|---------|----------|
| Debug output minimize / expand | The debug panel in `teleprompter_screen.dart` may collapse to a header-height view and expand back to full log height without clearing state. |
| Present-mode search | `Ctrl+Shift+F` opens a search dialog in presentation mode even when focus was captured by full-screen/overlay surfaces. |
| Search-to-resume | A found word becomes the next resume point through `jumpToPosition(...)`. |
| Stopped-session browsing | While STT is stopped, manual scrolling cancels stale smooth-scroll targets and updates the resume point from the reading line on scroll end. |
| Active STT auto-follow | Auto-follow remains enabled only while STT is listening. |
| Windows external mic selector | Presentation settings can show discovered `audioinput` devices, persist selection, and apply the chosen input without resetting script position. |

---

## Shared-File Ownership Notes

STT MVP owns adapter construction, STT callbacks, and speech lifecycle sections
inside `teleprompter_provider.dart`. Teleprompter Engine owns confirmed-word
state, force-skip, fluid advance, reset, and presentation rendering behavior.

---

## Preserved Original Contract Rows

The following rows and notes existed in the prior Windows Teleprompter Engine
MVP and remain preserved so hardening is additive, not destructive.

Legacy exact title marker: `# Teleprompter Engine MVP â€” Windows`

Prior scope statement: Governs the rendering architectures and hardware
execution flags.

| Original Owned File Row | Preserved Role |
|-------------------------|----------------|
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | Riverpod controller handling voice command prioritization and manual overrides. |

| Original API Row | Preserved Where Called |
|------------------|------------------------|
| `_handleSttResult(...)` | Callback routers parsing active inputs. |

| Original Caller Row | Preserved What It Calls |
|---------------------|-------------------------|
| Teleprompter UI / `teleprompter_screen.dart` | Listens to scrolling offsets. |

## Internal States & Tuning Constants

| Variable | Value / Type | Purpose |
|----------|--------------|---------|
| `_googleSkipAfterStuck` | 45 seconds | Wait bounds for STT stalls |
| `_whisperSkipAfterStuck` | 10 seconds | Wait bounds for custom isolates |
| `_maxAdvancePerUpdate` | 30 words | Throttle limits for frame calculations |

## Extended External APIs

| Method | Purpose |
|--------|---------|
| `startSession()` | Initializes audio processing |
| `stopSession()` | Cleans background listeners |
| `togglePlayPause()` | Toggles manual scrolling metrics |

1. **Bypass Limits**: Maximum words allowed per single frame update cannot break boundaries.

- Never interrupt active layout listeners.
- Stale timers can occasionally cascade. Ensure safe clears.

```markdown
---
name: Teleprompter Engine MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Teleprompter Engine MVP â€” Windows

Governs the rendering architectures and hardware execution flags.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | Riverpod controller handling voice command prioritization and manual overrides. |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `_handleSttResult(...)` | Callback routers parsing active inputs. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Teleprompter UI | `teleprompter_screen.dart` | Listens to scrolling offsets. |

---

## Internal States & Tuning Constants

| Variable | Value / Type | Purpose |
|----------|--------------|---------|
| `_googleSkipAfterStuck` | 45 seconds | Wait bounds for STT stalls |
| `_whisperSkipAfterStuck` | 10 seconds | Wait bounds for custom isolates |
| `_maxAdvancePerUpdate` | 30 words | Throttle limits for frame calculations |

## Extended External APIs

| Method | Purpose |
|--------|---------|
| `startSession()` | Initializes audio processing |
| `stopSession()` | Cleans background listeners |
| `togglePlayPause()` | Toggles manual scrolling metrics |

---

## Invariants

1. **Bypass Limits**: Maximum words allowed per single frame update cannot break boundaries.

---

## Forbidden Changes

- Never interrupt active layout listeners.

---

## Known Fragilities

- Stale timers can occasionally cascade. Ensure safe clears.
```
