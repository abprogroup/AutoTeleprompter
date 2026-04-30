---
name: Scrolling MVP
type: planned-feature
platform: iOS
last_updated: 2026-04-29
---

# Scrolling MVP - iOS

## Scope

Planned iOS migration target for Windows v4.1.12 presenter scrolling. Active
STT owns auto-follow, stopped STT allows browsing and resume selection, and
bookmark/search/restart commands jump directly.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Planned scroll controller, reading-line anchor, user-scroll lock, direct navigation, row-progress follow |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.manual_scroll.dart` | Planned scroll controller helpers, smooth-follow loop, user-scroll gating, direct jump execution |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.build.dart` | Planned visible word/window publication and viewport/rendering data consumed by skip logic |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.control_bar.dart` | Planned controls that trigger direct navigation or restart/reset |
| `Platform_iOS/lib/features/teleprompter/providers/teleprompter_provider.dart` | Confirmed index and `jumpToPosition(...)` provider state consumed by scroll UI |
| `_agent/mvp/Platform_iOS/teleprompter_engine_mvp.md` | Presenter ownership coordination |
| `_agent/mvp/Platform_iOS/stt_mvp.md` | STT lifecycle and active-state coordination |

## External API

| API | Allowed callers |
|-----|-----------------|
| `confirmedWordIndex` | Presenter scroll target calculations |
| `jumpToPosition(...)` | Bookmark/search/tap/restart direct navigation |
| `scrollLead` | Reading-line anchor calculation |

## All Callers

| Caller | Dependency |
|--------|------------|
| STT confirmed-word listener | Row-progress auto-follow while active |
| Bookmark navigation | Direct exact jumps |
| Present search | Direct exact jumps |
| User drag | Stopped-mode browsing and resume selection |

## Invariants

1. Active STT locks user drag scrolling.
2. Stopped STT allows browsing.
3. Stopped browsing updates the resume point.
4. STT auto-follow should move progressively through the row, not snap only at
   row boundaries.
5. Bookmark/search/restart jumps are exact and immediate.
6. Blank-line markers must keep real height because they affect scroll rhythm.

## Forbidden Changes

- Do not allow user drag scrolling while STT is listening or starting.
- Do not use active-STT smooth follow for bookmark/search/restart jumps.
- Do not reset provider indices as a side effect of scroll motion.
- Do not collapse intentional blank lines to zero height.

## Known Fragilities

- iOS keyboard and selection overlays can affect available viewport height.
- Mixed RTL/LTR rows may need platform-specific row-progress tuning.
- Very large fonts may require tuning the reading-line anchor.

## Shared-File Ownership Notes

`teleprompter_screen.dart` is shared by Teleprompter Engine, STT, Settings,
Bookmarks, and Scrolling. Scrolling owns scroll physics, target calculations,
and user-scroll lock only.

After the 2026-04-29 iOS split, scrolling implementation must target the listed
part files rather than re-expanding the root screen file. Root files remain
shell/delegate files.

---

## Windows v4.1.12 Final Migration Target

The final Windows scrolling baseline is user verified and must be the iOS
target:

- Active STT locks user drag scrolling.
- Active STT uses row-progress follow instead of hard row snaps.
- Stopped STT allows free browsing.
- Stopped browsing updates the resume point nearest the reading line.
- Bookmark/search/restart/direct jumps are exact and immediate.
- Visible-skip support depends on the presenter publishing the rendered visible
  word window; hidden/offscreen text must not become a speech skip target.
- The visible-skip window is the viewport bound, but matching must still prefer
  nearby 3+ word phrase matches before farther similar text.

---

## iOS Active-STT Scroll Lock + Row-Progress Follow + Stopped Browsing - 2026-04-30

- The presenter `SingleChildScrollView` flips its physics to
  `NeverScrollableScrollPhysics` whenever `tState.isListening || isStarting`.
  The wrapping `NotificationListener` calls `_handleStoppedBrowsingScroll`,
  which is a no-op during that window. Result: the active reading position
  never leaves the screen while STT is live or starting.
- `_scrollToWordIndex(index)` adds `rowProgress * lineAdvance` to the scroll
  target. `_visualRowProgress` computes the fractional position of `index`
  inside its visual row using a Y-tolerance walk over `_wordKeys`. Result:
  the auto-scroll glides smoothly across each row, no row-end snapping.
- Stopped state: drag-scroll is allowed. On `ScrollEndNotification`, the
  presenter syncs the visible word window (`_syncVisibleWordWindow`) and the
  resume point (`_syncResumePointToReadingLine`), which routes the chosen
  word index through `jumpToPosition` so `state.confirmedWordIndex` reflects
  where the user landed. Mic start then resumes from there.
- Restart remains the only owner of `confirmedWordIndex = 0`.
- Forbidden regression: do not allow drag-scroll while `isStarting` is true.
  Startup is part of the active-STT window — releasing the lock too early
  lets the reading position drift before the first STT status arrives.
