---
name: Script Editor MVP
type: component
platform: iOS
last_updated: 2026-05-03
---

# Script Editor MVP - iOS

Governs iOS editor orchestration: active script state, block controllers,
gallery/editor handoff, save/import flow, and coordination with History,
Selection, Styling, File I/O, Settings, and Editor Suites.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | Editor shell, block lifecycle, controller wiring, save/import orchestration |
| `Platform_iOS/lib/features/script/widgets/script_gallery_screen.dart` | Recent scripts, open/delete/rename, restore metadata |
| `Platform_iOS/lib/features/script/widgets/teleprompt_selector_sheet.dart` | File/source selector and recent source preferences |
| `Platform_iOS/lib/features/script/providers/script_provider.dart` | `ScriptNotifier`, active `Script`, `loadText`, `importFile`, `parseFile`, `clear` |
| `Platform_iOS/lib/features/script/models/script.dart` | Script text, title, source/session/history/style metadata |
| `Platform_iOS/lib/features/script/models/script_word.dart` | Word token consumed by STT alignment and teleprompter rendering |
| `Platform_iOS/lib/features/script/models/editor_state.dart` | Editor history snapshot model |
| `Platform_iOS/lib/features/script/models/cursor_style.dart` | `cursorStyleProvider` bridge for suite state |
| `Platform_iOS/lib/features/script/widgets/editor/editor_dialogs.dart` | Rename/save/import dialogs |
| `Platform_iOS/lib/features/script/widgets/editor/lobby_settings_panel.dart` | Lobby/editor settings UI |

## External API

| Method / Field | Caller |
|----------------|--------|
| `scriptProvider` | Gallery, editor, teleprompter |
| `ScriptNotifier.loadText(...)` | New/open/import flows |
| `ScriptNotifier.importFile(File)` | File import entry points |
| `ScriptNotifier.parseFile(File)` | Import preview/error handling |
| `ScriptNotifier.clear()` | New/clear flows |
| `Script.rawText` | Rendering, save/export, markup transforms |
| `Script.words` | STT aligner and teleprompter |
| `Script.historyJson` / `historyIndex` | History restore/persistence |
| `cursorStyleProvider` | Editor suites and selection/style updates |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Teleprompter screen | `teleprompter_screen.dart` | Reads active script and style metadata |
| Teleprompter provider | `teleprompter_provider.dart` | Consumes `Script.words` for session advancement |
| Word aligner | `word_aligner.dart` | Consumes script words and normalized text |
| Settings provider | `settings_provider.dart` | Persists recent script and style/history metadata |
| Editor suites | `*_suite_mvp.dart` | Receive callbacks from editor screen |
| File I/O services | `docx_service.dart`, `rtf_service.dart`, `pages_service.dart` | Generate export bytes from markup |

## Invariants

1. `Script.rawText` and `MarkupController.text` preserve internal markup tags.
2. `Script.words` must be derived from the same text loaded into `rawText`.
3. Style metadata (`fontSize`, `fontFamily`, spacing, alignment, colors) and
   history metadata (`sessionId`, `historyJson`, `historyIndex`) travel through
   all open/save/import paths.
4. Controller creation, listener attachment, focus tracking, and disposal stay
   centralized in the editor screen.
5. Editor orchestration must not own STT.

## Forbidden Changes

- Do not strip markup from raw editor text as a generic cleanup.
- Do not bypass `ScriptNotifier.loadText()` for active-script replacement.
- Do not remove history metadata from recent-script JSON.
- Do not create history entries for cursor movement or selection-only changes.

## Known Fragilities

- `script_editor_screen.dart` is a large shared file with many MVP owners.
- Programmatic controller changes can trigger listener loops.
- Visible selection offsets diverge from raw markup offsets.
- Recent metadata, provider state, and editor local history can race.

## Shared-File Ownership Notes

History, Selection, Styling Engine, Editor Suites, and File I/O own sections
inside the editor screen; read those MVPs before editing their sections.

## Split File Ownership - 2026-04-29

This MVP was behavior-preservingly split for iOS V5 preparation. The split is
mechanical only: all private helpers remain in the same Dart library through
`part` files, and no in-app behavior is allowed to change because of the split.

| File | Split responsibility |
|------|----------------------|
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | Thin editor shell, imports, `part` declarations, widget/state fields, root lifecycle delegates |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.load_blocks.dart` | Pending file load, auto-save timer, dependency load, block/controller lifecycle, selection detection, cleanup body |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dialogs_history.dart` | Rename dialog, refined-text save body, clear-style command, history snapshots, undo/redo/apply state |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.styling_commands.dart` | Inline style, alignment, color, font, size, and command execution helpers |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.file_present.dart` | Import/save/clear flows, present-mode handoff, bottom action callbacks |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.build.dart` | Main editor build tree and debug sentry rendering |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.selection_clipboard.dart` | Clean selection, copy/cut/paste/select-all/delete, overlay resync |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.editor_block.dart` | `_EditorBlock` widget and block-level editing surface |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.search.dart` | Editor visible-text search, raw-offset mapping, search selection/jump behavior |

Split invariants:

1. The root file owns lifecycle order; extracted files must not call
   `super.dispose()` directly.
2. Extracted helpers must stay private to the same library unless a public API is
   intentionally added and documented.
3. Search/bookmark/font/export migrations must edit the smallest owning part
   file, not rebuild the monolithic screen.
4. Future feature ports must update this ownership table when ownership moves.

---

## Windows v4.1.12 Final Migration Target

When iOS editor work resumes, port these verified Windows editor contracts:

- Editor search must match visible text and then map back to raw markup offsets.
- Bookmarks must display visible markers, support add/remove/previous/next, and
  sync with present mode.
- Font-size controls must read and write the same metadata value used by present
  mode; editor visual scale must not create a second saved font number.
- Intentional blank lines, quotes, punctuation, and standalone symbols must be
  preserved while editing and when handing off to present mode.

---

## iOS Visible-Text Search Port - 2026-05-02

- Editor search is owned by
  `Platform_iOS/lib/features/script/widgets/script_editor_screen.search.dart`.
- Search protocol details belong in this MVP document, not as task-list
  narrative inside root editor code files.
- Search opens from the editor action bar and from `Ctrl/Meta+Shift+F`.
- Search must match visible text after markup stripping, not raw tag text.
- Match offsets must be translated back through
  `MarkupController.visualToRawOffset(...)` before setting the editor
  selection.
- Search must never place the cursor or selection inside `[color]`, `[size]`,
  `[font]`, alignment tags, `**`, or any other invisible markup token.
- Search clears global-selection overlay state before applying the match so
  highlight ownership does not leak from selection MVP into search behavior.
- Search result scrolling must use the block key / `Scrollable.ensureVisible`
  path and must not rebuild the editor into a monolith.

Additional search toolbar rules:

- Editor search owns a compact result toolbar, matching presenter search: back,
  next, counter, query label, new search, and close.
- A search builds all visible-text matches across all editor blocks. Next/back
  cycles the same result set without reopening the dialog.
- `Match whole word` is supported in the editor search dialog. Whole-word
  boundaries treat English letters, Hebrew letters, and digits as word
  characters; punctuation and whitespace are boundaries.
- Closing the search toolbar clears search UI state only. It must not clear the
  app-private cut/copy clipboard.

---

## iOS One Font-Size Authority Port - 2026-05-02

- Editor font-size controls must read the same persisted
  `settingsProvider.fontSize` / `Script.fontSize` metadata value used by
  present mode.
- Cursor inline `[size=...]` detection may still describe selected inline
  styling, but it must not become the global script font-size number shown by
  the Text Suite.
- `script_editor_screen.styling_commands.dart` owns the editor command that
  updates the global font-size metadata. It must call both
  `SettingsNotifier.setFontSize(...)` and
  `ScriptNotifier.updateStyleMetadata(fontSize: ...)`.
- `script_provider.dart` must not rebuild scripts with an old hardcoded
  `18.0` fallback when settings metadata is already available.
- Any visual scale difference between editor and presenter is render-only.
  It must not create a second saved font-size number.

---

## iOS Loaded-File Preservation Port - 2026-05-02

- `_getRefinedFullText()` must join editor blocks exactly with `\n`; it must
  not `trim()` the full script and remove intentional empty first/last blocks.
- Editor save/recent paths must preserve loaded-file blank lines, quotes,
  standalone punctuation, and symbols.
- Empty blocks can be meaningful file structure and must not be treated as
  cleanup noise.

---

## iOS App-Owned Selection Toolbar - 2026-05-03

- The editor screen now treats non-collapsed selected text as an app-owned
  script selection. `_EditorBlock` may let native iOS detect the initial word or
  range, but selected-text commands are presented by the app toolbar in
  `script_editor_screen.build.dart`.
- `script_editor_screen.editor_block.dart` must suppress native selected-text
  menus while global, overlay, or external app selection exists. This prevents
  UIKit from bypassing `_onCutClean()` / `_onCopyClean()`.
- The app toolbar is intentionally separate from `FormattingToolbarMVP`.
  Formatting suites remain the style/editing toolbar; selected-text Cut/Copy/
  Paste/Select All belongs to the Selection MVP.
- Editor taps, background taps, search jumps, bookmark jumps, imports, block
  splits/removals, undo/redo, and history jumps must clear transient selected
  text UI without clearing `_blockClipboard`.
