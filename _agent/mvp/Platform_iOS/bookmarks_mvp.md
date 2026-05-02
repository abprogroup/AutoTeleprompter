---
name: Bookmarks MVP
type: mvp
platform: iOS
last_updated: 2026-05-02
---

# Bookmarks MVP - iOS

## Scope

Implemented iOS migration target for Windows v4.1.12 bookmark behavior. Bookmarks
allow multiple script anchors that sync between editor and present mode, support
visible markers, explicit add/remove controls, previous/next navigation, and
active-STT jumps without resetting the session.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/services/script_bookmark_service.dart` | Bookmark model, SharedPreferences scope key, load/save/upsert persistence |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | Editor bookmark state fields, service import, bookmark part registration |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.bookmarks.dart` | Editor add/remove/previous/next commands, bookmark persistence, editor coordinate mapping, editor scroll-to-bookmark |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.file_present.dart` | Presenter handoff identity: passes title/source/session id and saves bookmarks before present mode |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.build.dart` | Editor toolbar/button wiring and bookmark marker coordination |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.editor_block.dart` | Visible `»` marker hit target and deletion affordance inside editor blocks |
| `Platform_iOS/lib/features/script/widgets/editor/suites/project_actions_mvp.dart` | Editor add/remove/previous/next bookmark buttons |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Presenter bookmark state fields, service import, bookmark part registration |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.bookmarks.dart` | Presenter load/save/add/remove/previous/next commands and direct jump execution |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.build.dart` | Presenter marker rendering and control wiring |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.control_bar.dart` | Add/remove/previous/next bookmark controls in present mode |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.manual_scroll.dart` | Existing direct-jump/scroll helper surface used by bookmark navigation |
| `_agent/mvp/Platform_iOS/script_editor_mvp.md` | Must document editor shared-file ownership before implementation |
| `_agent/mvp/Platform_iOS/teleprompter_engine_mvp.md` | Must document presenter shared-file ownership before implementation |

## External API

| API | Allowed callers |
|-----|-----------------|
| `ScriptBookmarkService.scopeKey(String? sessionId, String title)` | Editor/presenter bookmark loaders |
| `ScriptBookmarkService.load(String key)` | Editor/presenter screen state |
| `ScriptBookmarkService.save(String key, List<ScriptBookmark> bookmarks)` | Editor/presenter screen state |
| `ScriptBookmarkService.upsert(List<ScriptBookmark>, ScriptBookmark)` | Add-bookmark commands |
| `ScriptBookmark.wordIndex` | Presenter jumps and editor approximate cross-mode mapping |
| `ScriptBookmark.blockIndex` / `offset` | Editor-native exact jumps |
| `TeleprompterNotifier.jumpToPosition(...)` | Presenter bookmark jumps while STT is stopped or active |

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

After the 2026-04-29 iOS split, bookmark implementation must target the listed
part files rather than re-expanding the root screen files. Root files remain
shell/delegate files.

---

## iOS Implementation Notes - 2026-05-02

- iOS now mirrors the Windows shared bookmark persistence contract with
  `ScriptBookmarkService` under `Platform_iOS/lib/features/script/services/`.
- Editor bookmarks are created from the current focused block and raw cursor
  offset. They also save an approximate `wordIndex` for presenter handoff.
- Presenter bookmarks are created from `confirmedWordIndex`; when they lack
  editor coordinates, the editor maps them back from `wordIndex` as a best
  effort.
- Entering present mode from the editor now preserves `_currentTitle`,
  `_sourceType`, and `_currentSessionId` in `scriptProvider.loadText(...)`, so
  editor and presenter use the same bookmark scope.
- Visible `»` markers are UI-only. Tapping the marker deletes the bookmark;
  marker characters must never be inserted into script text.
- Previous/next presenter bookmark navigation routes through
  `TeleprompterNotifier.jumpToPosition(...)`, so active-STT bookmark jumps are
  structurally supported and must be verified on device.
- All implementation files remain below the 800-line split gate.

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
