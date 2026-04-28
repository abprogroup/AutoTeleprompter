---
name: Styling Engine MVP
type: component
platform: Windows
last_updated: 2026-04-28
---

# Styling Engine MVP - Windows

Governs internal markup, tag rendering, style application/removal, style
detection, alignment/direction wrappers, color/font/size semantics, hidden-tag
selection behavior, and no-leak transformations for clipboard/recent/export.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/widgets/editor/styling_logic_mixin.dart` | `wrapSelection`, `applyInlineProperty`, `broadcastAlign`, style active detection, partial style removal |
| `Platform_Windows/lib/features/script/widgets/editor/markup_controller.dart` | Hidden tag rendering, tag-skipping backspace, selection snapping, raw/visual offset conversion |
| `Platform_Windows/lib/features/script/services/styling_service.dart` | Script-level styling helpers and HTML conversion |
| `Platform_Windows/lib/core/services/styling_service.dart` | Core duplicate styling helper used by shared surfaces |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | `_applyStyleCmd`, `_applyInlineCmd`, `onAlign`, `onDirection`, `_detect*AtCursor`, `_clearStyleAtCursor`, color remove paths |
| `Platform_Windows/lib/features/script/models/cursor_style.dart` | `CursorStyle` and `cursorStyleProvider` state bridge |
| `Platform_Windows/lib/core/services/rich_clipboard.dart` | Rich clipboard output after style stripping/conversion |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `StylingLogicMixin.wrapSelection(...)` | Editor style commands |
| `StylingLogicMixin.applyInlineProperty(...)` | Font/color/size/highlight commands |
| `StylingLogicMixin.broadcastAlign(...)` | Alignment commands |
| `MarkupController.buildTextSpan(...)` | Flutter text field rendering |
| `MarkupController.rawToVisualOffset(...)` / `visualToRawOffset(...)` | Alignment selection preservation |
| `MarkupController.value` override | Text input, backspace, selection snapping |
| `cursorStyleProvider` | Editor suites |
| `StylingService.stripTags(...)` | Clipboard/recent/export snippets |
| `StylingService.applyLayout(...)` | Alignment wrappers |
| `StylingService.markupToHtml(...)` | Rich clipboard |
| `MarkupExportService.parse(...)` | File export conversion from raw markup into styled document runs |
| `MarkupExportService.toPlainText(...)` | Plain export conversion from raw markup into visible text |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Text suite | `text_suite_mvp.dart` | Calls bold/italic/underline/font/size callbacks; reads cursor style |
| Color suite | `color_suite_mvp.dart` | Calls text/highlight/background callbacks; reads cursor colors |
| Layout suite | `layout_suite_mvp.dart` | Calls align/direction/spacing callbacks; reads cursor alignment |
| Formatting toolbar | `formatting_toolbar_mvp.dart` | Orchestrates suite callbacks |
| Editor copy/cut/save | `script_editor_screen.dart` | Uses stripping/conversion and style mutation |
| Teleprompter render | `teleprompter_screen.dart` and `word_aligner.dart` | Parse markup into styled words/spans |
| File services | `docx_service.dart`, `rtf_service.dart`, `pages_service.dart` | Generate document output from internal markup |

---

## Invariants

1. **Internal markup is the source of truth**: Bold, italic, underline, color,
   highlight, font, size, align, and direction are represented as tags in raw
   text.

2. **Tags render invisible in the editor**: `MarkupController._tagStyle` must keep
   tags visually hidden while preserving raw offsets.

3. **Backspace skips hidden tags**: Deleting near hidden markup must delete
   visible content rather than slowly exposing/removing tag characters.

4. **Selections cannot land inside tags**: Selection snapping must keep raw
   selection boundaries outside tag tokens.

5. **Category styles are mutually exclusive per range**: Color, background,
   font, size, alignment, and direction must not stack conflicting same-family
   wrappers on the same visible range.

6. **Additive styles toggle**: Bold, italic, and underline coexist with category
   styles and toggle off when selection is already enclosed.

7. **Alignment/direction are paragraph-level**: Applying alignment or direction
   strips previous paragraph layout tags before writing the new wrapper.

8. **Cursor style detection is silent**: `_onSelectionChanged()` updates
   `cursorStyleProvider`; cursor movement must not rebuild the whole editor or
   save history.

9. **Style commands preserve highlighted selection**: After wrapping, command
   paths must pin post-wrap selection to `externalSelection` and refresh/sync
   overlay state.

10. **No raw-tag leaks**: Clipboard, recent snippets, plain-text exports, and
    generated document files must expose only visible script text or real
    document styling, not internal tags.

11. **Display-only symbols are preserved**: Tokenization may create
    `ScriptWord` entries whose `normalized` value is empty when the visible token
    is punctuation or a symbol such as `"` or `»`. These tokens are unspeakable
    for STT alignment but must still render in presentation mode.

12. **Font-size metadata is never scaled in the editor**: The editor text field,
    font suite, script metadata, file export, and style tags all use the same
    saved font-size number. Any presentation enlargement belongs only to the
    teleprompter render path.

---

## Forbidden Changes

- Do not make hidden tags visible as a debugging shortcut.
- Do not remove selection snapping or tag-skipping backspace.
- Do not use ad hoc string replacement for a style family if an existing helper
  handles the case.
- Do not let alignment tags nest or accumulate.
- Do not let copy/paste expose raw style tags to the user.
- Do not use editor preview scaling to mutate or reinterpret
  `settings.fontSize`, `[size=...]` tags, script metadata, or exported document
  sizes.
- Do not add history saves to cursor/style detection.
- Do not skip punctuation-only or symbol-only tokens merely because
  `normalizeForMatching()` returns an empty string. Skip only empty markup/tag
  residue.

---

## Known Fragilities

- **Nested markup**: Overlapping tags can break flat regex parsers. Prefer
  well-formed wrappers.
- **Raw/visual offset conversion**: Correct for zero-width alignment tags but not
  a universal fix for every style path.
- **Duplicate service files**: Both `core/services/styling_service.dart` and
  `features/script/services/styling_service.dart` exist. Check imports before
  editing.
- **Color parsing**: Hex colors may be 6 or 8 chars depending on source.
- **Display vs speech tokens**: Presentation rendering and STT alignment share
  `ScriptWord` indices, but some visible symbols are intentionally unspeakable.
  Alignment and locale detection must skip empty-normalized symbols without
  deleting them from the rendered script.

---

## Shared-File Ownership Notes

Styling Engine owns style mutation and rendering sections in
`script_editor_screen.dart` and `markup_controller.dart`. Selection owns target
ranges; History owns save timing; File I/O owns external document conversion.
