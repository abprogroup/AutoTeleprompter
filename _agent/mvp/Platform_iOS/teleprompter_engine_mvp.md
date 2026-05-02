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

---

## iOS Presenter Search Port - 2026-05-02

- Presenter search is owned by
  `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.search.dart`.
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
