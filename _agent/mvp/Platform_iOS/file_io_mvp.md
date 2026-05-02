---
name: File I/O MVP
type: component
platform: iOS
last_updated: 2026-05-02
---

# File I/O MVP - iOS

Governs iOS import/export parsing and generation for DOCX, RTF, Pages, plain
text, and platform file-format lists.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/platform/file_import/platform_file_import.dart` | Supported extension list and formats label; includes Apple Pages on iOS |
| `Platform_iOS/lib/features/script/providers/script_provider.dart` | `importFile`, `parseFile`, `_parseDocx`, `_parseRtf`, `_parsePages`, style extraction |
| `Platform_iOS/lib/features/script/services/docx_service.dart` | DOCX export generation |
| `Platform_iOS/lib/features/script/services/rtf_service.dart` | RTF export generation |
| `Platform_iOS/lib/features/script/services/pages_service.dart` | Apple Pages export generation |
| `Platform_iOS/lib/features/script/services/markup_export_service.dart` | Shared internal-markup export parser for rich/plain output |
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | Save/export/import UI orchestration |
| `Platform_iOS/lib/features/script/widgets/teleprompt_selector_sheet.dart` | Importable extension list and source selection |

## External API

| Method / Field | Caller |
|----------------|--------|
| `PlatformFileImport.supportedExtensions` | File picker/import validation |
| `PlatformFileImport.formatsLabel` | Unsupported-format dialogs |
| `ScriptNotifier.importFile(File)` | Gallery/editor import actions |
| `ScriptNotifier.parseFile(File)` | Import preview/error handling |
| `DocxService.buildDocx(...)` | Export/save path |
| `RtfService.buildRtf(...)` | Export/save path |
| `PagesService.buildPages(...)` | iOS Pages export path |
| `MarkupExportService.parse(String)` | DOCX/RTF/Pages export services |
| `MarkupExportService.toPlainText(String)` | Plain/Pages export paths |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Script editor | `script_editor_screen.dart` | Save/export/import commands |
| Script provider | `script_provider.dart` | Parses imported bytes and extracts metadata |
| Teleprompt selector | `teleprompt_selector_sheet.dart` | Lists allowed formats |
| Settings provider | `settings_provider.dart` | Persists recent script metadata |
| Styling Engine | Styling services | Converts hidden markup for export |

## Invariants

1. iOS supports standard formats plus `.pages`.
2. Import must preserve raw text and style metadata where parsers can extract it.
3. Export must decide explicitly whether to preserve or strip internal markup.
4. `sourceType`, `sessionId`, `historyIndex`, and `style` metadata must survive
   save/open flows.
5. Unsupported-format messages must match `PlatformFileImport.formatsLabel`.

## Forbidden Changes

- Do not remove `.pages` support from iOS without documenting product impact.
- Do not parse binary office formats with ad hoc string splitting when service
  parsers exist.
- Do not save exported visible text back over internal raw markup accidentally.
- Do not drop history/style metadata during save/import.

## Known Fragilities

- DOCX/Pages are ZIP-based and can be memory-heavy.
- RTF parsing has escape/control-word edge cases.
- `.doc` is treated through text/RTF fallback behavior, not full binary Word parsing.
- Exported Pages format is minimal and intended for round-trip compatibility.

## Shared-File Ownership Notes

File I/O owns parsing/generation and import/export UI paths; Script Editor owns
active controller orchestration; Settings owns persistence of recent entries.

---

## Windows v4.1.12 Final Migration Target

When iOS import/export work resumes, port the verified Windows export hygiene
contract in iOS-native terms:

- RTF/DOCX/Pages rich exports must convert app-private markup into document
  styling.
- Plain formats must export visible text only.
- Raw `[color]`, `[size]`, bold, alignment, highlight, and display-only tags
  must not spill into saved files.
- Default teleprompter display colors must not become unreadable body text in
  exported documents.
- Intentional blank lines, quotes, punctuation, and standalone symbols must
  survive import/export round trips.

---

## iOS Loaded-File Preservation Port - 2026-05-02

- Loaded/imported file content must not be normalized with generic
  `trim()`/newline-collapse cleanup.
- Non-RTF `.rtf`, legacy `.doc`, DOCX extraction, Pages extraction, and RTF
  parsing must preserve intentional leading/trailing text, multiple blank
  lines, quotes, standalone punctuation, and symbols.
- Parsers may strip unsupported binary/control metadata, but visible text
  structure from the loaded file must survive into `Script.rawText`.
- Editor save/recent serialization must not trim the joined block text after a
  file has been loaded.

---

## iOS Markup-Safe Export Port - 2026-05-02

- `markup_export_service.dart` is the shared export parser for app-private
  markup.
- DOCX and RTF export must convert internal tags (`[color]`, `[size]`, `[font]`,
  `**`, underline, italic, alignment, and shorthand color tags) into document
  styling controls.
- Pages export must write visible text only. It must not leak raw app-private
  bracket tags into `index.xml`.
- Default teleprompter white (`#FFFFFF`) is display metadata and must not be
  written as white body text in normal exported documents.
- Export services must preserve visible text, symbols, punctuation, and blank
  paragraph structure while keeping internal markup out of user-facing files.
