---
name: Block Selection Recognition MVP
type: component
platform: iOS
last_updated: 2026-05-02
---

# Block Selection Recognition MVP - iOS

Defines the iOS-only recognition layer that lets the editor understand partial selections across paragraph blocks without replacing the native one-block selection system, Select All recovery path, or existing overlay handle infrastructure.

---

## Scope

This MVP is the implementation contract for safer partial multi-block selection. It exists because iOS native selection is scoped to one `TextField`, while the script editor is intentionally split into one `MarkupController` / `TextField` per paragraph block.

The goal is not to create a second toolbar, a new app-wide selection system, or a passive native-selection adoption path. The goal is to let the app recognize the user's intended block range precisely enough that Cut/Copy can build the correct raw-markup clipboard slices when the selected range crosses block boundaries.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.selection_clipboard.dart` | Owner for normalized block-range to clipboard-slice conversion, command routing, and cut/copy range execution |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.editor_block.dart` | Owner for native/adaptive toolbar command interception and single-block selection source detection |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.build.dart` | Owner for visible block rectangle refresh hooks, debug diagnostics, and scroll/layout notification integration |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.load_blocks.dart` | Owner for controller listener boundaries and selection-change guard interactions |
| `Platform_iOS/lib/features/script/widgets/editor/components/global_selection_overlay.dart` | Existing owner of app handles and read-only raw endpoint reporting; not a replacement for native one-block selection |
| `Platform_iOS/lib/features/script/widgets/editor/markup_controller.dart` | Raw/visible text mapping source for styled selections and invisible markup tags |
| `_agent/mvp/Platform_iOS/selection_mvp.md` | Parent selection-system contract; this MVP must remain compatible with all invariants there |

---

## External API

| Method / Field | Intended contract |
|----------------|-------------------|
| `_selectAllBlocks()` | Full-script selection remains owned by Selection MVP; block recognition must not override it |
| `_onCopyClean()` / `_onCutClean()` | Future command router should check a normalized block range before falling back to native one-block selection |
| `_overlaySelectedMarkupBlocks()` | Existing overlay-slice builder; may be reused if the recognized range is stored as `externalSelection` slices |
| `_blockClipboard` | Must receive one raw-markup string per selected block/slice, preserving styling tags and block order |
| `MarkupController.externalSelection` | May represent the app-owned visual range after recognition; must never be stale after user navigation |
| `GlobalSelectionOverlayState.hasSelection` | Indicates app-owned selection is active; command routing may use this, but passive native events must not create it |
| `MarkupController.rawToVisualOffset` / `visualToRawOffset` | Required for mapping visible selection positions back to raw markup offsets when tags are hidden |

---

## All Callers

| Caller | Expected use |
|--------|--------------|
| Native/adaptive iOS context menu | Provides one-block selection intent and command presses; cannot itself describe multiple blocks |
| Editor block taps/background taps | Must dismiss stale recognized ranges just like stale global/overlay selections |
| Scroll notifications | Must refresh visible block rectangles and handle positions; must not run timer autoscroll |
| Cut/Copy/Paste commands | Must consume normalized block slices when a recognized cross-block range exists |
| Styling commands | Must respect recognized `externalSelection` ranges only when they are active and current |
| History system | Must receive immediate history entries for Cut/Paste, not delayed entries after deselection |

---

## Invariants

1. Native one-block selection remains native. Do not break double-tap word selection, native handles, or native toolbar behavior for a range that stays inside one block.

2. Select All remains separate. Full-block native selection and `_selectAllBlocks()` continue to own full-script selection and protected multi-block snapshot recovery.

3. No product-facing `Extend` button is required. The recognition layer should make the app understand blocks better; it should not expose vague selection-mode language to the user.

4. No second toolbar. The rejected app command bar must not return. Toolbar command ownership must remain native/adaptive for visible commands, with app command handlers behind those buttons when needed.

5. No passive listener adoption. `_onSelectionChanged()` and controller listeners must not automatically convert every native selection into app overlay selection.

6. Recognition starts from a confirmed user selection source: native/adaptive menu build, command press, or an explicit user drag event owned by existing overlay handles. It must not trigger from incidental focus changes.

7. A recognized cross-block range is normalized as ordered endpoints: start block/start raw offset, end block/end raw offset, with RTL/LTR respected only for visual hit-testing, not for storage order.

8. Clipboard slices are built from raw markup, not visible text. A multi-block selection becomes start slice, zero or more full middle-block slices, and end slice.

9. Empty selected blocks are preserved if the user selected them intentionally. Do not collapse N selected blocks into N-1 clipboard entries.

10. Invisible markup tags must never be selected as visible characters. Any visible offset used by recognition must map back through `MarkupController` raw/visible helpers.

11. Block rectangles are layout data, not selection state. They may help hit-test visible blocks, but stale rectangles must not create a hidden selection after scroll/layout changes.

12. User navigation clears recognized transient ranges while preserving the real paste clipboard after Cut/Copy.

13. Cut commits history immediately after mutation. It must not wait until deselection or focus loss.

14. The recognized range must be inspectable in debug mode with block count and `index:length` shape, matching existing clipboard diagnostics.

15. The feature must be iOS-only unless explicitly ported. Do not infer shared code or touch Windows/Android/macOS implementations.

---

## Forbidden Changes

- Do not replace the existing iOS selection system wholesale.
- Do not add a floating app Cut/Copy/Paste toolbar.
- Do not make native handles visible during global/overlay selection modes where `GhostSelectionControls` is required.
- Do not call block-range recognition from passive focus/selection listener noise.
- Do not collapse cross-block clipboard content into one plain-text string.
- Do not strip markup while building `_blockClipboard`.
- Do not let a one-block native Cut/Copy command overwrite a larger recognized range unless the user has actually changed the selection.
- Do not let stale block rectangles survive script reload, block split/merge, import, paste, undo, redo, or user navigation.
- Do not use timer-based edge autoscroll as part of this MVP.
- Do not update non-iOS platform folders while implementing this MVP.

---

## Known Fragilities

- iOS exposes one native selection per `UITextView`, so no amount of native toolbar interception will make UIKit report a true cross-block range by itself.
- `RenderEditable.getPositionForPoint(...)` expects global coordinates; double-converting global/local coordinates has broken handle positions before.
- Hidden markup tags make raw offsets larger than visible offsets. Any direct substring operation from visible positions can cut tags or miss text.
- RTL Hebrew blocks and LTR English blocks may have opposite visual marker sides, but raw block order must stay script order for clipboard restoration.
- Lazy editor list rendering means offscreen blocks may not have valid render boxes. Recognition should use visible block maps only for visible hit-testing, not for restoring hidden state.
- Existing Select All snapshot repair is intentionally separate. Do not mix this MVP with the native-empty snapshot repair path unless a test proves the interaction.
- Native iOS may dismiss or rebuild the toolbar after a command. The command router must be resilient to menu timing and must not depend on a toolbar staying open forever.

---

## Related Feature Integration Audit

This audit was added before runtime implementation so the selection fix is checked against every nearby editor feature, not only against the visible handle behavior.

| Related system | Current owner | Required compatibility rule |
|----------------|---------------|-----------------------------|
| Native one-block selection | `script_editor_screen.editor_block.dart` | Double-tap, drag within one block, native Cut, native Copy, and native Paste must keep working without requiring global overlay state. |
| Full Select All | `script_editor_screen.selection_clipboard.dart` and `GlobalSelectionOverlay.selectAll()` | `_selectAllBlocks()` keeps its protected raw-markup snapshot and native-empty repair path. Block recognition must not downgrade full-script snapshots. |
| Overlay handles | `editor/components/global_selection_overlay.dart` | Existing handles remain the only app-owned cross-block handle system. Recognition may feed endpoints into these handles, but must not create parallel handles. |
| Clipboard storage | `_blockClipboard`, `_plainBlockClipboardText`, `RichClipboard` | Multi-block copy/cut stores raw markup slices in script order. Plain clipboard is only a companion for system paste fallback, never the source of styled restore. |
| Native plain paste interception | `_consumeNativePlainBlockPasteIfNeeded()` | If iOS routes toolbar Paste through plain text, the listener must still restore from `_blockClipboard` and preserve block structure/styles. |
| History and undo | `_commitHistory()` / `_saveHistory()` | Cut and Paste commit immediately after mutation. No change may wait for deselection/focus loss to enter history. |
| Styling commands | `_styleTargets()`, `wrapSelection()`, `applyInlineProperty()` | A recognized range must be represented as current `externalSelection` slices before styling can act on it. Hidden stale ranges must not receive style commands. |
| Markup rendering | `MarkupController` | Raw offsets must be snapped outside invisible tags. Visible hit-testing must map through `rawToVisualOffset` / `visualToRawOffset` when the source coordinate is visible text. |
| Search | `script_editor_screen.search.dart` | Search-created `externalSelection` remains a local editor selection. New block recognition must clear search selections on real user navigation and must not treat old search highlights as clipboard ranges. |
| Bookmarks | `script_editor_screen.bookmarks.dart` | Bookmark jumps clear transient selections and must not be interpreted as a new selected range. Selection changes must not move bookmark coordinates. |
| Import, save, export | `script_editor_screen.file_present.dart` and file services | Recognition is editor-runtime state only. It must not trim/collapse loaded file text, leak internal tags, or alter save/export serialization. |
| Block load/split/merge | `script_editor_screen.load_blocks.dart` | Any recognized range becomes invalid after block insert/remove/split/merge, undo/redo, import, paste, or clear. Do not keep stale block indexes alive. |
| Scroll/layout | `script_editor_screen.build.dart` and overlay refresh | Render boxes may be used for visible hit-testing and handle location only. They must refresh after scroll and must not become persistent selection truth. |
| RTL/Hebrew | `MarkupController`, block text direction, overlay hit testing | Storage order is always script block order. Visual side/drag behavior may be RTL-aware, but clipboard slices remain ordered start block through end block. |

## Implementation Gates

1. Add a small internal range model first, for example `blockIndex + rawOffset` endpoints and a normalized range helper. Do not connect it to Cut/Copy until debug output proves its shape.

2. Populate the range only from confirmed user sources: current native menu selection, existing overlay handle movement, or explicit Select All. Do not populate it from passive `_onSelectionChanged()` noise.

3. Add a pure helper that converts a normalized range into raw-markup block slices. It must be tested mentally against one-block, two-block, three-block, empty middle block, English/Hebrew, and styled-tag cases before command routing uses it.

4. Only after the helper is proven, let `_onCopyClean()` and `_onCutClean()` prefer the recognized range when it is current. They must then fall back in this order: full Select All snapshot, overlay selection, ordinary one-block native selection.

5. Any mutation path must clear only transient selection state, not the real paste clipboard. `_blockClipboard` remains valid after Cut/Copy until timeout or replacement.

6. If the user taps elsewhere, jumps bookmark/search, imports, splits, merges, undoes, redoes, or reloads the script, clear the recognized transient range immediately.

7. Keep implementation iOS-only. No Windows, Android, or macOS runtime files may change for this MVP.

---

## Finished-Product Runtime Plan

This is the required implementation order when runtime work begins. The goal is that the user receives one testable iOS build where the related pieces work together, not a half-state that fixes handles but breaks clipboard, history, or native selection.

### Phase 0 - Preflight and Backup

| Step | Action | Files |
|------|--------|-------|
| 0.1 | Read `AI_PROTOCOL.md`, `selection_mvp.md`, this MVP, `history_mvp.md`, `styling_engine_mvp.md`, `script_editor_mvp.md`, and `bookmarks_mvp.md`. | Documentation only |
| 0.2 | Create one surgical backup folder containing every iOS runtime file that will be touched. | All files listed below |
| 0.3 | Confirm the working tree has no unrelated staged files. Existing unrelated dirty release artifacts must stay unstaged. | Git state |

### Phase 1 - Internal Range Model Only

| Step | Runtime change | Required behavior |
|------|----------------|-------------------|
| 1.1 | Add private range structs/classes in `script_editor_screen.selection_clipboard.dart`, for example `_BlockSelectionPoint` and `_BlockSelectionRange`. | They store `blockIndex` and raw offset only. No UI behavior changes yet. |
| 1.2 | Add `_normalizeBlockRange(start, end)` helper. | It orders endpoints by script order, clamps offsets to controller lengths, rejects invalid controllers, and returns null for stale block indexes. |
| 1.3 | Add `_clearRecognizedBlockRange(reason)` and debug string support. | Clears transient range only; never clears `_blockClipboard`. |
| 1.4 | Add `_recognizedBlockRangeDebugShape()` using `index:start-end` and slice lengths. | Debug output must make it obvious whether the range is one-block, two-block, or N-block. |

Forbidden in Phase 1: no Cut/Copy/Paste changes, no toolbar changes, no overlay visual changes, no listener adoption.

### Phase 2 - Pure Slice Builder

| Step | Runtime change | Required behavior |
|------|----------------|-------------------|
| 2.1 | Add `_rawMarkupSlicesForRange(_BlockSelectionRange range)`. | One-block range returns one raw substring. Multi-block range returns start slice, full middle blocks, end slice. |
| 2.2 | Preserve intentionally selected empty blocks. | If an entire empty middle block is selected, the returned list must include `''` for that block so N blocks do not become N-1. |
| 2.3 | Keep styling tags intact. | Slices must come from raw `controller.text`; no `StylingService.stripTags()` here. |
| 2.4 | Add a visible-to-raw mapping helper only if input source is visible text. | Use `MarkupController.rawToVisualOffset` / `visualToRawOffset`; never substring visible text for clipboard. |

Forbidden in Phase 2: no mutation of controllers, no history commit, no system clipboard write.

### Phase 3 - Feed Range From Existing Overlay Handles

| Step | Runtime change | Required behavior |
|------|----------------|-------------------|
| 3.1 | Add a read-only endpoint API to `GlobalSelectionOverlayState`, for example `currentBlockRange`. | It returns start/end block and raw offsets after normalization, without exposing mutable overlay internals. |
| 3.2 | In `onSelectionChanged` wiring in `script_editor_screen.build.dart`, update the recognized range from overlay endpoints only when overlay has a real selection. | The existing overlay remains the visual selection system. Recognition only records its precise block range for clipboard/history. |
| 3.3 | Do not use passive native `_onSelectionChanged()` to create cross-block recognition. | Passive native events can update cursor styling, but must not create hidden cross-block state. |
| 3.4 | Keep `externalSelection` as the visual truth for highlighted text. | Recognized range is command metadata; if visual selection changes, recognized range must refresh or clear. |

This phase is the safest way to solve the current user-facing bug: handles visually select across blocks, and Cut/Copy must consume exactly that visible overlay range.

### Phase 4 - Command Routing

| Step | Runtime change | Required behavior |
|------|----------------|-------------------|
| 4.1 | Add `_recognizedBlocksForCommand(reason)` before overlay/global fallback. | It returns raw slices only if the recognized range is current and matches active overlay selection. |
| 4.2 | Update `_onCopyClean()` order: full Select All snapshot, recognized overlay range, existing overlay slices, one-block native selection. | Select All remains protected; recognized partial range fixes cross-block handles; native one-block still works. |
| 4.3 | Update `_onCutClean()` with same order. | After cutting recognized slices, mutate exactly the selected raw ranges across involved controllers. |
| 4.4 | For multi-block cut mutation, replace start block with prefix before start, middle blocks with empty strings or remove only when existing architecture already removes them, and end block with suffix after end. | Preserve paragraph/block structure unless the existing global delete path explicitly owns reduction. Do not silently merge unrelated blocks. |
| 4.5 | Call `_storeBlockClipboard(..., preferProtectedSnapshot: false)` for recognized partial ranges. | A full Select All protected snapshot must not overwrite a smaller intentional handle-refined selection. |
| 4.6 | Write `RichClipboard` plain/html companion exactly like current Copy path. | User can paste externally as visible text/html while in-app paste restores raw styles. |
| 4.7 | Commit history immediately after Cut and Paste. | Undo must work without requiring deselection first. |

Forbidden in Phase 4: do not call the native active `TextField` cut/copy command for cross-block overlay selection.

### Phase 5 - Native Menu Cooperation Without Product-Facing Extend

| Step | Runtime change | Required behavior |
|------|----------------|-------------------|
| 5.1 | Keep the native/adaptive toolbar as the visible command surface. | No app command bar, no second floating Cut/Copy/Paste toolbar. |
| 5.2 | Partial native one-block menu may still promote its confirmed native range into overlay handles behind the menu. | This is allowed only from `contextMenuBuilder`, not passive listeners. |
| 5.3 | Select All from native toolbar must reopen/rebuild toolbar into global command state. | User must immediately see Cut/Copy/Paste after Select All. |
| 5.4 | If native toolbar shows one-block actions while overlay has crossed blocks, app handlers must override Cut/Copy and consume recognized range. | This prevents the "only the originally touched block was cut" regression. |

### Phase 6 - Clearing, Invalidation, and Related Features

| Event | Required handling |
|-------|-------------------|
| Tap another block or editor background | Clear visual selection and recognized transient range; keep `_blockClipboard`. |
| Search jump | Clear recognized range before applying search selection. Search selection is not a clipboard range until user explicitly copies/cuts it. |
| Bookmark jump | Clear recognized range. Do not move bookmark anchors. |
| Import/reload/clear script | Clear recognized range and snapshots tied to old controllers. |
| Split paragraph / remove block | Clear recognized range because block indexes changed. |
| Undo/redo | Clear recognized range after state apply; existing history state is the source of truth. |
| Style command | Allowed only against current `externalSelection` slices. After style changes raw lengths, ask overlay to sync offsets from external selection. |
| Scroll | Refresh overlay positions; do not create or modify selected range from scroll alone. |

### Phase 7 - Debug Instrumentation for User Testing

| Debug line | Required information |
|------------|----------------------|
| Range armed | `range: blockA:offset-blockB:offset` plus slice shape |
| Copy recognized | Number of slices and `index:length` shape |
| Cut recognized | Number of slices, affected block range, and history commit name |
| Paste restored | Number of restored blocks/slices and whether rich in-app clipboard or plain fallback was used |
| Range cleared | Reason, e.g. `block-tap`, `search`, `bookmark`, `undo`, `import` |

Diagnostics must be visible in existing debug surfaces only. Do not add a permanent user-facing diagnostics panel.

---

## Final User Test Route

The runtime implementation is not considered ready until all rows below are tested on the iOS workflow artifact.

| Test | User action | Expected result |
|------|-------------|-----------------|
| Native one-block word cut | Double-tap a word inside one English block, Cut, Paste | Only that word/slice is restored with style intact. |
| Native one-block Hebrew cut | Double-tap/select Hebrew inside one RTL block, Cut, Paste | Hebrew selection stays in the same block, correct direction, style intact. |
| Select All two styled blocks | Red English block + white Hebrew block, Select All, Cut, Paste | Both blocks restore, no N-1 loss, no style stripping, no newline loss. |
| Select All three blocks | Three blocks, Select All, Cut, Paste | All three restore; first block is not missing. |
| Overlay partial two-block copy | Select from middle of block 0 through middle of block 1 with handles, Copy, Paste elsewhere | Restores start slice + end slice only, in order, with raw styling preserved. |
| Overlay partial three-block cut | Select middle of block 0 through middle of block 2, Cut | Cuts selected text across all involved blocks; unselected prefixes/suffixes remain. |
| Cross-block handle + native toolbar | Start from native one-block selection, drag overlay handles across blocks, press native toolbar Cut/Copy | Command applies to the visible cross-block range, not just the originally touched block. |
| History after Cut | Cross-block Cut, immediately Undo | Undo restores text immediately without needing deselection first. |
| Search interaction | Make selection, run search jump | Old selection clears; search highlight appears; clipboard from previous Copy remains pasteable if it was real. |
| Bookmark interaction | Make selection, jump bookmark | Old selection clears; bookmark location does not change; no hidden range remains. |
| Scroll handles | Select text, scroll so endpoint leaves viewport | Offscreen handle hides instead of clamping to edge; selection does not mutate from scroll alone. |
| Import preservation | Load styled multi-block file after selection work | Existing styles/newlines remain unaffected by the selection feature. |

---

## Exact Runtime Patch Contract

When runtime implementation begins, the patch must follow this exact private API shape unless the code proves a strictly safer equivalent. Any deviation must be documented in this file before code is committed.

### Runtime Implementation Status

Implemented on 2026-05-02 for iOS runtime testing.

| Contract area | Runtime status |
|---------------|----------------|
| Private transient range state | `_recognizedBlockRange` and `_recognizedBlockRangeDebug` added to `script_editor_screen.dart`. |
| Private range model | `_BlockSelectionPoint` and `_BlockSelectionRange` added in `script_editor_screen.selection_clipboard.dart`. |
| Raw slice conversion | `_rawMarkupSlicesForRange(...)` builds script-order raw-markup slices and preserves selected empty blocks. |
| Overlay endpoint source | `GlobalSelectionOverlayState.currentRawRange` exposes read-only raw endpoints. |
| Parent range sync | `script_editor_screen.build.dart` records recognized range only from refined overlay selections. |
| Cut/Copy routing | `_onCutClean()` and `_onCopyClean()` prefer full Select All first, then recognized partial range, then overlay fallback, then native one-block selection. |
| Partial cut mutation | `_deleteRecognizedRange(...)` mutates only selected raw ranges and preserves block count for safer history/bookmark stability. |
| Invalidation | Tap/navigation, clear, delete, load, remove, split, undo, redo, search, bookmark, import, and clear-script paths clear only transient recognized range. |
| Debug diagnostics | Existing editor sentry shows `Range: ...` alongside clipboard shape. |

Device QA is still required before marking this MVP user-verified.

### New Private State

Add only these transient fields to `_ScriptEditorScreenState` in `script_editor_screen.dart`:

| Field | Purpose |
|-------|---------|
| `_BlockSelectionRange? _recognizedBlockRange` | Current app-recognized partial block range, valid only while visual overlay/native selection is current. |
| `String _recognizedBlockRangeDebug` | Debug description for range source, endpoints, and slice shape. |

Do not persist this state. Do not save it to recent scripts. Do not store it in bookmarks, history, settings, or provider state.

### New Private Types

Add the following private immutable helpers in `script_editor_screen.selection_clipboard.dart`:

| Type | Required fields |
|------|-----------------|
| `_BlockSelectionPoint` | `int blockIndex`, `int rawOffset` |
| `_BlockSelectionRange` | `_BlockSelectionPoint start`, `_BlockSelectionPoint end`, `String source` |

These are not public API. They must not be imported by other files or platforms.

### New Private Helpers

Add these helpers in `script_editor_screen.selection_clipboard.dart`:

| Helper | Contract |
|--------|----------|
| `_normalizeBlockRange(_BlockSelectionPoint a, _BlockSelectionPoint b, String source)` | Returns ordered/clamped range or null. Script order wins over visual direction. |
| `_rawMarkupSlicesForRange(_BlockSelectionRange range)` | Returns raw-markup slices in script order. Preserves selected empty blocks. Never strips tags. |
| `_setRecognizedBlockRange(_BlockSelectionRange? range, String reason)` | Stores transient range and debug text. Does not touch `_blockClipboard`. |
| `_clearRecognizedBlockRange(String reason)` | Clears transient range only. Does not touch `_blockClipboard`, `_globalSelectionSnapshot`, or native clipboard. |
| `_recognizedBlocksForCommand(String reason)` | Returns raw slices only when range is valid and still matches current overlay/native visual state. |
| `_deleteRecognizedRange(_BlockSelectionRange range)` | Mutates only the selected raw ranges, then clears selection and commits history. |

### Command Precedence

`_onCopyClean()` and `_onCutClean()` must resolve commands in this exact order:

1. Full global Select All / protected snapshot from `_globalBlocksForCommand(...)`.
2. Current recognized partial block range from `_recognizedBlocksForCommand(...)`.
3. Existing overlay slices from `_overlaySelectedMarkupBlocks()`.
4. Ordinary active one-block native selection.

Rationale: Select All is the full-script emergency path; recognized range fixes cross-block handles; overlay slices are current fallback; native selection is safe only inside one block.

### Recognized Cut Mutation Rules

For a recognized range from block `A` to block `B`:

| Case | Required mutation |
|------|-------------------|
| `A == B` | Replace controller text with prefix before start + suffix after end. |
| `A < B` | Start block keeps prefix before start. Middle selected blocks become empty strings unless an existing tested merge behavior is deliberately reused. End block keeps suffix after end. |

Do not remove controllers during partial recognized cut unless a separate tested rule proves that removal preserves history, bookmarks, and block indexes. The initial safe behavior is to preserve block count.

### Overlay Endpoint API

Add a read-only getter to `GlobalSelectionOverlayState`:

| Getter | Contract |
|--------|----------|
| `currentRawRange` or equivalent | Returns start/end block indexes and raw offsets only when `hasSelection` is true. It does not mutate controllers. |

The parent may read this getter in `onSelectionChanged` to update `_recognizedBlockRange`.

### Invalidation Points

The runtime patch must call `_clearRecognizedBlockRange(...)` from every path below:

| Path | File |
|------|------|
| editor block tap and background tap | `script_editor_screen.build.dart` / `selection_clipboard.dart` |
| `_clearGlobalSelection()` | `script_editor_screen.selection_clipboard.dart` |
| `_deleteGlobalSelection()` | `script_editor_screen.selection_clipboard.dart` |
| `_loadText(...)`, `_clearControllers(...)`, `_removeBlock(...)`, split/merge flows | `script_editor_screen.load_blocks.dart` |
| `_undo()` and `_redo()` after applying state | `script_editor_screen.dialogs_history.dart` |
| `_findVisibleTextInEditor(...)` before search selection is applied | `script_editor_screen.search.dart` |
| `_goToEditorBookmark(...)` before bookmark selection is applied | `script_editor_screen.bookmarks.dart` |
| `_importFile()`, `_clearScript()` | `script_editor_screen.file_present.dart` |

If a path changes controllers, focus nodes, block keys, or raw text lengths outside a style command, it must clear the recognized range.

### Style Command Compatibility

Style commands must not read `_recognizedBlockRange` directly. They may act only on visible/current `externalSelection` ranges returned by `_styleTargets()`. This prevents hidden command metadata from styling text the user no longer sees as selected.

### Minimum Compile Gates Before Push

Before pushing a runtime implementation:

1. `git diff --check`
2. `flutter analyze --no-pub` on all touched iOS Dart files that accept file targets.
3. Confirm no non-iOS runtime folders are staged.
4. Force-add only the matching `_agent/mvp/Platform_iOS/*.md` docs if needed.
5. Push to main only after the staged diff shows exactly the intended iOS runtime files and docs.

### Stop Conditions

Do not continue implementing if any of these happens:

- Native one-block Cut/Copy stops working.
- Select All no longer shows Cut/Copy/Paste immediately afterward.
- `_blockClipboard` becomes plain text for styled in-app paste.
- Cross-block Cut waits for deselection before history records it.
- A second app toolbar or product-facing `Extend` button is reintroduced.
- Runtime changes require editing Windows, Android, or macOS files.

---

## Planned Test Matrix

| Test | Expected result |
|------|-----------------|
| Double-tap one word, Cut | Cuts only that word, native one-block path remains intact |
| Select text inside one block, Copy/Paste | Restores the same styled slice |
| Select All, Cut/Paste two styled blocks | Restores both blocks with styles and newlines |
| Recognized partial range from block 0 into block 1, Copy/Paste | Restores start slice + end slice in order with raw markup preserved |
| Recognized partial range across English and Hebrew blocks | Clipboard order follows script order; visual hit-testing respects block direction |
| Tap elsewhere after recognized range | Clears transient selection/range but preserves real clipboard |
| Undo after cross-block Cut | Restores immediately through history |

---

## Runtime Clarification - 2026-05-03

- `_recognizedBlocksForCommand(...)` must rebuild from
  `GlobalSelectionOverlayState.currentRawRange` when the overlay is currently
  visible. The live overlay endpoints are the user-facing truth; cached
  `_recognizedBlockRange` exists only as a transient command/debug mirror.
- If the live overlay range and cached range differ, update the cached range
  before slicing raw markup. This prevents a stale native one-block selection
  from winning after the user has dragged handles into another block.
- Native iOS `Select All` escalation must compare normalized
  `selection.start` / `selection.end`, never raw base/extent direction.
