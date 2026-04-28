---
name: Bookmarks MVP
type: mvp
platform: Windows
last_updated: 2026-04-28
---

## Scope

Governs Windows script bookmarks: multiple saved anchors per script, editor
bookmark navigation, presenter bookmark navigation, persistence, and the
resume-point handoff between bookmark jumps and STT start/stop behavior.

---

## Owned Files

| File | Role |
| --- | --- |
| `Platform_Windows/lib/features/script/services/script_bookmark_service.dart` | Bookmark model, SharedPreferences scope key, load/save/upsert persistence |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | Editor add/remove/previous/next bookmark commands, editor position mapping, editor scroll-to-bookmark, editor marker rendering, presenter handoff identity |
| `Platform_Windows/lib/features/script/widgets/editor/suites/project_actions_mvp.dart` | Editor bookmark add/remove/navigation toolbar buttons |
| `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Presenter add/remove/previous/next bookmark commands, presenter word-index jumps, presenter marker rendering |
| `MASTER_TODO_V5.md` | Future presenter edit-from-current-position requirement |

---

## External API

| API | Allowed callers |
| --- | --- |
| `ScriptBookmarkService.scopeKey(String? sessionId, String title)` | Editor/presenter bookmark loaders |
| `ScriptBookmarkService.load(String key)` | Editor/presenter screen state |
| `ScriptBookmarkService.save(String key, List<ScriptBookmark> bookmarks)` | Editor/presenter screen state |
| `ScriptBookmarkService.upsert(List<ScriptBookmark>, ScriptBookmark)` | Bookmark add commands |
| `ScriptBookmark.wordIndex` | Presenter jumps and editor approximate cross-mode mapping |
| `ScriptBookmark.blockIndex` / `offset` | Editor-native exact jumps |

Anything not listed here is private implementation detail.

---

## All Callers

| Caller | Dependency |
| --- | --- |
| Script editor app bar | Adds/removes a bookmark at the current cursor/block and navigates previous/next bookmark |
| Presentation control bar | Adds/removes a bookmark at `confirmedWordIndex` and navigates previous/next bookmark while STT is stopped |
| Teleprompter provider | Receives bookmark jumps through `jumpToPosition(...)` only |
| SharedPreferences | Stores bookmarks under a script-scoped key derived from session id/title |

---

## Invariants

1. **Bookmarks are script-scoped**: Bookmarks must be stored under the script
   session id when available. Title fallback is allowed only when no session id
   exists.
2. **Multiple anchors are allowed**: A script may contain many bookmarks.
   Adding a bookmark must not erase other bookmarks for that script.
3. **Editor bookmarks use editor coordinates**: Editor-created bookmarks must
   save block index and raw offset so the editor can return to the same block.
4. **Presenter bookmarks use word coordinates**: Presenter-created bookmarks
   must save `wordIndex` so present mode can jump through
   `TeleprompterNotifier.jumpToPosition(...)`.
5. **Bookmark jumps preserve resume state**: Jumping to a bookmark updates the
   provider position and must make the next STT start resume from that point.
6. **Active STT owns the reading line**: Previous/next bookmark navigation in
   present mode is disabled while STT is listening or starting.
7. **Bookmark persistence is additive**: Saving bookmarks must write only the
   bookmark list for that script scope; it must not rewrite script text,
   history, recents, or settings.
8. **Cross-mode mapping is best effort**: When a bookmark lacks editor block
   coordinates, the editor may approximate from `wordIndex`, but must not mutate
   script text to make the mapping easier.
9. **Presenter handoff preserves identity**: Entering present mode from the
   editor must pass the current title and session id into `scriptProvider` so
   presenter mode loads the same bookmark scope that editor mode saved.
10. **Bookmarks are visible and removable**: Editor and present mode must render
    a visible marker such as `»` at saved bookmark positions. Selecting the
    marker deletes the bookmark from the shared script scope, and both editor
    and present mode must also expose an explicit remove-bookmark button. The
    marker is UI-only and must not be inserted into script text.
11. **Editor and presenter stay in sync**: Bookmarks created or deleted in
    present mode must be visible after returning to the editor. Bookmarks created
    or deleted in the editor must be visible after entering present mode.
12. **Bookmark jumps are direct**: Previous/next bookmark jumps in present mode
    must move directly to the saved anchor without the active-STT soft-follow
    animation.

---

## Forbidden Changes

- Do not reset `confirmedWordIndex` to zero when jumping to a bookmark.
- Do not use the restart button behavior for bookmark navigation.
- Do not clear the bookmark list when adding a new anchor.
- Do not allow present-mode bookmark navigation while STT is active unless the
  STT contract is explicitly updated.
- Do not store bookmarks inside visible script text or markup tags.
- Do not make bookmarks depend on debug mode.
- Do not enter presentation by rebuilding the script with a fresh session id
  when an editor session id already exists.
- Do not hide bookmark markers behind debug mode or search state.
- Do not leave bookmarks write-only. A visible marker and explicit remove button
  must expose deletion.
- Do not use estimated font-size scroll math when an exact editor block context
  is available.

---

## Known Fragilities

- Presenter-created bookmarks do not always have exact editor raw offsets.
  Editor fallback maps them from `wordIndex`, which can be approximate around
  heavy markup.
- Editor-created bookmarks preserve raw offsets; if text before the bookmark is
  heavily edited, the anchor may point near the original location rather than to
  semantic content.
- Bookmarks are local SharedPreferences data and are not yet part of export
  formats.

---

## Shared-File Ownership Notes

`script_editor_screen.dart` is shared with Script Editor, Selection, Styling,
History, and Editor Suites MVPs. Bookmark edits may touch only the bookmark
toolbar commands, editor coordinate mapping, and bookmark scroll/focus paths.

`teleprompter_screen.dart` is shared with Teleprompter Engine, STT, Settings,
and Scrolling MVPs. Bookmark edits may touch only bookmark buttons, bookmark
loading/saving, and stopped-session bookmark jumps.

Search is owned by Script Editor MVP, but bookmark handoff depends on the same
editor position mapping helpers. Search must match visible text and translate
back to raw markup offsets instead of treating hidden tags as visible
characters.
