---
name: Teleprompter Engine MVP
type: component
platform: macOS
last_updated: 2026-04-27
---

# Teleprompter Engine MVP - macOS

Governs macOS presentation runtime: confirmed-word advancement, scrolling,
manual controls, presentation rendering, remote command handling at the screen
edge, and state consumed by the teleprompter UI. STT capture itself belongs to
STT MVP.

## Owned Files

| File | Role |
|------|------|
| `Platform_macOS/lib/features/teleprompter/providers/teleprompter_provider.dart` | `TeleprompterNotifier`, state, confirmed index, force-skip, session/reset/stop logic |
| `Platform_macOS/lib/features/teleprompter/models/alignment_result.dart` | `TeleprompterState` model and copy semantics |
| `Platform_macOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Presentation rendering, controls, settings panel, scroll animation, remote command subscription |
| `Platform_macOS/lib/features/teleprompter/services/word_aligner.dart` | Alignment output that drives confirmed-word advancement |

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

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Presentation screen | `teleprompter_screen.dart` | Reads provider state and starts/stops/resets |
| Control bar/settings panel | `teleprompter_screen.dart` | Mutates settings while presentation runs |
| STT callbacks | `teleprompter_provider.dart` | Call result handler after `SpeechResult` |
| Remote commands | `teleprompter_screen.dart` | Translate remote commands to provider/settings actions |

## Invariants

1. `confirmedWordIndex` must remain inside active script word bounds.
2. Voice commands are handled before word alignment.
3. Force-skip and max-advance thresholds prevent stalls and runaway jumps.
4. Stop is authoritative: callbacks after stop must not mutate visible state.
5. Rendering does not mutate script text.

## Forbidden Changes

- Do not move raw STT adapter lifecycle into the screen.
- Do not remove stop/reset/dispose guards.
- Do not restore remote mutations without reading Remote MVP.
- Do not mutate script text while rendering presentation mode.

## Known Fragilities

- Provider is multi-owner: STT, teleprompter, debug, remote, and settings meet.
- STT callbacks can arrive after dispose/stop.
- Apple speech callbacks are asynchronous and can lag UI transitions.

## Shared-File Ownership Notes

STT owns speech lifecycle sections in `teleprompter_provider.dart`; this MVP
owns confirmed-word state, presentation rendering, reset, stop, and scrolling.

## 2026-05-04 Windows 385911e Parity Port

The macOS presenter runtime now uses the split Windows/iOS-style widget
ownership:

- `teleprompter_screen.dart`: lifecycle/state fields and part declarations.
- `teleprompter_screen.build.dart`: presenter canvas, word rendering, overlays,
  controls, and search toolbar placement.
- `teleprompter_screen.bookmarks_search.dart`: presenter bookmark navigation,
  add/remove/sync, compact search toolbar, whole-word search, and direct
  `jumpToPosition` sync.
- `teleprompter_screen.manual_scroll.dart`: manual scrolling and resume-point
  sync while stopped.
- `teleprompter_screen.session_stt.dart`: macOS-safe permission/session
  dialogs and request/start flow.
- `teleprompter_screen.settings_panel.dart`: presenter settings, excluding
  Windows-only mic selectors.

Ported runtime behavior includes resume/restart presentation choice, compact
presenter search with previous/next/new/close controls, whole-word matching,
visible text skip with safe local STT recovery, bookmark add/remove sync with
editor text-flow signs, and active presenter jumps that update provider state.

macOS intentionally keeps Apple-native STT. Do not add Windows WebView2,
Windows mic picker UI, `setx`, Windows Settings links, or Windows speech-pack
fallback dialogs here.

## 2026-05-05 Windows v4.1.14 Presenter Port Implemented

macOS presenter parity now includes:

- continuous imported DOCX underline/highlight painting behind/over presenter
  words, instead of fragmented word backgrounds/underlines;
- bookmark sign taps select/jump to the bookmark position and no longer delete
  a bookmark directly;
- active STT hides presenter controls; bottom hover reveals controls without
  jumping the script or changing the resume point;
- strict bullet/header STT and visible-skip relock behavior from Windows
  v4.1.14, adapted through Apple STT.

macOS runtime verification is still user/device QA; local Windows-side checks
cover tests/analyzer only.
