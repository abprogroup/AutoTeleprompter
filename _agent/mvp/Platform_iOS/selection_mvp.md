---
name: Selection MVP
type: component
platform: iOS
last_updated: 2026-04-27
---

# Selection MVP — iOS

Governs all multi-block text selection, overlay drag handles, cut/copy, and the interplay between native TextField selection and the in-app overlay selection system.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/editor/components/global_selection_overlay.dart` | Overlay handles, refine mode, handle drag, selectAll/clearSelection |
| `Platform_iOS/lib/features/script/widgets/editor/components/ghost_selection_controls.dart` | Hides native iOS circle handles |
| `Platform_iOS/lib/features/script/widgets/editor/markup_controller.dart` | `externalSelection`, `isGlobalSelected`, `refresh()` fields |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | `_selectAllBlocks`, `_clearGlobalSelection`, `_deleteGlobalSelection`, `_resyncGlobalSelection`, `_onCopyClean`, `_onCutClean`, `_EditorBlock` context menu, `onTap` handler, `_isGlobalSelection` flag, `_isCommandExecuting` flag |

---

## External API (what outside code may call)

| Method / Field | Where used |
|----------------|-----------|
| `_selectAllBlocks()` | Context menu "Select All", `SelectAllTextIntent` action, keyboard Cmd+A |
| `_clearGlobalSelection()` | `onTap` on any block, `_onCutClean`, style commands after apply |
| `_deleteGlobalSelection()` | Controller listener when focused block cleared via backspace |
| `_resyncGlobalSelection()` | After every global style operation that changes text length |
| `_onCopyClean()` | Context menu "Copy", `CopySelectionTextIntent`, keyboard Cmd+C |
| `_onCutClean()` | Context menu "Cut", keyboard Cmd+X |
| `_isGlobalSelection` | Read by style commands (`_applyStyleCmd`, `_applyInlineCmd`, `onAlign`, `onDirection`) to decide whether to apply globally |
| `_overlayKey.currentState?.hasSelection` | Read by `_onSelectionChanged`, `_styleTargets`, `_applyStyleCmd` |
| `_overlayKey.currentState?.selectAll()` | Called by `_selectAllBlocks` and `_resyncGlobalSelection` postFrameCallback |
| `_overlayKey.currentState?.clearSelection()` | Called by `_clearGlobalSelection`, `_deleteGlobalSelection` |
| `_styleTargets()` | Returns list of controllers to apply style to; reads `_isGlobalSelection` and `hasOverlay` |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Formatting toolbar bold/italic/underline | `script_editor_screen.dart _applyStyleCmd` | `_isGlobalSelection`, `_resyncGlobalSelection`, `_styleTargets()` |
| Font size / color / align commands | `script_editor_screen.dart _applyInlineCmd / onAlign / onDirection` | Same as above |
| Undo / Redo | `script_editor_screen.dart _undo / _redo` | `_isCommandExecuting = true/false` (borrows the flag) |
| Editor build → ListView.builder | `script_editor_screen.dart build()` | `_EditorBlock(onSelectAll, onCopy, onCut, onTap, isGlobalSelected)` |

---

## Invariants

1. **Global state coherence**: When `_isGlobalSelection=true`, every controller has `isGlobalSelected=true` AND `externalSelection` covering its full text. When `_isGlobalSelection=false`, all `externalSelection=null` and `isGlobalSelected=false`.

2. **`_isCommandExecuting` guard**: While `true`, `_onSelectionChanged()` must not clear global selection and the escalation check must not fire `_selectAllBlocks()`. Set to `true` before any programmatic selection mutation, `false` after.

3. **Refresh after mutation**: After any change to `externalSelection` or `isGlobalSelected`, `c.refresh()` must be called. These fields live outside `TextEditingValue` so Flutter won't repaint otherwise.

4. **`selectionColor` always transparent**: `_EditorBlock` on iOS hardcodes `selectionColor: Colors.transparent`. The native selection highlight is never visible — all amber rendering is done exclusively by `MarkupController.buildTextSpan` via `externalSelection`. Do NOT make this conditional.

5. **`_enterRefineMode` must NOT collapse native selection**: Collapsing `controller.selection` inside `_enterRefineMode()` corrupts `RenderEditable`'s internal state and breaks `getPositionForPoint()` on the second+ visual line of wrapped text (v4.0.7 fix). Because `selectionColor` is always transparent, there is no amber flash to suppress — leave native selection untouched.

6. **`_selectAllBlocks` sets full-block native selection**: The active controller receives `TextSelection(baseOffset: 0, extentOffset: text.length)` so the iOS soft keyboard can delete the selection. `GhostSelectionControls` hides the native circle handles — do NOT remove it.

7. **Overlay `_isSelecting`**: Must be `true` whenever any `externalSelection` is set. `clearSelection()` must reset all controller fields as well as its own state.

---

## Forbidden Changes

- Do not make `selectionColor` conditional on `isGlobalSelected` — it must always be `Colors.transparent` on iOS. Adding a condition breaks the multi-line drag and creates spurious amber flashes.
- Do not collapse `controller.selection` in `_enterRefineMode()` — this is the v4.0.7 multi-line drag fix. The transparent `selectionColor` already ensures the native selection is invisible.
- Do not remove `selectionControls: GhostSelectionControls()` from `_EditorBlock` — native iOS circle handles will reappear and interfere with the overlay handle system.
- Do not call `_clearGlobalSelection()` inside `_onSelectionChanged()` for a collapsed cursor — that cursor was placed by `_selectAllBlocks()` to enable keyboard delete and must not trigger a clear.
- Do not call `c.refresh()` after setting `_isCommandExecuting = true` without immediately setting it back to `false` — the guard only suppresses listener reactions during a brief synchronous window.

---

## Known Fragilities

- **`c.refresh()` triggers listener**: Any `c.refresh()` call fires the `addListener` callback. If called when `_isCommandExecuting=false` and `_isGlobalSelection=true`, `_onSelectionChanged()` runs immediately. Always verify the active controller's selection state is full-block (not partial) before calling refresh in that window.
- **Overlay `_enterRefineMode` timing**: It fires during `onPanStart` of a handle drag. The `onSelectionChanged` callback it triggers causes `_isGlobalSelection` to update in the parent widget. Any code that runs between `_enterRefineMode` and the parent's `setState` sees an inconsistent state.
- **`_resyncGlobalSelection` + postFrameCallback**: The `overlay.selectAll()` in the postFrameCallback fires after layout, which fires `c.refresh()` again. Verify escalation is blocked (`_isGlobalSelection=true` and `_overlayKey.currentState?.hasSelection=true`) before adding any code near that path.
