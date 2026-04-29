---
name: Teleprompter Engine MVP
type: component
platform: iOS
last_updated: 2026-04-29
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
