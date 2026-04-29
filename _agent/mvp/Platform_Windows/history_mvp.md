---
name: History MVP
type: component
platform: Windows
last_updated: 2026-04-29
---

# History MVP - Windows

Governs the Windows undo/redo stack, history list UI, persisted history JSON,
history index recovery across gallery re-entry, typing bulking, and suite
section commits.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | `_history`, `_historyIndex`, `_undo`, `_redo`, `_jumpToHistory`, `_saveHistory`, `_commitHistory`, `_forceRecentUpdate`, history timers and guard flags |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dialogs_history.dart` | Extracted history stack, undo/redo, state restore, refined text, and commit helpers after V5 file split |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.load_blocks.dart` | Extracted initial load and pending file load paths that create/restore history entries |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.file_present.dart` | Extracted import/save/clear/present paths that commit or preserve history metadata |
| `Platform_Windows/lib/features/script/widgets/editor/suites/history_suite_mvp.dart` | Undo/redo buttons and history popup UI |
| `Platform_Windows/lib/features/script/widgets/editor/suites/formatting_toolbar_mvp.dart` | Passes history state and callbacks to `HistorySuite` |
| `Platform_Windows/lib/features/script/models/editor_state.dart` | Serialized history snapshot model |
| `Platform_Windows/lib/features/script/models/script.dart` | `historyJson` and `historyIndex` fields |
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | Restores/persists history metadata through `loadText()` and `saveScript()` |
| `Platform_Windows/lib/features/script/widgets/script_gallery_screen.dart` | Opens recent scripts and must pass history metadata |
| `Platform_Windows/lib/features/settings/providers/settings_provider.dart` | Stores `lastHistoryIndex`, recent entry `historyIndex`, and `historyJson` |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `_undo()` | Formatting toolbar undo button |
| `_redo()` | Formatting toolbar redo button |
| `_jumpToHistory(int idx)` | `HistorySuite` popup selection |
| `_saveHistory({description, debounce})` | Text, style, import, clear, cut/delete, settings changes |
| `_commitHistory(String description)` | Suite commits and immediate actions |
| `canUndo` / `canRedo` | `FormattingToolbarMVP` button state |
| `_history` / `_historyIndex` | `HistorySuite` display and selection |
| `EditorState.toJson()` / `fromJson()` | History persistence and restore |
| `Script.historyJson` / `historyIndex` | Provider/gallery/editor handoff |
| `SettingsNotifier.saveScript(... historyIndex, historyJson ...)` | Recent metadata persistence |

---

## V5 File Split Notes

History code was moved out of the monolithic editor into same-library parts.
Future undo/redo, history JSON, suite checkpoint, recent-save, and state-restore
edits should start in `script_editor_screen.dialogs_history.dart`, then inspect
`load_blocks` and `file_present` only for load/save entry points.

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Text typing | `script_editor_screen.dart` | `_onBlockChanged()` calls `_saveHistory(... debounce: true)` |
| Style commands | `script_editor_screen.dart` | `_applyStyleCmd`, `_applyInlineCmd`, clear format call history saves |
| Layout commands | `script_editor_screen.dart` | `onAlign`, `onDirection`, layout interactions commit sections |
| Import/load | `script_editor_screen.dart` | `_runPendingFileLoad()` and initial load save history |
| Toolbar | `formatting_toolbar_mvp.dart` | Receives `history`, `historyIndex`, `canUndo`, `canRedo`, callbacks |
| History popup | `history_suite_mvp.dart` | Calls `onHistorySelected(idx)` |
| Settings provider | `settings_provider.dart` | Saves `historyIndex` and `historyJson` into recent metadata |
| Script provider/gallery | `script_provider.dart`, `script_gallery_screen.dart` | Restore saved history on re-entry |

---

## Invariants

1. **History index is always valid**: When `_history` is non-empty,
   `_historyIndex` must satisfy `0 <= _historyIndex < _history.length`.

2. **Undo/redo are command-guarded**: `_isCommandExecuting` must be true while
   `_applyState()` mutates controllers so listeners do not create new history
   entries.

3. **Forward history truncates only on new commit**: Undo does not delete future
   entries. New edits after undo remove forward entries.

4. **History stores state, not selection**: `EditorState` stores text and style
   metadata only. Cursor/selection is intentionally not restored.

5. **Typing bulking survives**: Text edits commit by debounce/bulk logic rather
   than per keypress. Newline and explicit commands may commit immediately.

6. **Suite sectioning survives**: Suite sessions and layout interactions must
   commit meaningful sections, not a polluted entry for every button click.

7. **Persistence writes both index and JSON**: `_forceRecentUpdate()` and
   save/load flows must keep `historyIndex` and `historyJson` together.

8. **Gallery re-entry must not reset to head**: If saved `historyIndex` exists,
   the editor/provider must restore it instead of defaulting to the latest entry.

9. **Duplicate prevention remains active**: `_commitHistory()` must skip entries
   when text/settings match the current head.

---

## Forbidden Changes

- Do not create history entries for selection/cursor movement.
- Do not set `_historyIndex = _history.length - 1` when a valid saved index
  exists.
- Do not remove `_isCommandExecuting` guards from undo/redo/apply-state paths.
- Do not drop `historyJson` from recent metadata.
- Do not clear `[U]` or historical TODO/log records as part of documenting or
  testing history behavior.
- Do not move history UI logic into STT/teleprompter code.

---

## Known Fragilities

- **Async persistence race**: `_forceRecentUpdate()` is async. Fast navigation can
  race recent metadata writes.
- **Shared settings metadata**: Recent-script updates also carry style and source
  metadata. A naive history update can accidentally drop unrelated fields.
- **Suite disposal**: Closing/navigating with an open suite can lose a pending
  suite section if it is not committed before disposal.
- **Large history JSON**: Storing full editor states can grow quickly for large
  scripts.

---

## Shared-File Ownership Notes

History owns the history-related sections of `script_editor_screen.dart`,
`script_provider.dart`, and `settings_provider.dart`. Script Editor owns editor
orchestration; Settings owns persistence mechanics; History owns the semantics
of saved snapshots and indices.
