---
name: Teleprompter Engine MVP
type: component
platform: iOS
last_updated: 2026-05-02
---

# Teleprompter Engine MVP - iOS

Governs iOS presentation runtime: confirmed-word advancement, scrolling,
manual controls, presentation rendering, remote command handling at the screen
edge, and state consumed by the teleprompter UI. STT capture itself belongs to
STT MVP.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/teleprompter/providers/teleprompter_provider.dart` | `TeleprompterNotifier`, state, confirmed index, force-skip, session/reset/stop logic |
| `Platform_iOS/lib/features/teleprompter/models/alignment_result.dart` | `TeleprompterState` model and copy semantics |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Presentation rendering, controls, settings panel, scroll animation, remote command subscription |
| `Platform_iOS/lib/features/teleprompter/services/word_aligner.dart` | Alignment output that drives confirmed-word advancement |

## External API

| Method / Field | Caller |
|----------------|--------|
| `teleprompterProvider` | `TeleprompterScreen` |
| `startSession(Script script)` | Mic/play/start flow |
| `stopSession()` | Mic button, back navigation, dispose |
| `resetPosition()` | Restart/reset UI |
| `TeleprompterState.confirmedWordIndex` | Highlight and scroll target |
| `TeleprompterState.isListening` | Mic/control state |
| `TeleprompterState.statusMessage` / `hasError` | Errors and dialogs |
| `TeleprompterState.missingLanguage` | iOS speech language prompt |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Presentation screen | `teleprompter_screen.dart` | Reads provider state and starts/stops/resets |
| Control bar/settings panel | `teleprompter_screen.dart` | Mutates settings while presentation runs |
| STT callbacks | `teleprompter_provider.dart` | Call `_handleSttResult()` after `SpeechResult` |
| Remote commands | `teleprompter_screen.dart` | Translate remote commands to provider/settings actions |

## Invariants

1. `confirmedWordIndex` must remain inside active script word bounds.
2. Voice commands are handled before word alignment.
3. Force-skip and max-advance thresholds prevent stalls and runaway jumps.
4. Fluid-advance timers must be canceled on stop, reset, dispose, or new target.
5. Stop is authoritative: callbacks after stop must not mutate visible state.
6. Rendering does not mutate script text.

## Forbidden Changes

- Do not move raw STT adapter lifecycle into the screen.
- Do not remove timer cancellation from stop/reset/dispose.
- Do not allow a single STT update to jump past documented thresholds.
- Do not restore remote mutations without reading Remote MVP.

## Known Fragilities

- Provider is multi-owner: STT, teleprompter, debug, remote, and settings meet.
- STT callbacks can arrive after dispose/stop.
- Large alignment jumps can disorient users without fluid advance.
- iOS speech callbacks are asynchronous and can lag UI transitions.

## Shared-File Ownership Notes

STT owns speech lifecycle sections in `teleprompter_provider.dart`; this MVP
owns confirmed-word state, presentation rendering, reset, stop, and scrolling.

## Split File Ownership - 2026-04-29

This MVP was behavior-preservingly split for iOS V5 preparation. The split is
mechanical only: all private helpers remain in the same Dart library through
`part` files, and no in-app behavior is allowed to change because of the split.

| File | Split responsibility |
|------|----------------------|
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Thin presenter shell, imports, `part` declarations, widget/state fields, root lifecycle delegates, alignment helpers |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.session_stt.dart` | Remote listener lifecycle, STT start request, missing-language dialog, error text, control visibility timer, cleanup body |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.manual_scroll.dart` | Manual scroll helpers, smooth scroll loop, runtime settings launch/update helpers |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.build.dart` | Main presenter build tree, highlighted word rendering, overlay structure |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.search.dart` | Presenter search dialog, visible text phrase mapping, direct jump to word index |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.control_bar.dart` | `_ControlBar` presentation controls |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.settings_panel.dart` | `TeleprompterSettingsPanel`, presets, color grid, runtime display settings |

Split invariants:

1. The root file owns lifecycle order; extracted files must not call
   `super.dispose()` directly.
2. Session cleanup, timer cancellation, and remote subscription cleanup stay in
   the cleanup body called by root `dispose()`.
3. STT migration work must respect STT MVP ownership and may not move adapter
   lifecycle into the screen.
4. Scrolling/bookmark/search migrations must edit the smallest owning part file
   and preserve direct-navigation versus smooth-follow boundaries.
5. Future feature ports must update this ownership table when ownership moves.

---

## Windows v4.1.12 Final Migration Target

Before changing iOS presentation runtime, preserve iOS STT/keyboard/remote
fragilities above and port these final Windows product contracts:

- Active STT owns scrolling and locks normal user drag scrolling.
- Stopped STT allows browsing and updates the resume point.
- Bookmark/search/restart/direct navigation jumps immediately; these are not
  smooth row-follow animations.
- Default STT local recovery may recover up to 5 words.
- Longer visible skip requires an opt-in presenter setting, must stay inside
  the rendered visible viewport, and must prefer nearby 3+ word phrase matches
  before jumping to farther similar visible text.
- Presenter search and word/bookmark jumps update `confirmedWordIndex` through
  the provider and must preserve locale/session state.
- Font size has one persisted metadata value shared with the editor; any
  presenter visual enlargement is display-only and must not be written back.
- Blank lines, quotes, standalone symbols, and punctuation are display content
  and must not be dropped during rendering or tokenization.

---

## iOS Stop/Resume Parity - 2026-04-30

- Presentation entry no longer resets the provider position. It may stop a
  lingering recognizer for safety, but it must preserve `confirmedWordIndex`.
- If the provider already holds a non-zero `confirmedWordIndex`, the presenter
  scrolls back to that word after layout instead of jumping to the top.
- Restart remains the only present-mode control that resets the provider to word
  `0` and scrolls to the beginning.
- Future stopped-browsing and bookmark/search work must reuse this same
  position-preservation contract rather than adding separate reset paths.

### 2026-05-02 resume prompt update

- Re-entering present mode at a non-zero `confirmedWordIndex` shows a
  resume/restart choice.
- Continue keeps the current position and scrolls to it.
- Restart is the only dialog action that calls `resetPosition()` and scrolls
  to the beginning.
- Mic start after re-entry must use the same resume point selected by this
  prompt; it must not reset internally to word `0`.

---

## iOS Presenter Search Port - 2026-05-02

- Presenter search is owned by
  `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.search.dart`.
- Windows-parity task labels and behavioral protocol belong in MVP documents,
  not in presenter root/build/provider comments. Code comments should stay
  implementation-local and concise.
- Search opens from the control bar and from `Ctrl/Meta+Shift+F` when a
  hardware keyboard can focus the presentation screen.
- Search must build its phrase map from visible word text, after stripping
  internal markup and alignment tags.
- Search jumps through the provider position path used by bookmarks so
  `confirmedWordIndex`, resume point, locale/alignment state, and scroll target
  stay synchronized.
- Presenter search is direct navigation. It must not reuse the smooth STT
  row-follow animation that is reserved for normal live reading progress.
- Search must skip newline/display-empty tokens as match anchors while still
  preserving those tokens in rendering.

---

## iOS One Font-Size Authority Port - 2026-05-02

- Presenter settings and A-/A+ controls must update the same
  `settingsProvider.fontSize` / `Script.fontSize` metadata value shown by the
  editor Text Suite.
- `teleprompter_screen.settings_panel.dart` must label font size with the raw
  saved metadata number, not `fontSize * 2`.
- `teleprompter_screen.control_bar.dart` must persist font-size button changes
  through both `SettingsNotifier.setFontSize(...)` and
  `ScriptNotifier.updateStyleMetadata(fontSize: ...)`.
- Presenter rendering may still multiply the saved value for readable display,
  but that multiplier is display-only and must never be written back to script
  metadata.

---

## iOS Synced Spacing Ranges Port - 2026-05-02

- `teleprompter_screen.settings_panel.dart` owns present-mode spacing controls.
- Presenter spacing controls must use the same ranges as the editor Layout
  Suite: line `0.5..3.0`, word `-5.0..20.0`, letter `-2.0..5.0`.
- Present-mode spacing changes must call both the Settings setter and
  `ScriptNotifier.updateStyleMetadata(...)` so returning to the editor shows
  the same script metadata values.
- Line spacing labels must show default-relative values, where saved `1.2`
  appears as `0.0`.

---

## iOS Loaded-File Preservation Port - 2026-05-02

- Presenter tokenization must preserve punctuation-only display tokens such as
  `"`, `»`, section marks, and other visible symbols even when their STT
  normalized text is empty.
- Such display-only tokens remain unspeakable for alignment, but they must stay
  in `Script.words` so present mode can render the same visible file content
  the user loaded.
- Newline tokens remain renderable layout structure and must not be dropped to
  make STT matching simpler.

---

## iOS Present-Mode Speech Input Selector - 2026-05-02

- `teleprompter_screen.settings_panel.dart` owns the visible Speech Input
  selector in present settings.
- The selector shows System Default plus routes reported by
  `TeleprompterState.audioInputDevices`.
- Selecting a route calls `TeleprompterNotifier.setSttInputDevice(...)` and
  `SettingsNotifier.setSttInputDevice(...)`.
- Mic route changes must not reset `confirmedWordIndex`, bookmarks, search
  state, or presenter scroll position.
- The selector is an iOS `AVAudioSession` route selector, not a Windows WebView
  media-device picker.

---

## iOS Present Toolbar Layout - 2026-05-02

- `teleprompter_screen.control_bar.dart` owns present-mode control layout.
- The control bar uses two rows to avoid overflow on compact iOS screens.
- Top row owns back, previous bookmark, add bookmark, remove bookmark, next
  bookmark, and search.
- Bottom row owns font decrease, mic/play/stop, font increase, settings, and
  restart.
- Do not restore all controls into one horizontal row unless the control set is
  redesigned for responsive wrapping.

---

## iOS Visible Skip Toggle - 2026-05-02

- Present settings expose `Allow visible text skip`.
- The setting remains off by default and may only widen STT matching to the
  currently rendered visible word window when explicitly enabled.
- Default local recovery remains separate from visible skip and must stay
  active even when the visible skip switch is off.

---

## iOS Presenter Search Toolbar - 2026-05-02

- `teleprompter_screen.search.dart` owns presenter search state, result
  collection, and result navigation.
- A presenter search must build all visible-text matches for the submitted
  query, show a compact in-present toolbar, and let the user move previous/next
  through that same result set without reopening the search dialog.
- The toolbar must expose four small actions: previous result, next result,
  search new text, and close toolbar.
- Search-result jumps remain direct navigation through the same provider
  position path used by bookmarks so the resume point and scroll target stay
  synchronized.
- Closing the toolbar clears only transient result navigation state; it must not
  alter the last script position, bookmarks, STT session, or loaded script.
- Presenter search dialog supports `Match whole word`. Whole-word boundaries
  treat English letters, Hebrew letters, and digits as word characters while
  punctuation, whitespace, quotes, and marker symbols are boundaries. This
  option must not change direct search-result navigation or the existing
  next/back toolbar.

---

## Deferred STT Visible Skip Language Boundary - 2026-05-03

- The next STT task is visible-skip across language changes. Example: Hebrew
  block, English block, Hebrew block. When visible skip is enabled, STT must be
  able to consider visible text in a later language block and trigger the
  required locale transition before the reader reaches the previous block end.
- This search/bookmark pass must not edit STT matching or locale-switching
  logic. The language-boundary skip requires a separate STT MVP update and
  physical-device test.

---

## iOS Presenter Bottom Controls Fade - 2026-05-02

- `teleprompter_screen.build.dart` owns the control-overlay backing fade.
- The two-row presenter controls and search toolbar must sit on a dark
  bottom-to-top fade so script text cannot visually hide icon buttons.
- `teleprompter_screen.control_bar.dart` keeps the mic/start control centered
  in the lower row by placing settings at the left edge, then font decrease,
  mic/play/stop, font increase, and restart.
- The upper control row must continue to expose the search button alongside
  back and bookmark controls.
