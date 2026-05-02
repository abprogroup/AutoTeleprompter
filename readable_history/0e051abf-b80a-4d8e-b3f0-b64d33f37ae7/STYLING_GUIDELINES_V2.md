# AutoTeleprompter Styling Guidelines v2.0 (The "MS Office" Protocol)

This document serves as the absolute source of truth for all styling, history, and synchronization logic within the AutoTeleprompter editor. Every implementation must strictly adhere to these rules.

## 1. Professional History & Bulking (Undo/Redo)
The history system must mimic Microsoft Office's behavior to prevent "pollution" while capturing meaningful changes.

### A. Typing Bulking Logic
- **10 Chars / 10s Rule**: Commit a history entry only after 10 characters are typed OR 10 seconds have elapsed since the last commit.
- **New Line Trigger**: Immediate history commit whenever a new line is introduced.
- **Quick Small Changes**: 1-10 letters should be bulked if they occur within the same 10s window.

### B. Suite-Based Bulking (The "Session" Protocol)
- **Modal Isolation**: When a Suite (Text, Layout, Color) is opened, capture a snapshot of the current text.
- **Unified Commit**: All edits made *while the suite is open* are bulked. A SINGLE history entry is created upon suite closure (if changes were made).
- **Sectioned Bulking**:
  - **Text Suite**: Bulk `Bold/Italic/Underline` as one section; `Font Size` as another; `Font Type` as the last.
  - **Layout Suite**: `Alignments` are one function; `Line Spacing` is another; `Letter Spacing` is another; `Word Spacing` is the last. Do not mix these together in the history list.

## 2. Global "Clear All" Formatting (The "C" Button)
- **Selection Mode**: If text is selected, clear tags only from selection.
- **Word Mode**: If the cursor is in the middle of a word, clear styles for the entire word.
- **Baseline Mode**: If no selection and cursor is at end of line/paragraph, clear the WHOLE script style.

## 3. Styling Suite Specifications

### A. Text Suite
- **Dynamic Preview**: The toolbar must sync with the selected text's styles.
- **State Highlighting**: Bold/Italic/Underline buttons must glow/highlight if active for the selection.
- **Auto-Word Inheritance**: If typing next to a letter, inherit its styling (Paragraph Styling Logic).
- **Silent Defaults**: If no text is selected, show default styling options.

### B. Layout Suite
- **Alignment Mutual Exclusivity**: Left, Center, and Right are 1-at-a-time.
  - Selecting a new alignment MUST purge all existing alignment/direction tags from the paragraph.
  - **Default Baseline**: If English (LTR) text has no alignment tags, it defaults to Left. Applying "Left" to it should remove all alignment tags to return to baseline.
- **Spacing Bulking**: Slider changes must be bulked per function (e.g., all Spacing adjustments in one suite session = 1 history entry for that specific spacing type).

### C. Color Suite
- **Live Sync**: Circular preview bubbles must update instantly when a color is picked.
- **Selection Inheritance**: Point of focus syncs with neared paragraph styling. Default to white text/none highlight if unstyled.

## 4. Stability & Performance (The "No-Regressions" Guard)
- **Silent Selection**: History selection must be a "silent thing to remember." Selection state should not pollute the history list or visually "tag" text during undo/redo actions.
- **Anti-Flicker**: No UI blinking or flickering during background tasks (e.g., Auto-Save). Rebuilds must be surgically constrained.
- **Overflow Prevention**: Font enlargement must never cause rows to overlap. Line height must adapt proportionally without colliding with adjacent blocks.
