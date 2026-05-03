---
name: Styling Engine MVP
type: component
platform: iOS
last_updated: 2026-05-03
---

# Styling Engine MVP - iOS

Governs iOS markup transformation, invisible tag rendering, clipboard-safe rich
text behavior, selection-sensitive style commands, and style metadata
propagation through editor, settings, and exports.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/editor/markup_controller.dart` | Hidden-tag controller, `buildTextSpan`, external selection bridge |
| `Platform_iOS/lib/features/script/widgets/editor/styling_logic_mixin.dart` | Style commands, tag application/removal, recent snippet and clipboard-safe behavior |
| `Platform_iOS/lib/features/script/services/styling_service.dart` | Feature-level style parsing/transforms |
| `Platform_iOS/lib/core/services/styling_service.dart` | Shared style parser/renderer helpers |
| `Platform_iOS/lib/core/services/rich_clipboard.dart` | Plain/rich clipboard boundary |
| `Platform_iOS/lib/features/script/models/cursor_style.dart` | Cursor style state bridge |
| `Platform_iOS/lib/core/widgets/global_color_picker.dart` | Shared color picker used by style controls |

## External API

| Method / Field | Caller |
|----------------|--------|
| `MarkupController.text` | Editor, save/export, history |
| `MarkupController.externalSelection` | Global selection overlay and editor blocks |
| `MarkupController.buildTextSpan(...)` | Text field rendering |
| `StylingLogicMixin` style commands | Editor toolbar/suites |
| `StylingService` parse/render helpers | Editor, file I/O, teleprompter rendering |
| `RichClipboard.copy(...)` | Copy/cut paths |
| `cursorStyleProvider` | Editor suites and selection change handler |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Script editor | `script_editor_screen.dart` | Applies style commands and reads active style |
| Selection MVP | `global_selection_overlay.dart`, editor screen | Supplies selection boundaries |
| Editor suites | `text_suite_mvp.dart`, `layout_suite_mvp.dart`, `color_suite_mvp.dart`, `formatting_toolbar_mvp.dart` | Invoke style commands |
| File I/O | `docx_service.dart`, `rtf_service.dart`, `pages_service.dart` | Converts markup to export bytes |
| Teleprompter screen | `teleprompter_screen.dart` | Renders styled script without exposing tags |

## Invariants

1. Internal markup tags stay in raw text; user-visible rendering hides tags.
2. Clipboard/recent snippets must not leak hidden markup unless rich clipboard
   semantics explicitly require it.
3. Selection-sensitive commands apply only to selected ranges or active cursor
   style, never to unrelated blocks.
4. Color, font, size, alignment, spacing, bold, italic, and underline tags must
   round-trip through save/restore/export paths.
5. Rendering must avoid mutating controller text.

## Forbidden Changes

- Do not strip all tags as a generic cleanup.
- Do not expose hidden markup in normal paste, recent script titles, or snippets.
- Do not apply style commands across block boundaries without selection mapping.
- Do not fork styling rules between editor and teleprompter without documenting both.

## Known Fragilities

- Raw offsets and visible offsets diverge when tags are hidden.
- Nested/overlapping tags can corrupt style detection.
- Clipboard paths can accidentally leak markup.
- Shared styling services exist in both `core` and feature folders.

## Shared-File Ownership Notes

Styling owns style transforms in `script_editor_screen.dart`; Selection owns
range geometry, History owns snapshot timing, and File I/O owns export encoding.

---

## iOS One Font-Size Authority Port - 2026-05-02

- Inline `[size=...]` tags remain valid styling markup for selected text.
- The global editor/presenter font-size control is not the same thing as inline
  `[size=...]` detection. Global font-size must be stored as script metadata.
- Style commands must not accidentally wrap selected text in `[size=...]` when
  the user intended to change the script-wide font-size control.
- Export/import work must preserve inline size tags while also preserving the
  script-level metadata font size.

---

## iOS App-Owned Selection Styling Boundary - 2026-05-03

- App-owned selected text is represented to styling commands through
  `MarkupController.externalSelection` and `isGlobalSelected`, not through
  native iOS `controller.selection` once overlay ownership begins.
- Styling commands must continue to call overlay resync/refresh after inserting
  or removing tags, because raw offsets move while the user's visible selected
  range should stay anchored to the same visible text.
- The selected-text app toolbar owns Cut/Copy/Paste/Select All only. It must not
  replace the Text/Layout/Color formatting suites or become a second styling
  toolbar.
