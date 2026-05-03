---
name: History MVP
type: component
platform: iOS
last_updated: 2026-05-03
---

# History MVP — iOS

Governs the undo/redo stack, history persistence across sessions, and the typing-bulk / suite-sectioned auto-save logic.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | `_undo`, `_redo`, `_jumpToHistory`, `_saveHistory`, `_commitHistory`, `_onTypingBulk`, `_trackSuiteSection`, `_startSuiteAutoSave`, `_historyIndex`, `_history`, `_isDirty`, all three history timers |
| `Platform_iOS/lib/features/script/widgets/editor/suites/history_suite_mvp.dart` | History list UI, jump-to button |
| `Platform_iOS/lib/features/script/providers/script_provider.dart` | `historyIndex`, `historyJson` fields on `Script`; `updateHistoryIndex()` method |
| `Platform_iOS/lib/features/script/widgets/script_gallery_screen.dart` | Loads `historyIndex` + `historyJson` from saved metadata when re-opening a script |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `_undo()` | Undo button in `FormattingToolbarMVP` |
| `_redo()` | Redo button in `FormattingToolbarMVP` |
| `_jumpToHistory(int idx)` | History suite list item tap |
| `_saveHistory(description, debounce)` | Every style command, text change, alignment change |
| `canUndo` / `canRedo` | Toolbar button enable state |
| `history` / `historyIndex` | Passed to history suite for display |
| `scriptProvider.updateHistoryIndex(int)` | Called by `_undo` and `_redo` to keep in-memory provider in sync |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Bold / Italic / Underline | `_applyStyleCmd` | `_saveHistory(description: 'Bold/...')` |
| Font size / color / bg | `_applyInlineCmd` | `_saveHistory(description: ...)` |
| Align / Direction | `onAlign`, `onDirection` | `_commitHistory('Align:...')` |
| Clear Format | onClear handler | `_saveHistory(description: 'Clear Format')` |
| Cut | `_onCutClean` | `_saveHistory(description: 'Cut')` |
| Delete global selection | `_deleteGlobalSelection` | `_saveHistory(description: 'Delete Selection')` |
| Text typing | `_onBlockChanged` | `_saveHistory(description: 'Edit Text', debounce: true)` |
| Import file / load | `_runPendingFileLoad` | `_saveHistory(description: 'Import')` |
| Settings style change | `ref.listen(settingsProvider)` | `_saveHistory(description: 'Update Styling', debounce: true)` |
| Gallery re-open | `script_gallery_screen.dart` | `scriptNotifier.loadText(..., historyIndex: ..., historyJson: ...)` |

---

## Invariants

1. **Index always valid**: `_historyIndex` must always satisfy `0 ≤ _historyIndex < _history.length` when history is non-empty.

2. **Dual persistence after undo/redo**: Both `_forceRecentUpdate()` (SharedPreferences via settingsProvider) AND `scriptProvider.notifier.updateHistoryIndex(_historyIndex)` must be called. Missing either causes re-entry to restore the wrong position.

3. **Gallery must pass historyIndex**: `script_gallery_screen.dart` must pass `historyIndex: (decodedMeta?['historyIndex'] as num?)?.toInt()` to `loadText()`. Without it, the index defaults to -1 and the editor falls back to `_history.length - 1` — the root cause of the "undo lost on re-entry" bug fixed in v4.1.6.

4. **`_isCommandExecuting` during undo/redo**: Must be `true` while `_applyState` runs to prevent controller listeners from firing history saves mid-operation. Cleared after 150ms delay.

5. **No save during `_isCleaning`**: `_commitHistory` returns early if `_isCleaning=true`. This prevents the style-scan pass from creating spurious history entries.

6. **Typing bulk**: Text edits are debounced — commit after 10 chars OR 10 seconds, whichever comes first. `_typingCharCount` resets on each commit. Do not bypass this for performance fixes without preserving both triggers.

7. **Suite auto-save**: A 3-second auto-save fires while a formatting suite is open. Section changes within the same suite commit the previous section first. Closing the suite commits the full session.

8. **Duplicate prevention**: `_commitHistory` checks if the current text + settings match the head entry. If identical, it skips — do not remove this check.

---

## Forbidden Changes

- Do not call `_forceRecentUpdate()` in `_undo`/`_redo` without ALSO calling `scriptProvider.notifier.updateHistoryIndex()` — SharedPreferences and in-memory provider must stay in sync.
- Do not set `_historyIndex = _history.length - 1` in `didChangeDependencies` unless `script.historyIndex < 0` — this discards the saved undo position.
- Do not truncate `_history` during undo — only truncate forward entries after a new commit (`if (_historyIndex < _history.length - 1) _history.removeRange(...)`).
- Do not call `_saveHistory` while `_isCommandExecuting = true` — style commands set this flag to prevent listener-triggered saves from polluting the stack.
- Do not skip saving `historyJson` in `_forceRecentUpdate()` — without the full JSON, re-entry has no history to restore, only the current text.

---

## Known Fragilities

- **App-owned selection Cut history (2026-05-03)**: Selection Cut now depends
  on app-owned toolbar commands reaching `_onCutClean()`. If debug mode shows
  `Command: idle`, History did not receive a real Cut command and no history
  behavior can be trusted. App-owned Cut must commit a baseline before mutation
  and a Cut state after mutation so Undo is available immediately, before any
  deselection, focus loss, or background tap. Selection toolbar dismiss/clear
  actions must not create history entries; only destructive mutations and paste
  restorations own history commits.
- **Async race on exit**: `_forceRecentUpdate()` is async. If the user exits within ~200ms of an undo, SharedPreferences might not flush before the gallery re-reads. The in-memory `scriptProvider.updateHistoryIndex()` provides a synchronous fallback, but ONLY if the gallery doesn't call `scriptNotifier.loadText()` before the flush completes.
- **Gallery `loadText` overwrites in-memory**: Whenever the gallery opens a script, it calls `scriptNotifier.loadText()` which rebuilds the in-memory state from the metadata JSON. If that JSON has a stale `historyIndex`, the in-memory fix is lost. This is why the gallery MUST pass `historyIndex` explicitly (Invariant 3).
- **Suite not committed on back-navigation**: If a suite is left open and the user navigates away, the pending suite history is not committed. `dispose()` cancels the timer but does not flush. Accepted behaviour — the last suite action may be lost from the history stack.
