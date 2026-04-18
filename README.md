# AutoTeleprompter v4.1.3
# (Core Teleprompter Engine - iOS - Android - macOS - Windows)

A high-performance, professional teleprompter engine for iOS, Android, macOS, and Windows, featuring a hardened autonomous development loop. Hardened at v4.0.7.

## Key Improvements (v4.1.3 - 2026-04-17)
- Style Selection Locked (Synchronous Read): Applying Bold → Italic → Underline in sequence on any selection no longer shrinks the amber highlight. Root cause: all prior attempts (arithmetic shift, visual-offset conversion, snapshot-before-wrap) ultimately failed because they tried to reconstruct or preserve the selection position BEFORE the wrap, but the post-wrap raw offset is already computed correctly and synchronously by `wrapSelection`/`applyInlineProperty` via `controller.value = ...`. iOS platform resets of `c.selection` can only occur at event-loop boundaries (platform messages), never mid-function during synchronous Dart execution. Fixed by: reading `c.selection` DIRECTLY after `wrapSelection`/`applyInlineProperty` returns (guaranteed correct at that instant), pinning it to `c.externalSelection`, and discarding the visual-offset-conversion round-trip entirely. Applies to all four paths: single-block and multi-block overlay in both `_applyStyleCmd` and `_applyInlineCmd`.
- Alignment Selection Preserved: Applying alignment (left/center/right/RTL/LTR) to a partial selection no longer corrupts the amber highlight. Root cause: `applyLayout` strips all alignment tags then re-wraps with the new tag — when the new tag is a different length than the old one (e.g., `[center]` = 8 chars vs `[left]` = 6 chars), all raw offsets in `externalSelection` shift, but were never updated. Fixed by: capturing visual character offsets (invariant to tag changes since alignment tags render at zero width) BEFORE apply, then converting back to raw offsets AFTER, and re-pinning `externalSelection`. Applied to both `onDirection` and `onAlign`.

## Key Improvements (v4.1.2 - 2026-04-17)
- Style Selection Locked (Native + Overlay): Applying Bold → Italic → Underline in sequence on any selection (native long-press or overlay drag handles) no longer shrinks the amber highlight. Root cause: the v4.1.1 fix was gated on `hadOverlaySelection` — when the user selected text with a native iOS long-press (no overlay handles), `externalSelection = null`, the gate evaluated to `false`, the fix was skipped, and iOS's async platform reset of `c.selection` (which occurs between gesture events) caused each subsequent style to use a stale, pre-tag offset, shrinking the visible range by `open.length` chars per application. Fixed by: (1) expanding the selection snapshot to fall back to `c.selection` when `externalSelection` is null, so the fix now covers native selection too; (2) always pinning `c.externalSelection` after wrap (so future styles read it instead of the platform-reset `c.selection`); (3) adding `!isCollapsed` guard in `StylingLogicMixin.wrapSelection` and `applyInlineProperty` to prevent collapsed sentinel externalSelections (used for out-of-range block suppression) from being mistaken for style targets.

## Key Improvements (v4.1.1 - 2026-04-17)
- Multi-Line Handle Drag Fixed (Global Coordinates): Handles now correctly drag to line 2+ text. Root cause: `_handleUpdate` was calling `editable.globalToLocal(globalPos)` and then passing the result to `editable.getPositionForPoint()`, which itself calls `globalToLocal()` internally — double-converting the coordinate and always shifting the touch point above line 1, so `getPositionForPoint` returned a line-1 position for any touch. Fixed by passing `globalPos` directly to `getPositionForPoint` without pre-converting.
- Style Selection Locked (Visual Offsets): Applying Bold → Italic → Underline in sequence no longer progressively shrinks the amber highlight. Root cause: the arithmetic shift (`oldStart + open.length`) is numerically correct but fragile against any tag-boundary edge case in the selection position. Fixed by converting `externalSelection.start/end` to visual character counts BEFORE the style command (using new `MarkupController.rawToVisualOffset`), then converting back to raw positions AFTER (using `visualToRawOffset`). Visual character counts are invariant to tag insertion/removal, so the amber highlight stays locked to the same visible characters regardless of how many style layers accumulate.

## Key Improvements (v4.1.0 - 2026-04-17)
- Multi-Line Handle Drag Fixed (Affinity): Handles now correctly track line 2+ positions after dragging. Root cause: `getLocalRectForCaret` was called with default `TextAffinity.upstream`, which places a wrap-boundary caret at the END of line 1 instead of the START of line 2. Even after `_endOffset` was correctly set to a line-2 position by `getPositionForPoint`, `_calculateHandlePositions` re-rendered the handle at line 1 on every frame update. Fixed by passing `affinity: TextAffinity.downstream` to every `getLocalRectForCaret` call in `_getOffsetForPosition`.
- Style Selection Locked (Arithmetic Shift): Applying Bold → Italic → Underline in sequence no longer progressively shrinks the amber highlight. Root cause: the previous fix read `c.selection` after `wrapSelection` to determine the new selection range, but on iOS the platform text input system can asynchronously reset `c.selection`, making the read unreliable. Fixed by computing the shift arithmetically: `open.length` is added (toggle-on) or subtracted (toggle-off) directly from the stored `oldStart`/`oldEnd` — `c.selection` is never read.

## Key Improvements (v4.0.9 - 2026-04-17)
- Multi-Line Handle Drag Fixed (Global-at-Start): `_stackKey.currentContext` can be temporarily null inside `onPanUpdate` during a setState rebuild. Fixed by converting the handle's Stack-local caret position to global coords ONCE in `onPanStart` (where layout is guaranteed valid from the previous frame) and storing it as `_panStartHandleGlobal`. `onPanUpdate` simply adds the finger delta to that stored global origin — no lookup needed.
- Style Selection Locked (Missing refresh()): `externalSelection` is a plain Dart field with no setter — assigning it never calls `notifyListeners()`. So after `wrapSelection` updated `externalSelection` to the post-insert positions, `buildTextSpan` was never re-invoked and continued rendering the old (pre-insert) offset range, causing the visible highlight to shrink by the tag length with each successive style. Fixed by calling `c.refresh()` immediately after every `c.externalSelection = ns` assignment.

## Key Improvements (v4.0.8 - 2026-04-17)
- Multi-Line Handle Drag Fixed (Delta Compensation): Handles no longer snap to line 1 when the finger lands at the top of the 56-px hit area. Root cause: `_handleUpdate` was passed `d.globalPosition` (finger touch) directly instead of the handle's logical caret position. Fixed by recording `_panStartGlobal` and `_panStartHandleLogical` on pan start, then deriving `adjustedGlobal = stackBox.localToGlobal(caretStart) + delta` and passing that to `_handleUpdate`.
- Style Selection Preserved After B/I/U: Applying bold/italic/underline/color/size no longer shrinks the amber highlight. Root cause: after `wrapSelection` inserted tags, `externalSelection` still held pre-insert offsets. Fixed by copying `controller.selection` (set correctly by `wrapSelection`) back to `externalSelection`, then calling `syncOffsetsFromExternalSelection` on the overlay to update `_startOffset`/`_endOffset` and recalculate handle positions.

## Key Improvements (v4.0.7 - 2026-04-17)
- Multi-Line Handle Drag Fixed: Handles can now be dragged to the second (and further) visual lines of wrapped text within a single block. Root cause: collapsing native controller.selection in _enterRefineMode() was corrupting RenderEditable's internal state used by getPositionForPoint(). Fixed by making selectionColor always transparent and removing the collapse — all amber rendering is now exclusively in MarkupController.buildTextSpan.

## Key Improvements (v4.0.6 - 2026-04-17)
- Highlight Preserved After Alignment: Applying alignment to a Select All selection no longer clears the amber highlight (overlay hasSelection guard added to _onSelectionChanged).
- Full-Block Highlight Fixed on Drag: Starting a drag from Select All no longer shows the entire block highlighted; only the dragged selection is amber (native selection collapsed in _enterRefineMode after _isGlobalSelection flips false).

## Key Improvements (v4.0.5 - 2026-04-17)
- Selection Handles Correct After Select All: Handles now appear at the true caret positions after Select All (deferred to post-frame).
- Highlight Clears Immediately on Drag: Deselected blocks no longer retain the amber highlight when a drag handle is moved.
- Handle Position Lag Fixed: Handle positions recalculate after each drag frame settles, not before.

## Key Improvements (v4.0.4 - 2026-04-17)
- Alignment Button Highlights After Apply: Tapping left/center/right in the layout suite now immediately lights up the correct button.
- Alignment Button Reflects Script on Load: Opening a Hebrew (right-aligned) script now shows the right button as active in the layout suite.
- Alignment Button Reflects Active Block When Suite Opens: Moving focus to the layout suite no longer resets the toolbar to left.

## Key Improvements (v4.0.3 - 2026-04-17)
- Upcoming Text Color Toggle: Restored correct override logic for uniform futureWordColor in presentation mode.
- B/I/U Single-Click Fix: Removed false-positive forward scan in _isStyleActiveAt.
- Hebrew Alignment Detection: Fixed _detectAlignAtCursor close tag format detection.

## Key Improvements (v4.0.2 - 2026-04-17)
- Multi-Platform Architecture: Clean lib/platform/ separation layer for iOS, Android, macOS, Windows.
- RTF Round-Trip: Full save + load fidelity including Hebrew/Arabic Unicode characters.
- Pages Export: Save as Apple Pages format (.pages) on iOS and macOS.
- Mic Button Fix: Reliable start/stop state on iOS - race condition resolved.
- Hebrew Colors in Presenter: Inline markup colors survive presentation mode.
- DOCX Round-Trip: Proper ZIP-based DOCX archive generation.

## Hardened Agentic Intelligence (v3.7.5)
The project includes a state-of-the-art autonomous development engine designed for precision, safety, and absolute visual proof.

### Agentic Safety Protocols
- Persistence Guard: Managed caffeinate bridge ensures the system stays awake during autonomous sessions.
- Surgical Backups: Mandatory path-mirroring before any file modification via the /backup command.
- Task Timer: Hard 30-minute safety limit per atomic task to prevent run-away processes.
- Auditor Layer (/logit): Mandatory universal documentation synchronization for every development cycle.
- Versioning Governance: Only the USER can authorize major stable version transitions.
- Cleanup Policy: User-verified [U] items are permanently preserved; cleanup only occurs on major releases at user request.

### Developer Hot Commands
- /run: Master Broad loop for multi-task fix sessions.
- /deep_run: Focused surgical loop for critical bugs.
- /fix: Surgical code injection of approved plans.
- /deep_fix: THREE-PHASE manual surgical fix.
- /deep_test: Hardened visual verification.
- /emulator: Absolute Rebuild Mandate.
- /logit: Universal terminal-based documentation sync.
- /plan: Priority-based planning with [TRIO-PATH].
- /sync: Automatically syncs the AI agent with project protocols.
- /organize: Smart Governance engine for dynamic artifact routing.
- /backup: Surgical mirrors and full session snapshots.
- /test: Basic stability and regression verification.

## Project Structure
- AutoTeleprompter/lib/: Flutter source code for the teleprompter engine.
- AutoTeleprompter/lib/platform/: Multi-platform abstraction layer (STT, file import, permissions, keyboard).
- _agent/: Hardened autonomous engine logic, workflows, and safety scripts.
- backups/: Surgical path-mirrors and full project archives.
- schemes/: Architectural loop schemes and loop blueprints.
- test/deep_analysis/: Visual loop verification artifacts and surgical test routes.
- DAILY_LOG.md: Real-time development diary and session history.
- MASTER_TODO.md: Centralized task tracking and bug status.
- AI_PROTOCOL.md: Mandatory agentic governance and safety rules (v3.7.5).
- Project platforms structure.md: Multi-platform architecture guide and development rules.

## v3.9.6 - Styling Engine Hardening (2026-04-12)
- Global Multi-Block Selection: Select All works across all paragraph blocks with drag handles.
- Style Toggle Engine: B/I/U/Color/Font correctly toggle on AND off, including nested styles.
- Professional History System: 10-char/10s typing bulking, suite-sectioned commits.
- Clear Style 3-Mode: Selection, word-level, and baseline modes.

## v3.9.8 - Teleprompter Hardening (2026-04-12)
- Hebrew STT Recognition: Expanded prefix stripping, phonetic normalization, lowered match thresholds.
- Improvisation Tolerance: Larger search window (60 words), relaxed distance penalties.
- Graceful Error Recovery: Non-fatal STT errors auto-restart silently.
- Presentation Font Scaling: 2x font multiplier restored for teleprompter presentation mode.

## v4.0 - Stable Release (2026-04-12)
- Core teleprompter feature set: Script editor, inline formatting, recent activity, and presentation mode.
- Premium features hidden and deferred to v4.1+.

## v4.0.1 - Native STT and Whisper Fallback Engine (2026-04-13)
- Native Android STT: Custom MethodChannel-based speech recognition.
- 4-Stage Fallback Chain for broad device compatibility.
- Whisper Offline STT: Sequential chunk design (2.5-4s chunks).

## v4.0.2 - iOS Hardening + Multi-Platform Separation (2026-04-17)
- lib/platform/ Architecture with abstract STT interface and platform adapters.
- DOCX, RTF, Pages export round-trips all fixed.
- Mic Button Race Fix and Hebrew Colors fix.

---

## Building for iOS (Without a Mac)
Since this project is managed on Windows, we use GitHub Actions to build the iOS version.

### How to get the iPhone App (.ipa):
1. Push your code: Simply commit and push your changes to GitHub.
2. Go to Actions: Visit the Actions tab on GitHub (https://github.com/abprogroup/AutoTeleprompter).
3. Choose the Workflow: Click on the latest "Build iOS IPA (Free Edition)" run.
4. Download: Scroll down to Artifacts and download the AutoTeleprompter-iOS zip.
5. Install: On your Windows laptop, use Sideloadly (https://sideloadly.io/) to install the .ipa onto your iPhone.

*Last Hardened: 2026-04-17 (v4.1.2 Native + Overlay Selection Lock — all selection paths pinned)*
