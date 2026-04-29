---
name: Bookmarks MVP
type: planned-feature
platform: iOS
last_updated: 2026-04-29
---

# Bookmarks MVP - iOS

## Scope

Planned iOS migration target for Windows v4.1.12 bookmark behavior. Bookmarks
allow multiple script anchors that sync between editor and present mode, support
visible markers, explicit add/remove controls, previous/next navigation, and
active-STT jumps without resetting the session.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | Planned editor bookmark marker rendering, add/remove/previous/next controls, visible-text coordinate mapping, presenter handoff identity |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Planned presenter bookmark controls, marker rendering, direct jump behavior, active-STT bookmark jumps |
| `Platform_iOS/lib/features/script/services/script_bookmark_service.dart` | Planned shared persistence service mirroring the Windows baseline |
| `_agent/mvp/Platform_iOS/script_editor_mvp.md` | Must document editor shared-file ownership before implementation |
| `_agent/mvp/Platform_iOS/teleprompter_engine_mvp.md` | Must document presenter shared-file ownership before implementation |

## External API

| API | Allowed callers |
|-----|-----------------|
| `ScriptBookmarkService.scopeKey(...)` | Planned editor/presenter bookmark loaders |
| `ScriptBookmarkService.load(...)` | Planned editor/presenter screen state |
| `ScriptBookmarkService.save(...)` | Planned editor/presenter screen state |
| `ScriptBookmarkService.upsert(...)` | Planned add-bookmark commands |
| `TeleprompterNotifier.jumpToPosition(...)` | Planned presenter bookmark jumps while STT is stopped or active |

## All Callers

| Caller | Dependency |
|--------|------------|
| Editor project/action toolbar | Add/remove/previous/next bookmark commands |
| Editor block list | Visible marker rendering and deletion |
| Presenter controls | Add/remove/previous/next bookmark commands |
| Presenter word renderer | Visible marker rendering and deletion |
| STT provider | Resume-point update after active bookmark jump |

## Invariants

1. Bookmarks are script/session metadata, not visible script text.
2. Bookmarks created in editor must appear in present mode.
3. Bookmarks created in present mode must appear when returning to editor.
4. Previous/next bookmark jumps must remain available while STT is active.
5. Bookmark jumps are direct navigation commands, not smooth scroll animations.
6. Removing a bookmark must be possible from a visible marker and an explicit
   remove button.
7. Bookmark navigation must preserve STT resume state.

## Forbidden Changes

- Do not insert bookmark marker characters into script text.
- Do not disable bookmark navigation while STT is active.
- Do not reset to word `0` as a side effect of bookmark navigation.
- Do not implement presenter-only bookmarks that editor cannot see.
- Do not use rough font-size scroll guesses when exact block contexts exist.

## Known Fragilities

- iOS selection/keyboard behavior is sensitive; bookmark controls must not steal
  or corrupt active text selection.
- Present-mode active-STT jumps must coordinate with iOS STT locale switching
  and audio-buffer plans.
- Exact editor mapping may drift after heavy edits before the bookmark anchor;
  preserve visible marker deletion and explicit remove fallback.

## Shared-File Ownership Notes

`script_editor_screen.dart` is shared with Script Editor, Selection, Styling,
History, and Editor Suites. Bookmark changes may touch only bookmark controls,
marker rendering, persistence handoff, and coordinate mapping.

`teleprompter_screen.dart` is shared with Teleprompter Engine, STT, Settings,
and Scrolling. Bookmark changes may touch only controls, markers, bookmark
loading/saving, and jump calls.

---

## Windows v4.1.12 Final Migration Target

The final Windows bookmark baseline is user verified and must be the iOS target:

- Multiple anchors per script/session.
- Visible marker signs in editor and presenter.
- Explicit add/remove controls in editor and presenter.
- Marker deletion must be possible without editing script text.
- Editor-created bookmarks must appear in presenter.
- Presenter-created bookmarks must appear when returning to editor.
- Previous/next bookmark jumps must work while STT is active.
- Bookmark jumps are immediate direct navigation commands and must not use the
  smooth STT follow animation.
- Bookmark jumps must preserve STT session state and resume point.
