---
name: Selection MVP
type: component
platform: Windows
last_updated: 2026-04-29
---

# Selection MVP - Windows

Governs multi-block text selection, custom amber highlighting, overlay drag
handles, hidden native handles, select-all behavior, copy/cut purity, and
selection-sensitive boundaries for style commands.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/widgets/editor/components/global_selection_overlay.dart` | Overlay handles, global selection state, select-all/refine mode, drag hit testing, handle position refresh |
| `Platform_Windows/lib/features/script/widgets/editor/components/ghost_selection_controls.dart` | Hides native Material selection handles while preserving logical selection |
| `Platform_Windows/lib/features/script/widgets/editor/markup_controller.dart` | `externalSelection`, `isGlobalSelected`, `refresh()`, hidden-tag render selection logic |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | `_selectAllBlocks`, `_clearGlobalSelection`, `_deleteGlobalSelection`, `_resyncGlobalSelection`, `_onCopyClean`, `_onCutClean`, `_styleTargets`, selection guards |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.debug_bookmarks_search.dart` | Extracted select-all, clean copy, search selection, and global-selection resync methods after V5 file split |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.styling_commands.dart` | Extracted selection-sensitive style target and resync call paths after V5 file split |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.editor_block.dart` | Extracted TextField/context menu wiring for select-all/copy/search actions |
| `Platform_Windows/lib/core/services/rich_clipboard.dart` | Rich/plain clipboard helper used by clean copy paths |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `GlobalSelectionOverlayState.selectAll()` | `_selectAllBlocks()` and `_resyncGlobalSelection()` |
| `clearSelection()` | `_clearGlobalSelection()` and delete/cut paths |
| `hasSelection` | `_onSelectionChanged()`, `_styleTargets()`, style command paths |
| `refreshPositions()` | Alignment/direction changes after layout shifts |
| `syncOffsetsFromExternalSelection(...)` | Style commands after raw text length changes |
| `MarkupController.externalSelection` | Overlay, style commands, renderer |
| `MarkupController.isGlobalSelected` | Select All state and renderer |
| `MarkupController.refresh()` | Any mutation of external selection or global flag |
| `_onCopyClean()` / `_onCutClean()` | Keyboard/context menu copy/cut |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Editor context menu/keyboard | `script_editor_screen.dart` | Select All, Copy, Cut, clear selection |
| Style commands | `script_editor_screen.dart` | `_styleTargets()`, `_resyncGlobalSelection()`, overlay sync |
| Layout commands | `script_editor_screen.dart` | `refreshPositions()` and visual offset preservation |
| Markup renderer | `markup_controller.dart` | Paints selection via `externalSelection` or `isGlobalSelected` |
| Clipboard | `rich_clipboard.dart` and editor copy path | Receives tag-free plain/HTML output |

---

## Invariants

1. **Global selection coherence**: When the whole script is selected, every block
   has `isGlobalSelected=true` or an authoritative `externalSelection` covering
   its visible range.

2. **Collapsed external selections suppress stale highlights**: Out-of-range
   blocks use a non-null collapsed `externalSelection` to prevent native
   selection bleed-through.

3. **Refresh after external field mutation**: `externalSelection` and
   `isGlobalSelected` are plain fields; `c.refresh()` must follow mutations.

4. **Native handles stay hidden**: `GhostSelectionControls` must remain wired for
   editor blocks when custom overlay handles are active.

5. **Do not collapse native selection in refine mode for Windows/iOS-derived
   overlay logic**: The current overlay relies on transparent/native-hidden
   behavior and RenderEditable hit testing.

6. **Handle coordinates use RenderEditable truth**: Caret positions come from
   the actual `RenderEditable`, with downstream affinity at wrap boundaries.

7. **Global selection style commands resync offsets**: After markup insertion or
   removal, overlay offsets must be updated from `externalSelection`.

---

## V5 File Split Notes

Selection behavior was mechanically moved into same-library Dart parts during
the Windows split. The owning files are now
`script_editor_screen.debug_bookmarks_search.dart`,
`script_editor_screen.styling_commands.dart`, and
`script_editor_screen.editor_block.dart`. Do not reintroduce native highlight
leaks or stale `externalSelection` behavior while editing these smaller files.

8. **Copy/cut are clean**: User clipboard output must not expose raw markup tags.

---

## Forbidden Changes

- Do not set out-of-range `externalSelection` to null during global selection
  refinement; use collapsed selection to suppress stale highlights.
- Do not remove `c.refresh()` after external selection/global flag mutations.
- Do not remove `GhostSelectionControls` without replacing native-handle
  suppression.
- Do not use TextPainter approximations for handle coordinates when
  `RenderEditable` is available.
- Do not let copy/cut emit raw `[color]`, `[bg]`, `[align]`, `[font]`, or `**`
  markup.
- Do not change `_styleTargets()` without checking Styling Engine and History
  MVPs.

---

## Known Fragilities

- **Raw vs visual offsets**: Markup tags take raw positions but render invisible.
  Selection math must know which coordinate system it uses.
- **Listener re-entry**: `c.refresh()` fires controller listeners and can trigger
  `_onSelectionChanged()`.
- **Handle timing**: Position recalculation must often be deferred until after
  layout via `addPostFrameCallback`.
- **Shared style paths**: Selection state drives style command targeting and
  history creation.

---

## Shared-File Ownership Notes

Selection owns selection state and target calculation in `script_editor_screen.dart`.
Styling Engine owns markup transforms that use those targets. History owns the
save entries created after selection-based commands.

---

## 2026-05-03 V5 Stabilization Addendum

- Selection handle geometry must be derived from constants, not magic offsets:
  the caret anchor is the rendered caret x plus vertical center, and the handle
  hit box is centered on that anchor.
- Raw handle endpoints and normalized selected ranges are separate concepts.
  Dragging one handle may update only that handle's raw endpoint; highlight,
  copy, cut, and style targeting may normalize the range afterward.
- Handle autoscroll is scoped to an active handle drag only. It must stop on
  pan end, pan cancel, deselect, clear selection, dispose, and scroll-boundary
  clamp.
- Native partial selections may seed the overlay only while command execution,
  handle drag, autoscroll, global selection, and existing overlay selection are
  all inactive.
- Empty editor blocks are valid selection and keyboard-navigation positions.
  Left/right arrows must visit consecutive empty rows one at a time.

## 2026-05-03 V5 Follow-Up: Endpoint Ownership Repair

- Overlay endpoints are stable ownership points, not document-order labels.
  Endpoint A and endpoint B may cross; only the normalized range used for
  highlight/copy/cut is reordered.
- A dragged handle may update only its active endpoint. Crossing into another
  block must not move the opposite endpoint or clear the original block from
  the normalized selection.
- Handle bars are drawn just outside the selected text boundary. The caret
  boundary remains the selection truth, while the hit box follows the visible
  bar so the bar does not cover selected letters.
- Arrow navigation has one owner: the global hardware-key route. The editor
  focus shell must not also process arrow keys, because duplicate handling can
  skip empty rows or stall at paragraph boundaries.
