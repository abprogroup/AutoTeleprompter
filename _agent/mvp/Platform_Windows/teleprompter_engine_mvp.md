---
name: Teleprompter Engine MVP
type: component
platform: Windows
last_updated: 2026-04-29
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
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.build.dart` | Extracted presenter build tree and word rendering; behavior-preserving V5 split |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.session_stt.dart` | Extracted session, WebView, keyboard, remote, and STT start/stop UI methods |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.manual_scroll.dart` | Extracted manual scroll, auto-follow target, stopped browsing, and resume sync methods |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.bookmarks_search.dart` | Extracted presenter bookmark and search methods shared with Bookmarks MVP |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.smooth_settings.dart` | Extracted smooth scroll tick and settings-sheet launcher |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.alignment_helpers.dart` | Extracted wrap-alignment helpers |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.audio_debug_widgets.dart` | Extracted sound bar and STT starting indicator widgets |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.control_bar.dart` | Extracted presenter control bar widget |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.settings_panel.dart` | Extracted presenter settings panel |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.settings_widgets.dart` | Extracted presenter settings helper widgets |
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
| `ScriptNotifier.updateStyleMetadata(fontSize: ...)` | Present-mode font size buttons and settings slider |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Presentation screen | `teleprompter_screen.dart` | Reads provider state, starts/stops/resets session |
| Control bar | `teleprompter_screen.dart` | Calls `stopSession()`, toggles manual presentation behavior locally |
| Settings panel | `teleprompter_screen.dart` | Reads/writes settings while presentation runs |
| Script provider | `script_provider.dart` | Receives present-mode font metadata updates so editor re-entry matches presenter changes |
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

20. **Active STT locks user browsing**: While `TeleprompterState.isListening` or
    `isStarting` is true, presentation scrolling must use
    `NeverScrollableScrollPhysics` for user input and word taps must not call
    `jumpToPosition(...)`. Bookmark previous/next controls are the allowed
    operator exception and must call `jumpToPosition(...)` directly. Other
    movement during active STT is provider-driven auto-follow from the confirmed
    word index.

21. **Debug console collapse is visual only**: Debug-mode minimize/expand changes
    only the debug output window height. It must not clear `debugLogs`, unmount
    STT processing, reset `soundLevel`, or move the resume point.

22. **Mic selection must not reset presentation position**: Choosing a Windows
    external microphone from the presenter settings panel may restart/reopen STT
    capture internals, but it must not call `resetPosition()`, clear
    `confirmedWordIndex`, scroll to the top, or discard the current resume
    point.

23. **Blank lines render as blank lines**: Hard newline markers (`\n\n`) in
    `script.words` must render with real vertical height based on presentation
    font size and line spacing. Present mode must not visually collapse multiple
    blank lines into a single tight gap.

24. **Presenter typography controls persist metadata**: Present-mode font size
    buttons, the presenter settings font-size slider, and presenter
    line/word/letter spacing sliders must update both `settingsProvider` and the
    active script metadata through `ScriptNotifier.updateStyleMetadata(...)`.
    Returning to the editor must show the same typography values in the font and
    layout suites.

25. **Presenter font size shares one metadata value**: Presenter controls,
    editor controls, settings provider, script metadata, and export all use the
    same saved font-size number. The teleprompter render path may enlarge that
    value for presenter readability, but it must never save the enlarged number
    back to metadata or display the enlarged number in controls.

26. **Default-relative spacing display**: Presenter line-spacing controls may
    store the real rendering value (`1.2` by default), but the visible value must
    show the user offset from default, so default reads `0.0`.

27. **Presenter spacing range matches the editor**: Present-mode line spacing
    must allow `0.5..3.0`, word spacing must allow `-5.0..20.0`, and letter
    spacing must allow `-2.0..5.0`, matching the Windows editor Layout Suite.
    Do not narrow presenter ranges independently.

28. **STT startup control is not a red stop state**: While
    `TeleprompterState.isStarting` is true and `isListening` is false, the
    central presenter control may show a loading/hourglass glyph, but it must
    not present as the red stop button or accept a second start/stop tap as if
    recognition were already active. Red means an active stoppable session.

29. **Visible skipping is opt-in and screen-bounded**: The default Windows STT
    behavior is no skip. If the presenter setting enables visible skipping, the
    screen must continuously publish the rendered visible word window, and STT
    alignment may land only inside that window. Hidden paragraphs must never be
    skipped to by speech alone.

30. **Visible means the whole viewport**: When visible skipping is enabled, STT
    may skip across any amount of text currently visible to the operator. Do not
    retain row-count, 30-word, or 1-2-line caps for multi-word sequence matches.
    Safety comes from the rendered viewport bound plus multi-word confirmation,
    not from a fixed distance limit.

31. **Local STT recovery is always allowed**: Even when visible skipping is off,
    the aligner may recover within the next 5-word local window so missed STT
    words do not stall the presenter. This is not considered paragraph skipping;
    longer jumps still require the visible-skip setting.

32. **Visible skip is fallback-only**: When visible skipping is enabled, the
    aligner must still prefer a strong nearby phrase match before jumping to a
    farther visible phrase. Similar text later in the viewport, such as another
    "at the well" phrase, must not steal focus from the current local sentence
    when the spoken words also match nearby.

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
- Do not allow drag scrolling or word-tap resume jumps while STT is listening or
  starting. Active STT owns the reading-line position except for explicit
  bookmark previous/next commands.
- Do not reduce hard blank-line markers to zero-height or half-hidden spacers in
  presentation mode.
- Do not make present-mode typography controls runtime-only. Font size and
  line/word/letter spacing must persist to the active script metadata that the
  editor font/layout suites read.
- Do not save presentation-enlarged font sizes back to settings, style tags, or
  script metadata. The stored number remains the editor/export/control number.
- Do not show raw `1.2` as the default line-spacing label in presenter settings;
  the UI label must display default-relative `0.0`.
- Do not give the presenter spacing sliders narrower bounds than the editor
  Layout Suite.
- Do not make the STT startup/hourglass state look like the red active stop
  state.
- Do not allow STT alignment to jump to offscreen text. Visible skipping is
  opt-in, and its maximum target must come from the presenter viewport.
- Do not let visible skipping bypass nearby phrase priority. Full-viewport
  skipping is allowed only after the local phrase-priority pass fails.

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
| Active STT auto-follow | Auto-follow remains enabled only while STT is listening; user drag scrolling and word-tap jumps are disabled during active/startup STT. |
| Windows external mic selector | Presentation settings can show discovered `audioinput` devices, persist selection, and apply the chosen input without resetting script position. |
| Blank-line rendering | Hard blank lines render at presentation line height so multiple newlines remain visible. |
| Visible STT skip | Disabled by default; when enabled, STT can jump only to a confident target visible in the current presenter viewport. |

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
last_updated: 2026-04-28
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
---

## Windows v4.1.12 Final Seal Notes

- Present mode is sealed with STT resume semantics: start resumes from the
  current confirmed/tapped/searched/bookmarked/scrolled position.
- Restart is the only command that resets to the beginning.
- Active STT owns presenter scrolling and user drag scrolling is locked while
  listening or starting.
- Stopped STT allows browsing and updates the resume point from the visible
  reading location.
- Search, bookmark previous/next, tap, and restart are direct navigation
  commands. They must not use the smooth STT-follow animation.
- Active STT follow uses row-progress smoothing to avoid hard row jumps while
  reading.
- Presenter controls share one font-size metadata value with editor mode;
  presenter visual enlargement is display-only and must not persist.
- Debug output can minimize/expand, and the sound bar remains mounted behind
  debug-mode opacity.

---

## V5 File Split Contract

The sealed Windows presenter screen was split into Dart `part` files on
2026-04-29 for surgical V5 development. This was a behavior-preserving move:
logic was moved into the same library so private state access remains identical.

Line-count ceiling after split:

| File | Lines |
|------|------:|
| `teleprompter_screen.dart` | 128 |
| `teleprompter_screen.build.dart` | 742 |
| `teleprompter_screen.session_stt.dart` | 415 |
| `teleprompter_screen.manual_scroll.dart` | 243 |
| `teleprompter_screen.bookmarks_search.dart` | 266 |
| `teleprompter_screen.settings_panel.dart` | 421 |
| Remaining teleprompter parts | Under 200 each |

Do not recombine these files. Future changes must edit the smallest owning part
file and the matching MVP docs.
