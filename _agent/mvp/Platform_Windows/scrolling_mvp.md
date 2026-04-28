---
name: Scrolling MVP
type: mvp
platform: Windows
last_updated: 2026-04-28
---

## Scope

Governs Windows presenter scrolling: active-STT auto-follow, stopped-session
browsing, manual timed scrolling, search/bookmark jumps, reading-line targeting,
and smooth motion rules for the presentation viewport.

---

## Owned Files

| File | Role |
| --- | --- |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Scroll controller, active STT auto-follow, smooth glide timer, stopped browsing, manual scroll, search/bookmark jump scroll |
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | `confirmedWordIndex`, `jumpToPosition(...)`, reset/start/stop state that drives presenter scroll |
| `Platform_Windows/lib/features/settings/providers/settings_provider.dart` | `scrollLead`, `scrollMode`, and `scrollSpeed` persisted settings |
| `_agent/mvp/Platform_Windows/teleprompter_engine_mvp.md` | Parent presentation engine contract |
| `_agent/mvp/Platform_Windows/bookmarks_mvp.md` | Bookmark jumps that reuse presenter scroll |

---

## External API

| API | Allowed callers |
| --- | --- |
| `_scrollToWordIndex(int index, {bool anticipate = false})` | Presenter search, bookmark, resume, and STT index listener |
| `_anticipatoryScrollIndex(int index)` | Active-STT auto-follow only |
| `_smoothScrollTick(Timer timer)` | Smooth scroll timer only |
| `_handleStoppedBrowsingScroll(ScrollNotification)` | Presentation `NotificationListener` |
| `_syncResumePointToReadingLine()` | Stopped-session scroll end only |
| `TeleprompterNotifier.jumpToPosition(int index, {Script? script})` | Search, bookmark, word tap, stopped scroll sync |
| `AppSettings.scrollLead` | Reading-line target |
| `AppSettings.scrollMode` | Auto/manual scroll branch |
| `AppSettings.scrollSpeed` | Manual timed scroll only |

Anything not listed here is private implementation detail.

---

## All Callers

| Caller | Dependency |
| --- | --- |
| STT confirmed-word listener | Calls anticipatory `_scrollToWordIndex(..., anticipate: true)` while listening |
| Word tap in present mode | Calls `jumpToPosition(...)` and exact scroll while STT is stopped |
| Present search | Calls bookmark-equivalent exact scroll to the found word |
| Bookmark navigation | Calls exact scroll to saved `wordIndex` while STT is stopped |
| Manual scroll controls | Use pixel timer and local `_manualWordIndex` without mutating STT transcript |
| Stopped user drag | Cancels stale smooth target and syncs resume point at scroll end |

---

## Invariants

1. **Active STT locks user scrolling**: While `isListening` or `isStarting` is
   true, the presenter scroll view must use non-user-scrollable physics.
2. **Stopped mode allows browsing**: When STT is stopped, user drag scrolling is
   allowed and must not be pulled back to an old STT target.
3. **Stopped browsing updates resume point**: On stopped scroll end, the nearest
   word to the reading line must become the next `confirmedWordIndex`.
4. **STT auto-follow is anticipatory**: Active STT should target a small number
   of readable words ahead of the confirmed word so the viewport starts moving
   before a row is fully completed.
5. **Smooth motion is bounded**: The smooth timer must move toward `_scrollTarget`
   with small bounded frame steps, not large `animateTo` row jumps.
6. **Exact jumps stay exact**: Search, bookmark, tap, reset, and initial resume
   may target the exact requested word; anticipatory targeting belongs only to
   active STT follow.
7. **Manual mode is local**: Manual timed scrolling must not corrupt provider
   transcript, accumulated STT text, or `confirmedWordIndex` except through
   explicit resume sync.
8. **Reading line remains the anchor**: Scroll calculations must continue to use
   `scrollLead` as the viewport anchor.

---

## Forbidden Changes

- Do not call `_scrollToWordIndex()` from stopped user-scroll notifications.
- Do not use `animateTo` row jumps for every STT word advancement.
- Do not allow word taps, drag browsing, or bookmark previous/next jumps while
  STT is listening/starting.
- Do not reset the provider index as a side effect of smooth scrolling.
- Do not make manual scroll speed change the STT auto-follow speed.
- Do not collapse blank-line markers to zero-height spacers; they affect scroll
  rhythm and visual structure.

---

## Known Fragilities

- Anticipatory scrolling uses a fixed lookahead count. Very large fonts, very
  short lines, or mixed RTL/LTR rows may need future tuning.
- The smooth timer uses `jumpTo` frame steps rather than Flutter physics; this
  is deliberate for deterministic teleprompter movement, but it must be watched
  for frame pacing on weak machines.
- Stopped resume sync depends on visible `GlobalKey` contexts. Very long scripts
  with offscreen words should not use this path for hidden elements.

---

## Shared-File Ownership Notes

`teleprompter_screen.dart` is section-owned by Teleprompter Engine, STT,
Settings, Bookmarks, and Scrolling MVPs. Scrolling owns only scroll target
calculation, timers, scroll notifications, scroll physics, and viewport motion.

`teleprompter_provider.dart` remains owned primarily by STT and Teleprompter
Engine. Scrolling may read or call `confirmedWordIndex`/`jumpToPosition(...)`
but must not move transcript or recognizer lifecycle state into the widget.

