---
name: File I/O MVP
type: component
platform: macOS
last_updated: 2026-04-27
---

# File I/O MVP - macOS

Governs macOS import/export parsing and generation for DOCX, RTF, Pages, plain
text, and platform file-format lists.

## Owned Files

| File | Role |
|------|------|
| `Platform_macOS/lib/platform/file_import/platform_file_import.dart` | Supported extension list and formats label; includes Apple Pages on macOS |
| `Platform_macOS/lib/features/script/providers/script_provider.dart` | `importFile`, `parseFile`, `_parseDocx`, `_parseRtf`, `_parsePages`, style extraction |
| `Platform_macOS/lib/features/script/services/docx_service.dart` | DOCX export generation |
| `Platform_macOS/lib/features/script/services/rtf_service.dart` | RTF export generation |
| `Platform_macOS/lib/features/script/services/pages_service.dart` | Apple Pages export generation |
| `Platform_macOS/lib/features/script/widgets/script_editor_screen.dart` | Save/export/import UI orchestration |
| `Platform_macOS/lib/features/script/widgets/teleprompt_selector_sheet.dart` | Importable extension list and source selection |

## External API

| Method / Field | Caller |
|----------------|--------|
| `PlatformFileImport.supportedExtensions` | File picker/import validation |
| `PlatformFileImport.formatsLabel` | Unsupported-format dialogs |
| `ScriptNotifier.importFile(File)` | Gallery/editor import actions |
| `ScriptNotifier.parseFile(File)` | Import preview/error handling |
| `DocxService.buildDocx(...)` | Export/save path |
| `RtfService.buildRtf(...)` | Export/save path |
| `PagesService.buildPages(...)` | macOS Pages export path |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Script editor | `script_editor_screen.dart` | Save/export/import commands |
| Script provider | `script_provider.dart` | Parses imported bytes and extracts metadata |
| Teleprompt selector | `teleprompt_selector_sheet.dart` | Lists allowed formats |
| Settings provider | `settings_provider.dart` | Persists recent script metadata |
| Styling Engine | Styling services | Converts hidden markup for export |

## Invariants

1. macOS supports standard formats plus `.pages`.
2. Import must preserve raw text and style metadata where parsers can extract it.
3. Export must decide explicitly whether to preserve or strip internal markup.
4. `sourceType`, `sessionId`, `historyIndex`, and `style` metadata must survive.
5. Unsupported-format messages must match `PlatformFileImport.formatsLabel`.

## Forbidden Changes

- Do not remove `.pages` support from macOS without documenting product impact.
- Do not parse binary office formats with ad hoc string splitting when parsers exist.
- Do not save exported visible text back over internal raw markup accidentally.
- Do not drop history/style metadata during save/import.

## Known Fragilities

- DOCX/Pages are ZIP-based and can be memory-heavy.
- RTF parsing has escape/control-word edge cases.
- `.doc` is treated through text/RTF fallback behavior, not full binary Word parsing.
- Exported Pages format is minimal and intended for round-trip compatibility.

## Shared-File Ownership Notes

File I/O owns parsing/generation and save/import UI paths; Script Editor owns
active controller orchestration; Settings owns persistence of recent entries.

## 2026-05-05 Windows v4.1.14 Transfer Pending

Windows commit `da99e17` fixed DOCX import loss by translating Word underline,
italic, `w:br`/`w:cr`, tabs, empty paragraphs, explicit alignment, and RTL/bidi
paragraph hints into the app's internal markup/newline model. macOS should port
that import behavior into
`Platform_macOS/lib/features/script/providers/script_provider.dart` before the
next macOS QA pass.

The source plan and QA checklist live in
`_agent/mvp/Platform_macOS/windows_v4_1_14_transfer_packet.md`.

## 2026-05-05 Windows v4.1.14 DOCX Port Implemented

macOS now imports DOCX with the Windows v4.1.14 preservation contract:

- underline, italic, meaningful text color, and Word highlight/shading map into
  internal markup;
- `w:br`, `w:cr`, tabs, empty paragraphs, and final blank rows are preserved;
- paragraph `w:bidi`/alignment hints map to app alignment tags;
- dark default text is normalized away instead of turning imported text gray;
- imported text is `trimRight()` only so intentional internal spacing remains.

Pages import/export stays macOS-native and unchanged.
