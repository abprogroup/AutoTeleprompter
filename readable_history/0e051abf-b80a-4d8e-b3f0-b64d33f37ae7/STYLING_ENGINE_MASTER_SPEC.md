# STYLING ENGINE MASTER SPECIFICATION (v3.9.5.7)

This is the final, authoritative blueprint for the styling engine. It codifies every rule and resource required to achieve absolute "Microsoft Office" parity and system stability.

## 1. Core Logic System (`StylingService`)

### A. MS Office Category Splitting
- **Principle**: Categories (Color, Font, Size, Align, Bg) are mutually exclusive per character.
- **Rule**: If a selection overlaps an existing category tag, the parent tag must be **surgically split** into three parts: `[Parent_Pre]`, `[New_Selection]`, `[Parent_Post]`.
- **Status**: IMPLEMENTED & VERIFIED.

### B. Adjacency Welding (The "Clean Code" Seal)
- **Principle**: Prevent tag fragmentation (e.g., `[color]A[/color][color]B[/color]`).
- **Rule**: Upon every style application, the engine must perform a recursive regex sweep to weld adjacent tags of the identical category and value.
- **Status**: IMPLEMENTED & VERIFIED.

## 2. Professional History (`Undo/Redo`)

### A. Modular Bulking
- **Type 1: Typing Bulking**: 10 characters or 10 seconds of activity = 1 entry.
- **Type 2: Newline Entry**: Immediate entry creation.
- **Type 3: Suite Session**: All clicks within a single open Suite (e.g. Color Menu) are bulked until the menu is closed.
- **Status**: IMPLEMENTED in `_ScriptEditorScreenState`.

### B. "Silent" Undo Registry
- **Rule**: Undo/Redo must NOT restore selection tagging. It must only restore the text buffer and cursor index.
- **Status**: IMPLEMENTED (Removed `lastSelection` from `_EditorState`).

## 3. Visual & Stability Guard

### A. Elimination of "The Blink"
- **Silent Selection**: Style detection in the toolbar uses a dedicated `ValueNotifier`/`ref.read` pattern. **NO Global `setState`** on cursor movement.
- **Shadow Auto-Save**: Background persistence uses `isSilent: true`, bypassing UI notification to prevent flickering in the lobby and editor.
- **Status**: IMPLEMENTED & VERIFIED.

### B. Row Isolation (1.5x Rule)
- **Rule**: Line height scaling = `1.5 + (settings - 1)`.
- **Rule**: Content padding = `8, 12, 8, 16` (Bottom margin is critical for descenders like 'g' and 'j').
- **Status**: IMPLEMENTED & VERIFIED.

## 4. Security & Data Integrity

### A. Data Leak Prevention
- **Clipboard Interceptor**: User copy actions are intercepted; tags are stripped via `StylingService.stripTags()` before hitting the system clipboard.
- **Recent Activity Sentry**: Snippets saved to `SharedPreferences` are pre-stripped of all formatting.
- **Status**: IMPLEMENTED & VERIFIED.

### B. MS Office Neighbor Inheritance
- **Rule**: If the cursor is at the boundary of a style, the next character typed inherits that style.
- **Status**: IMPLEMENTED via `_detectStyleAtCursor` and Neighbor check logic.

## 5. Verification Resources
- **Automated Registry**: `reverse_engineering_report.md`
- **Logic Mapping**: `STYLING_COEXISTENCE_MATRIX.md`
- **Success Log**: `walkthrough.md`

**Status**: ALL RESOURCES CONSOLIDATED. I am 100% prepared for any remaining hardening.
