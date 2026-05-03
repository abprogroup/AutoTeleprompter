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
| `Platform_iOS/lib/features/script/widgets/editor/suites/formatting_toolbar_mvp.dart` | Editor bookmark suite popup between History and Clear Styles |
| `Platform_iOS/lib/features/script/widgets/editor/suites/project_actions_mvp.dart` | Editor project/search/save/import actions; bookmark buttons must not live here |
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
- Editor bookmark actions are grouped into one bookmark suite popup in
  `FormattingToolbarMVP`, positioned between History and Clear Styles. Do not
  restore the four separate bookmark buttons to the project action row; that
  causes compact iOS toolbar overflow.
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
- Present-mode bookmark markers are floating UI anchored to the bookmarked
  word. They must not consume text-flow space or push script words around
  inside the row.
- Presenter markers use the paragraph direction, not the individual token
  direction, to choose their side: English/LTR paragraph anchors render outside
  the left edge of the word, Hebrew/RTL paragraph anchors render outside the
  right edge.
- Previous/next presenter bookmark navigation routes through
  `TeleprompterNotifier.jumpToPosition(...)`, so active-STT bookmark jumps are
  structurally supported and must be verified on device.
- Presenter-created bookmarks must store editor `blockIndex` and raw `offset`
  as well as `wordIndex`. Returning from present mode must force-reload editor
  bookmarks so presenter-created anchors appear in the editor without requiring
  a full app/session reload.
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

---

## iOS Boundary Mapping Repair - 2026-05-03

- Editor-created bookmarks at the start of a later block must attach to the
  first present-mode word in that block, not the second word.
- When converting editor raw block/offset to presenter `wordIndex`, tokenizing
  a prefix ending exactly with `\n` creates a phantom hard-break token for the
  empty trailing line. Subtract that phantom token before storing `wordIndex`.
- The raw editor coordinates (`blockIndex`, `offset`) remain the exact editor
  authority. The presenter `wordIndex` is only the teleprompter anchor derived
  from those editor coordinates.
- Present-mode bookmark markers must sit beside the anchor word, not above it.

---

## iOS Real-Word Bookmark Anchor Stabilization - 2026-05-03

- Bookmark anchors must resolve to readable `ScriptWord` entries, never to
  empty block/newline tokens. Empty editor blocks preserve layout only.
- Editor-created bookmarks at raw offset `0` of a text block must snap to that
  same block's first non-newline word in presenter mode.
- Presenter-created bookmarks must save editor `blockIndex` and raw `offset`
  for the exact word index when possible, so returning to editor does not place
  the marker in the previous empty block.
- The editor-to-presenter and presenter-to-editor mapping walks the actual
  block order and token cursor. Do not use substring tokenization loops that can
  drift around soft/hard blank-line tokens.
- Presenter `»` markers remain UI-only and must be vertically aligned beside
  the anchor word. LTR markers sit before/left of the word; RTL/Hebrew markers
  sit before/right of the word.
  Negative vertical offsets can make a before-word marker look like it belongs
  to the previous line and must be avoided.

---

## iOS Editor Inline Bookmark Marker - 2026-05-03

- Editor bookmark markers must render at the resolved raw editor offset, not as
  a generic page-side block flag.
- The marker remains metadata/UI only and must never be inserted into
  `controller.text`; script text, STT tokenization, copy/paste, export, and
  present-mode words must not receive a literal bookmark character.
- When exact editor anchors are available, delete marker taps must remove the
  exact bookmark id. The older block-level delete fallback may remain only for
  legacy cases with no resolved inline anchor.
- The marker is positioned from the same markup-aware `TextPainter` span used
  by the editor so hidden style tags do not shift the visual anchor.

---

## iOS Bookmark Marker Non-Overlap Rule - 2026-05-03

- Bookmark markers must never obscure readable script text in either editor or
  present mode.
- The visual marker must be the single right guillemet `\u00BB` / `»`, matching
  presenter and Windows behavior. Do not use mojibake literals such as `Â»` or
  `Ã‚Â»`.
- Presenter markers may reserve visual space beside the anchored word because
  presenter words are separate widgets. LTR markers reserve space before/left
  of the word; RTL/Hebrew markers reserve space before/right of the word.
- Editor markers must remain metadata/UI only and must not be inserted into
  `controller.text`. Because a standard editable `TextField` cannot reserve
  arbitrary inline metadata space without changing the text model, editor
  markers may use exact inline placement only when there is a safe whitespace or
  text-boundary gap. Otherwise they must fall back to a same-row margin marker
  that does not cover letters.
- Future work that attempts true text-flow bookmark glyphs must first replace
  or extend the editor renderer in a dedicated MVP pass and prove selection,
  raw markup offsets, clipboard, history, STT tokenization, and export remain
  unchanged.
