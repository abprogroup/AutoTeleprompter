---
name: Selection MVP
type: component
platform: iOS
last_updated: 2026-05-03
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
| `_agent/mvp/Platform_iOS/block_selection_recognition_mvp.md` | Planned companion MVP for block-aware partial selection recognition without replacing native one-block selection |

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

4. **`selectionColor` always transparent**: `_EditorBlock` on iOS hardcodes `selectionColor: Colors.transparent`. Native selection paint is never visible — amber rendering is done by `MarkupController.buildTextSpan` from native `controller.selection`, `externalSelection`, or `isGlobalSelected`. Do NOT make this conditional.

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

13. **Native plain paste must be intercepted**: When a rich multi-block
    `_blockClipboard` exists, iOS may still route the toolbar Paste through the
    system plain-text clipboard. The controller listener must detect insertion
    of the plain companion text and immediately replace it with
    `_pasteFromGlobalClipboard()` so styles and paragraph block boundaries are
    restored from raw markup.

14. **User navigation dismisses stale selection snapshots**: A real user tap
    into another block or editor background must clear `_isGlobalSelection`,
    overlay/external selections, native non-collapsed selections, and the
    temporary `_globalSelectionSnapshot`. It must NOT clear `_blockClipboard`;
    Cut/Paste recovery still needs the real paste clipboard. This prevents a
    recent Select All snapshot from poisoning later Cut/Copy after the user has
    visibly moved away and started a new selection.

15. **Handle drags publish the live selected range**: Dragging global selection
    handles must call the parent selection-change path after every range
    update. The parent must snapshot the current overlay-selected raw markup
    slices so debug clipboard shape, Copy, Cut, and Paste all operate on the
    visible handle range rather than a stale Select All snapshot.

16. **Scroll keeps handles in sync**: Editor scroll notifications must refresh
    `GlobalSelectionOverlay` handle positions. Selection handles are screen
    overlays; their coordinates must be recalculated after the underlying
    `ListView` scrolls.

17. **Offscreen handles must hide, not clamp**: If a selection endpoint scrolls
    outside the editor viewport, its handle must disappear until the endpoint is
    visible again. Handles may remain visible only while the user is actively
    dragging that handle. Never clamp an offscreen handle to the top/bottom edge
    because that visually lies about the selected text location.

18. **Only handle-refined overlay snapshots may shrink protected snapshots**:
    Native iOS selection/menu events are allowed to report only the originally
    touched `TextField`. Those events must not downgrade a recent multi-block
    `_globalSelectionSnapshot` to one block. A smaller snapshot is valid only
    after real overlay handle refinement, where the visible dragged range is the
    intended clipboard range.

19. **Native handles are allowed only for ordinary one-block selection**:
    `_EditorBlock` may let Flutter/iOS use default native selection controls
    only when neither global selection nor overlay selection is active. As soon
    as the app is in Select All/global/overlay mode, `GhostSelectionControls`
    must hide native handles so the app overlay remains the single visible
    handle system. This is intentionally not the rejected app-toolbar/autoscroll
    patch.

20. **Partial native selections must not auto-promote while the menu builds**:
    Because each paragraph block is a separate iOS `TextField`, native iOS
    selection handles cannot cross a newline/block boundary. A partial,
    non-full-block native selection must remain an ordinary one-block
    selection while the native/adaptive context menu is merely being built.
    Do not expose a vague product-facing `Extend` button. Do not promote from
    passive `_onSelectionChanged()` listener events or from toolbar-build
    side effects. Any future cross-block promotion entry must be explicit,
    command-owned, and device-tested against Select All first. Promotion is
    forbidden during `_isGlobalSelection`, command execution, full-block
    Select All, or any already-active overlay selection. It must not add an
    app-owned floating Cut/Copy/Paste toolbar, edge-scroll timer, or alternate
    clipboard command path.

21. **Handle drag hit-testing must include block boundaries**: Overlay handle
    dragging must let endpoints reach offset `0` and `text.length` for the
    current block, including the small visual corridor above/below a paragraph.
    Once the pointer is inside the next rendered block, that next block must win
    hit-testing so the handle can continue crossing blocks instead of sticking
    near a newline. This is boundary snapping only; it is not timer-based
    autoscroll.

22. **Overlay Cut/Copy must use overlay slices, not stale native actions**:
    After native-menu promotion converts a native partial selection into overlay
    handles, overlay-mode context-menu Cut/Copy and the app's keyboard Copy
    shortcut must route to `_onCutClean()` / `_onCopyClean()`. Overlay
    clipboard storage must prefer the visible overlay-selected raw slices and
    must not be replaced by an older protected full-script snapshot. Flutter
    3.24.3 does not expose `CutSelectionTextIntent`, so do not depend on that
    symbol in iOS workflow builds.

23. **Partial native menu must remain the command surface**: A partial
    native iOS selection is still limited to one `TextField`, so its context
    menu must show app-owned `Cut`, `Copy`, `Select All`, and optional `Paste`
    actions instead of burying the user in native-only `Lookup` / `Search Web`
    actions. The app must not promote the confirmed partial selection into
    overlay handles just because the menu opened; that stale one-word overlay
    can beat the user's later Select All command. It must not add an `Extend`
    product action or a separate app command bar.

24. **Select All must leave a Cut/Copy affordance**: When a native context-menu
    `Select All` command routes through `_selectAllBlocks()`, the toolbar must
    reopen/rebuild into the global selection command state so the user can
    immediately Cut/Copy/Paste the global selection. Do not close the user into
    a selected state with no visible command path.

25. **Block recognition is the safe extension point**: Partial cross-block
    selection is improved through
    `_agent/mvp/Platform_iOS/block_selection_recognition_mvp.md`, not by adding
    another toolbar, replacing Select All, or passively adopting every native
    selection event. The app may learn block endpoints and build raw-markup
    clipboard slices, but native one-block selection and Select All recovery
    must stay intact.

26. **Recognized partial ranges are transient command metadata**:
    `_recognizedBlockRange` may mirror the current refined overlay handle
    range so Cut/Copy can consume the exact visible cross-block selection. It
    is not persisted, not a styling authority, not a bookmark state, and not a
    replacement for `externalSelection`. Any script reload, block mutation,
    search/bookmark jump, undo/redo, clear, or user navigation must clear it
    without clearing the real `_blockClipboard`.

---

## Forbidden Changes

- Do not make `selectionColor` conditional on `isGlobalSelected` — it must always be `Colors.transparent` on iOS. Adding a condition breaks the multi-line drag and creates spurious amber flashes.
- Do not collapse `controller.selection` in `_enterRefineMode()` — this is the v4.0.7 multi-line drag fix. The transparent `selectionColor` already ensures the native selection is invisible.
- Do not remove `GhostSelectionControls` from global/overlay selection mode — native iOS circle handles will reappear and interfere with the overlay handle system. Ordinary one-block native selection may use native controls only while the overlay/global system is inactive.
- Do not call `_clearGlobalSelection()` inside `_onSelectionChanged()` for a collapsed cursor — that cursor was placed by `_selectAllBlocks()` to enable keyboard delete and must not trigger a clear.
- Do not call `c.refresh()` after setting `_isCommandExecuting = true` without immediately setting it back to `false` — the guard only suppresses listener reactions during a brief synchronous window.
- Do not let a native one-block iOS selection event overwrite a protected
  multi-block snapshot. Select All + Cut/Copy must keep all selected blocks
  unless the user actually refines the overlay handles.
- Do not reintroduce passive listener-based native selection adoption, the
  rejected custom app toolbar, or timer-based edge autoscroll while extending
  native partial selections into overlay handles.
  Cross-block dragging must reuse the existing overlay handle and clipboard
  paths only.
- Do not shrink the handle drag boundary back to the exact `RenderBox` height.
  That recreates the dead zone where handles stop before the selected text can
  reach the start/end of a paragraph block.
- Do not let overlay Cut/Copy call the active `TextField` native command after
  handles have crossed blocks. That cuts only the originally touched block while
  the overlay highlight spans more text.
- Do not call `extendNativeBlockSelection` from `_onSelectionChanged()` or any
  passive native selection listener. It is allowed only from the partial native
  context-menu build path for a confirmed user selection.
- Do not let the partial native selection menu fall back to native-only
  Lookup/Search Web actions when the app needs to expose Cut/Copy/Select All
  for the cross-block overlay bridge.
- Do not let context-menu Select All hide Cut/Copy afterward. It must reopen or
  rebuild into the global command menu.
- Do not implement partial block recognition without first following
  `_agent/mvp/Platform_iOS/block_selection_recognition_mvp.md`.

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
- Do not rely on the system clipboard for in-app multi-block paste. It is only
  a companion to make the native toolbar expose Paste; the app-private
  `_blockClipboard` is the source of truth for styled block restoration.
- Do not let `_globalSelectionSnapshot` behave like a hidden permanent
  selection. It is a short-lived native-menu recovery bridge only; once the
  user taps away to navigate/edit elsewhere, it must be discarded without
  discarding `_blockClipboard`.
- Do not let partial overlay Cut fall through to the full-script delete path.
  Handle-drag selections may span part of one or more blocks; Cut must remove
  only each selected external range while storing those selected raw slices in
  the app-private clipboard.
- Do not restore the old viewport-edge fallback for selection handles. Hidden
  offscreen endpoints are less misleading than handles floating at an unrelated
  edge of the screen.
- Do not adopt a full-block native selection into the partial overlay path.
  Full-block native selection is the iOS Select All bridge and must continue to
  route through `_selectAllBlocks()` so protected multi-block snapshots stay
  intact.
- Do not let `_storeBlockClipboard()` promote an old protected Select All
  snapshot while handling `copy-overlay` or `cut-overlay`. Overlay commands
  must store exactly the visible handle-selected slices.

- **`c.refresh()` triggers listener**: Any `c.refresh()` call fires the `addListener` callback. If called when `_isCommandExecuting=false` and `_isGlobalSelection=true`, `_onSelectionChanged()` runs immediately. Always verify the active controller's selection state is full-block (not partial) before calling refresh in that window.
- **Overlay `_enterRefineMode` timing**: It fires during `onPanStart` of a handle drag. The `onSelectionChanged` callback it triggers causes `_isGlobalSelection` to update in the parent widget. Any code that runs between `_enterRefineMode` and the parent's `setState` sees an inconsistent state.
- **`_resyncGlobalSelection` + postFrameCallback**: The `overlay.selectAll()` in the postFrameCallback fires after layout, which fires `c.refresh()` again. Verify escalation is blocked (`_isGlobalSelection=true` and `_overlayKey.currentState?.hasSelection=true`) before adding any code near that path.
- **iOS context-menu timing**: Native iOS may reset the active `TextField`
  selection or fire a tap-through before the menu action reaches Flutter. The
  short-lived global selection snapshot exists only to let Cut/Copy recover the
  intended multi-block selection; it must not become a permanent hidden
  selection state. Paste may also use it as a fallback when native Cut bypassed
  the in-app Cut command but Select All was captured correctly.

## Rejected Approach Log

- **2026-05-02 rejected selection-toolbar/autoscroll patch**: Do not reapply the
  attempted approach that promoted every native double-tap word selection into
  app overlay handles, added an overlay-owned Cut/Copy/Paste toolbar, and ran
  timer-based edge autoscroll from handle drag updates. Device QA showed this
  created native/app selection collisions: Select All degraded to one block,
  duplicate native + app toolbars appeared, and handle dragging could scroll
  indefinitely. Future selection work must isolate one behavior at a time and
  preserve the carefully crafted iOS native-menu recovery path.
- **2026-05-02 rejected automatic native-adoption patch**: Do not reapply the
  follow-up that automatically converted passive native word-selection events
  into overlay mode and broadened overlay menu interception. Device QA showed
  Select All stopped working, cross-block overlay Cut/Copy still used only the
  originally touched block, and history did not commit the cut until later
  deselection. The safer replacement avoids passive listener adoption and
  limits promotion to the partial native context-menu build path, with the
  native/adaptive toolbar remaining the visible command surface.

---

## iOS Device Regression Repair - 2026-05-03

- Native iOS full-block selection may report reversed `baseOffset` /
  `extentOffset`. The full-block escalation check must use normalized
  `selection.start == 0` and `selection.end == text.length`, or system
  `Select All` can remain trapped inside the originally touched paragraph.
- Cross-block handle Cut/Copy must resolve the command range from the live
  `GlobalSelectionOverlayState.currentRawRange` at command time. Do not rely
  only on previously cached `_recognizedBlockRange`; iOS toolbar/focus timing
  can leave cached command metadata stale while the visible handles are
  correct.
- The active command order remains unchanged: full Select All first, live
  recognized overlay range second, overlay slices third, native one-block
  selection last.
- Follow-up QA showed Cut could still call Copy first and let the original
  native word/block overwrite the intended overlay clipboard. `_onCutClean()`
  must not call `_onCopyClean()` before evaluating live overlay/recognized
  ranges.
- If overlay handles are visible, Cut/Copy must never fall back to a recent
  protected Select All snapshot or active one-block native selection. Protected
  snapshots are for full Select All recovery only.
- Paste must preserve the app-private `_blockClipboard` after restoring blocks
  so the same styled block clipboard can be pasted more than once.
- Cut must force an immediate history baseline before destructive mutation and
  then commit the Cut state, so Undo is available immediately after the cut
  without requiring the user to tap elsewhere first.
- The toolbar `Select All` button must be an app-owned custom toolbar action,
  not a `ContextMenuButtonType.selectAll` item that can fall through to native
  one-`TextField` semantics. It must call `_selectAllBlocks()` directly,
  re-arm once after the native toolbar callback window, and then reopen into
  the app-owned global Cut/Copy/Paste menu.
- `_selectAllBlocks()` owns a short native-menu guard window. During that
  window, late native word-selection callbacks must not clear the app global
  selection back to the originally double-tapped word.
- A double-tapped word toolbar is a passive menu-open state. It must not call
  `_extendNativeSelectionToOverlay()` from `contextMenuBuilder`; otherwise the
  app creates a one-word overlay before the user presses Select All and the
  full-script Select All path can appear to do nothing.

---

## Architectural Lesson - Native Selection Is Not Script Selection

- Native iOS selection is useful only as a one-`TextField` editing helper:
  cursor placement, word selection, ordinary one-block Cut/Copy, and keyboard
  behavior.
- Native iOS selection must not own any script-level selection feature. The
  editor is a multi-block styled script surface, not one native text control.
  Features that span blocks, preserve raw markup, write history, sync
  bookmarks, or affect presenter handoff must be owned by the app selection MVP.
- `GlobalSelectionOverlay` is the intended app-owned selection authority for
  script-level ranges. A mature implementation may allow native gestures to
  detect the initial user intent, but the app overlay/range model must own the
  selected raw range before cross-block Cut/Copy/Style operations run.
- Do not try to save implementation effort by combining native handle ownership
  with app overlay ownership. Device QA proved that this creates repeated
  regressions: Select All downgrades to one block, clipboard reads stale native
  ranges, history commits late, and app/native toolbars collide.
- Future selection development should be planned as `GlobalSelectionOverlay`
  quality work: precise hit-testing, LTR/RTL block boundaries, scroll-aware
  handle positions, offscreen handle hiding, raw range slicing, and one
  deterministic command router.

---

## Runtime Direction - Guarded Native-to-Overlay Handoff

- Native double-tap may detect the first one-block selection, but after the
  toolbar opens the app may hand that range to `GlobalSelectionOverlay` so the
  app overlay becomes the handle owner.
- This handoff is allowed only through the existing `_extendNativeSelectionToOverlay`
  command path. It is still forbidden from passive `_onSelectionChanged()`
  listener events.
- The handoff must be blocked while `_selectAllBlocks()` owns the native-menu
  guard window. Select All is the full-script escape path and must never be
  downgraded back to the originally double-tapped word.
- Cut/Copy from a partial-selection toolbar should call the handoff path before
  command routing, so `_onCutClean()` / `_onCopyClean()` can read the live
  app-owned overlay range instead of stale native one-block selection.
- Any overlay/global toolbar `Select All` button must use the same re-armed
  app-owned Select All path as the stable double-tap fix. Do not use a raw
  native `ContextMenuButtonType.selectAll` action.
- Native handles must be hidden whenever a non-collapsed native range,
  overlay range, or global selection exists. The native selection can detect
  the initial word/range, but the user must drag only app-owned overlay
  handles after handoff.
- If `_blockClipboard` already exists, iOS may rebuild the toolbar with only
  Paste/Select All. The editor must force app-owned Cut/Copy actions whenever
  any selectable native/overlay/global range exists, so a new selection is not
  trapped behind a stale paste-only menu.
- Device QA proved the previous handle-command repair was still insufficient:
  the visible amber app highlight could remain while command routing fell back
  to the originally double-tapped native word. `_onCutClean()` and
  `_onCopyClean()` must therefore prefer current visible app-owned selections
  from `MarkupController.isGlobalSelected` / non-collapsed
  `MarkupController.externalSelection` before they ever fall back to a native
  one-block `controller.selection`.
- That visible app-owned selection check must run before stale recognized or
  overlay command mirrors can win. If those mirrors still point at the original
  double-tapped word while `externalSelection` visibly spans more text, the
  visible app highlight owns the command.
- Exception: when the live recognized/overlay raw range contains more block
  slices than the visible fallback, the recognized raw range must win. The
  visible fallback cannot represent selected empty paragraph blocks, so using it
  first can collapse a selection shaped like text-empty-text-empty-text into
  only the non-empty slices.
- Plain and rich clipboard companions must preserve empty selected block slices
  too. Do not filter empty blocks out of `_plainTextForBlocks()` or rich
  clipboard serialization when they are part of the selected range.
- A stored recognized range may remain authoritative even if the live overlay
  range cannot be re-read during the toolbar command callback. If a visible app
  selection exists and the stored recognized range preserves more block slices
  than the visible fallback, the stored recognized range must win.
- Debug output must distinguish this path as `copy-recognized-stored` or
  `cut-recognized-stored` so device QA can prove which command source won.
- Debug sentry must expose command candidate shapes (`r`, `v`, `o`) and the
  chosen source for Cut/Copy while this selection work remains pending. Do not
  remove that diagnostic until device QA proves the app-owned selection route.
- A visible app highlight is command data. If the user can see highlighted text
  from the app selection layer, Cut/Copy must store those raw-markup slices in
  `_blockClipboard` and must not return an empty clipboard or the original
  tapped word.
- `_EditorBlock` toolbar construction must treat non-collapsed
  `MarkupController.externalSelection` as a selectable app range even if the
  parent overlay state is stale. Otherwise iOS can show only Paste/Select All
  while the user visibly has a selected range.
- Even ordinary one-block Copy fallback must write `_blockClipboard` in
  addition to the rich/system clipboard. In-app Paste must not depend on a
  separate external clipboard path after Copy.
