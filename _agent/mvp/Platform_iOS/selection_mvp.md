---
name: Selection MVP
type: component
platform: iOS
last_updated: 2026-04-29
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
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.selection_clipboard.dart` | Split owner for selection/cut/copy/paste helpers and multi-block clipboard snapshots |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.editor_block.dart` | Split owner for iOS context menu interception, custom Cut/Copy/Paste/Select All routing, and `GhostSelectionControls` usage |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.build.dart` | Split owner for block callback wiring and debug-mode clipboard diagnostics |

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

8. **Global selection snapshot protects paste recovery**: `_selectAllBlocks()`
   arms a short-lived raw-markup global selection snapshot for iOS context-menu
   timing. Cut/Copy write `_blockClipboard`, but Paste must prefer the largest
   recent protected snapshot if a later one-block native selection event
   downgraded or bypassed `_blockClipboard`.

9. **Multi-block paste restores block structure**: Global Cut/Copy stores one
   raw-markup string per paragraph block. `_pasteFromGlobalClipboard()` must add
   missing controllers before restoration and assign `TextEditingValue(text:
   rawMarkup)` so styling tags remain intact.

10. **Paste affordance may come from snapshot**: The editor context menu must
    expose the custom in-app Paste action when either `_blockClipboard` exists or
    a recent protected global selection snapshot exists.

11. **Native destructive cut must repair its slot**: If iOS clears one focused
    `TextField` while global selection is still active, the controller listener
    must repair the protected snapshot at the same block index using the
    listener's previous raw markup before `_deleteGlobalSelection()` reduces the
    controller list, then promote the repaired/kept snapshot into
    `_blockClipboard`. This prevents the `N -> N-1` paste symptom where the
    first selected block becomes an empty restored slot or Paste sees only the
    system clipboard path.

12. **Clipboard diagnostics must show shape**: Debug-mode clipboard diagnostics
    must include the block count and `index:length` shape for armed, stored, and
    restored snapshots. Do not remove this while the iOS context-menu path is
    under verification.

---

## Forbidden Changes

- Do not make `selectionColor` conditional on `isGlobalSelected` — it must always be `Colors.transparent` on iOS. Adding a condition breaks the multi-line drag and creates spurious amber flashes.
- Do not collapse `controller.selection` in `_enterRefineMode()` — this is the v4.0.7 multi-line drag fix. The transparent `selectionColor` already ensures the native selection is invisible.
- Do not remove `selectionControls: GhostSelectionControls()` from `_EditorBlock` — native iOS circle handles will reappear and interfere with the overlay handle system.
- Do not call `_clearGlobalSelection()` inside `_onSelectionChanged()` for a collapsed cursor — that cursor was placed by `_selectAllBlocks()` to enable keyboard delete and must not trigger a clear.
- Do not call `c.refresh()` after setting `_isCommandExecuting = true` without immediately setting it back to `false` — the guard only suppresses listener reactions during a brief synchronous window.

---

## Known Fragilities

Additional clipboard prohibitions:

- Do not write `_blockClipboard` inside `_selectAllBlocks()`. Select All arms
  selection state only; Cut/Copy owns clipboard persistence.
- Do not collapse multi-block clipboard data into one plain-text string. Plain
  system clipboard text is allowed as a companion, but in-app paste must keep the
  raw markup block list.
- Do not treat a same-length snapshot as safe if the leading slot changed from
  non-empty to empty. Native iOS cut can clear the touched block before Flutter's
  global command finishes; preserve that slot from the previous listener text.

- **`c.refresh()` triggers listener**: Any `c.refresh()` call fires the `addListener` callback. If called when `_isCommandExecuting=false` and `_isGlobalSelection=true`, `_onSelectionChanged()` runs immediately. Always verify the active controller's selection state is full-block (not partial) before calling refresh in that window.
- **Overlay `_enterRefineMode` timing**: It fires during `onPanStart` of a handle drag. The `onSelectionChanged` callback it triggers causes `_isGlobalSelection` to update in the parent widget. Any code that runs between `_enterRefineMode` and the parent's `setState` sees an inconsistent state.
- **`_resyncGlobalSelection` + postFrameCallback**: The `overlay.selectAll()` in the postFrameCallback fires after layout, which fires `c.refresh()` again. Verify escalation is blocked (`_isGlobalSelection=true` and `_overlayKey.currentState?.hasSelection=true`) before adding any code near that path.
- **iOS context-menu timing**: Native iOS may reset the active `TextField`
  selection or fire a tap-through before the menu action reaches Flutter. The
  short-lived global selection snapshot exists only to let Cut/Copy recover the
  intended multi-block selection; it must not become a permanent hidden
  selection state. Paste may also use it as a fallback when native Cut bypassed
  the in-app Cut command but Select All was captured correctly.
