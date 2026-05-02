# Implementation Plan - Regression Repair (v3.9.5.59)

The goal is to resolve critical regressions in text presentation and editor behavior that appeared after the Atomic Modularization.

## User Review Required

> [!IMPORTANT]
> **Text Spacing**: We will re-inject the necessary trailing space in the `Text()` widget of the prompter screens to ensure words don't stick together.
> **Select All**: We will audit the `GlobalSelectionOverlay` and its interaction with individual `MarkupController` instances to ensure cross-paragraph selection is definitively restored.

## Proposed Changes

### Presentation Layer

#### [MODIFY] [teleprompter_screen.dart](file:///Users/proapple/Desktop/AutoTeleprompter/AutoTeleprompter/lib/features/teleprompter/widgets/teleprompter_screen.dart)
#### [MODIFY] [content_creator_screen.dart](file:///Users/proapple/Desktop/AutoTeleprompter/AutoTeleprompter/lib/features/teleprompter/widgets/content_creator_screen.dart)
- Append a space `' '` to `displayText` for all non-last words in a paragraph.
- Calibrate the `height` (line-height) to be proportional to `settings.fontSize`.

### Editor Layer

#### [MODIFY] [script_editor_screen.dart](file:///Users/proapple/Desktop/AutoTeleprompter/AutoTeleprompter/lib/features/script/widgets/script_editor_screen.dart)
- Update `_selectAllBlocks()` to explicitly call `selectAll()` on EVERY controller in the list, ensuring global selection state is mirrored.
- Audit the regex used in `MarkupController` to ensure common tags like `[center]` are properly handled/hidden.

## Verification Plan

### Manual Verification
- **Functional Check**: Open prompter/content creator and verify spaces between words.
- **Functional Check**: Verify tags like `[center]` are hidden in the editor and prompter.
- **Functional Check**: Press Ctrl+A and verify all paragraphs are amber-highlighted.
