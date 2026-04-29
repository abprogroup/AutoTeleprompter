---
name: File I/O MVP
type: component
platform: Windows
last_updated: 2026-04-29
---

# File I/O MVP - Windows

Governs script import/export, supported file formats, document parsing,
document generation, save/import dialogs, platform-specific format lists, and
round-trip behavior for Windows.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | `parseFile`, `importFile`, DOCX/RTF/Pages/TXT/PDF/ODT parsing paths |
| `Platform_Windows/lib/features/script/services/markup_export_service.dart` | Shared export parser that converts internal editor markup into visible runs/paragraphs |
| `Platform_Windows/lib/features/script/services/docx_service.dart` | DOCX generation from internal markup |
| `Platform_Windows/lib/features/script/services/rtf_service.dart` | RTF generation with Unicode and color table handling |
| `Platform_Windows/lib/features/script/services/pages_service.dart` | Minimal Pages ZIP/XML generation from visible text |
| `Platform_Windows/lib/platform/file_import/platform_file_import.dart` | Windows supported extensions and display label |
| `Platform_Windows/lib/features/script/widgets/editor/editor_dialogs.dart` | Save/import/rename dialog helpers |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | `_runPendingFileLoad`, `_saveScript`, import/save action wiring |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.load_blocks.dart` | Extracted pending-file load and import parse handoff after V5 file split |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.file_present.dart` | Extracted import, save, clear, and present handoff after V5 file split |
| `Platform_Windows/lib/features/script/widgets/editor/suites/project_actions_mvp.dart` | Save/import buttons that enter File I/O flow |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `ScriptNotifier.parseFile(File)` | Import flows and preview/error handling |
| `ScriptNotifier.importFile(File)` | Editor/gallery import actions |
| `DocxService.generate(String)` | `_saveScript()` for `.docx` |
| `RtfService.generate(String)` | `_saveScript()` for `.rtf` |
| `PagesService.generate(String)` | Apple-format save path when enabled by platform |
| `MarkupExportService.parse(String)` | DOCX/RTF rich export serialization |
| `MarkupExportService.toPlainText(String)` | TXT/MD/Pages visible-text export serialization |
| `PlatformFileImport.supportedExtensions` | File picker validation |
| `PlatformFileImport.formatsLabel` | Unsupported-format error text |
| `_saveScript()` | Project action save button |
| `_runPendingFileLoad(File)` | Editor pending-file open path |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Project actions | `project_actions_mvp.dart` | Save/import callbacks |
| Editor screen | `script_editor_screen.dart` | Imports files and saves current script |
| Script provider | `script_provider.dart` | Parses bytes and loads script state |
| Settings provider | `settings_provider.dart` | Persists recent metadata and last import path |
| Platform file picker | `platform_file_import.dart` | Supplies allowed extensions |
| Teleprompter | `teleprompter_screen.dart` | Consumes imported script after provider load |

---

## Invariants

1. **Windows supported formats exclude Pages by default**: Windows
   `supportedExtensions` includes standard formats only; `.pages` is added only
   on iOS/macOS.

2. **Internal markup never leaks into exported documents**: DOCX/RTF generation
   must interpret bracket markup as real document styling. TXT/MD/Pages exports
   must write visible text only. Raw tags such as `[color=#ffffff]` must remain
   app metadata/editing syntax, not user-visible file content.

3. **Hebrew/Unicode must survive RTF**: RTF generation uses Unicode escapes for
   non-ASCII characters. Do not replace with ASCII filtering.

4. **DOCX is ZIP/XML**: DOCX saves must generate valid ZIP content with
   `[Content_Types].xml`, `_rels/.rels`, and `word/document.xml`.

5. **Import sets source metadata**: Imported scripts must carry title,
   `sourceType`, session/style metadata, and parsed content into `loadText()`.

6. **Background color can be parsed from document metadata**: DOCX parsing may
   call `setScriptBgColor`; preserve this side effect.

7. **Unsupported formats show platform label**: User-facing error text should use
   `PlatformFileImport.formatsLabel`.

8. **Teleprompter display white is not document text color**: Default white
   future-word/editor display color may be persisted in script metadata, but
   DOCX/RTF export must not force body text to white on normal white paper.

---

## Forbidden Changes

- Do not save `.docx` as plain UTF-8 bytes.
- Do not strip Hebrew or other non-ASCII characters during import/export.
- Do not add `.pages` to Windows supported extensions without explicit product
  approval.
- Do not write raw app-private markup tags into RTF, DOCX, TXT, MD, or Pages
  exports.
- Do not bypass `ScriptNotifier.loadText()` after parsing an imported file.
- Do not overwrite recent metadata when saving a file; preserve history/style
  fields.
- Do not serialize default teleprompter white as body text color in DOCX/RTF
  export.

---

## Known Fragilities

- **Heavy XML parsing**: Large DOCX/Pages/ODT files can consume main-isolate time.
- **PDF support limits**: If parser support is incomplete, file extension may be
  accepted before robust extraction exists.
- **Duplicate styling services**: Export helpers may import core or feature
  styling helpers; verify the intended one.
- **File path separators**: Windows paths use backslashes; title extraction must
  handle cross-platform paths carefully.

---

## Shared-File Ownership Notes

File I/O owns parse/generate/save/import sections. Script Editor owns the editor
orchestration that calls these paths. Settings owns metadata persistence after
save/import. Styling Engine owns the meaning of internal markup.
---

## Windows v4.1.12 Final Seal Notes

- RTF/DOCX export must translate app markup into document styling; raw
  app-private tags such as `[color]`, `[size]`, alignment tags, and bold syntax
  must not spill into saved documents.
- Plain text, markdown, and Pages-like plain paths must write visible text only.
- Default teleprompter white is display metadata and must not force white body
  text in normal exported documents.
- Import/export must preserve standalone symbols, quotes, punctuation, Hebrew,
  Unicode text, and intentional repeated blank lines.
- File I/O must not rewrite bookmark lists, history indices, or STT resume
  metadata as a side effect of export.

---

## V5 File Split Notes

Editor File I/O entry points now live primarily in
`script_editor_screen.file_present.dart` and pending-load parsing lives in
`script_editor_screen.load_blocks.dart`. File service behavior was not changed
by the split; future export/import edits must preserve markup-safe export and
blank-line/symbol preservation.
