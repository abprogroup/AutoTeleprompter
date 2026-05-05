---
name: Script Editor MVP
type: component
platform: macOS
last_updated: 2026-04-27
---

# Script Editor MVP - macOS

Governs macOS editor orchestration: active script state, block controllers,
gallery/editor handoff, save/import flow, and coordination with History,
Selection, Styling, File I/O, Settings, and Editor Suites.

## Owned Files

| File | Role |
|------|------|
| `Platform_macOS/lib/features/script/widgets/script_editor_screen.dart` | Editor shell, block lifecycle, controller wiring, save/import orchestration |
| `Platform_macOS/lib/features/script/widgets/script_gallery_screen.dart` | Recent scripts, open/delete/rename, restore metadata |
| `Platform_macOS/lib/features/script/widgets/teleprompt_selector_sheet.dart` | File/source selector and recent source preferences |
| `Platform_macOS/lib/features/script/providers/script_provider.dart` | `ScriptNotifier`, active `Script`, `loadText`, `importFile`, `parseFile`, `clear` |
| `Platform_macOS/lib/features/script/models/script.dart` | Script text, title, source/session/history/style metadata |
| `Platform_macOS/lib/features/script/models/script_word.dart` | Word token consumed by STT alignment and teleprompter rendering |
| `Platform_macOS/lib/features/script/models/editor_state.dart` | Editor history snapshot model |
| `Platform_macOS/lib/features/script/models/cursor_style.dart` | `cursorStyleProvider` bridge for suite state |
| `Platform_macOS/lib/features/script/widgets/editor/editor_dialogs.dart` | Rename/save/import dialogs |
| `Platform_macOS/lib/features/script/widgets/editor/lobby_settings_panel.dart` | Lobby/editor settings UI |

## External API

| Method / Field | Caller |
|----------------|--------|
| `scriptProvider` | Gallery, editor, teleprompter |
| `ScriptNotifier.loadText(...)` | New/open/import flows |
| `ScriptNotifier.importFile(File)` | File import entry points |
| `ScriptNotifier.parseFile(File)` | Import preview/error handling |
| `ScriptNotifier.clear()` | New/clear flows |
| `Script.rawText` | Rendering, save/export, markup transforms |
| `Script.words` | STT aligner and teleprompter |
| `Script.historyJson` / `historyIndex` | History restore/persistence |
| `cursorStyleProvider` | Editor suites and selection/style updates |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Teleprompter screen | `teleprompter_screen.dart` | Reads active script and style metadata |
| Teleprompter provider | `teleprompter_provider.dart` | Consumes `Script.words` for session advancement |
| Word aligner | `word_aligner.dart` | Consumes script words and normalized text |
| Settings provider | `settings_provider.dart` | Persists recent script and style/history metadata |
| Editor suites | `*_suite_mvp.dart` | Receive callbacks from editor screen |
| File I/O services | `docx_service.dart`, `rtf_service.dart`, `pages_service.dart` | Generate export bytes from markup |

## Invariants

1. `Script.rawText` and `MarkupController.text` preserve internal markup tags.
2. `Script.words` must be derived from the same text loaded into `rawText`.
3. Style and history metadata travel through all open/save/import paths.
4. Controller creation, listener attachment, focus tracking, and disposal stay
   centralized in the editor screen.
5. Editor orchestration must not own STT.

## Forbidden Changes

- Do not strip markup from raw editor text as a generic cleanup.
- Do not bypass `ScriptNotifier.loadText()` for active-script replacement.
- Do not remove history metadata from recent-script JSON.
- Do not create history entries for cursor movement or selection-only changes.

## Known Fragilities

- `script_editor_screen.dart` is a large shared file with many MVP owners.
- Programmatic controller changes can trigger listener loops.
- Visible selection offsets diverge from raw markup offsets.
- Recent metadata, provider state, and editor local history can race.

## Shared-File Ownership Notes

History, Selection, Styling Engine, Editor Suites, and File I/O own sections
inside the editor screen; read those MVPs before editing their sections.

## 2026-05-04 Windows 385911e Parity Port

The macOS editor has been split to match the surgical ownership pattern used
by iOS/Windows. Runtime ownership is now divided across:

- `script_editor_screen.dart`: shell, state fields, lifecycle, provider setup,
  keyboard handler registration, and build delegation.
- `script_editor_screen.build.dart`: visual editor scaffold and suite wiring.
- `script_editor_screen.keyboard.dart`: global shortcut routing and
  app-selection extension entry points.
- `script_editor_screen.keyboard_navigation.dart`: block-aware arrow target
  math, empty-row traversal, bookmark-aware navigation targets.
- `script_editor_screen.load_blocks.dart`: controller creation/listeners,
  autosave, recent-script updates, body-drag promotion.
- `script_editor_screen.bookmarks.dart`: text-flow bookmark sign metadata
  reconciliation.
- `script_editor_screen.search.dart`: editor search toolbar and whole-word
  matching.
- `script_editor_screen.dialogs_history.dart`,
  `script_editor_screen.file_present.dart`, and
  `script_editor_screen.styling_commands.dart`: their named domains.

Keep touched Dart files under 800 lines where practical. Lifecycle overrides
that Dart requires on the `State` class (`build`, `dispose`) remain in the
root file and delegate into parts.

Ported behavior from Windows includes app-owned selection command routing,
stable Shift/handle/body-drag interoperability, editor search toolbar parity,
text-flow `\u00BB` bookmark signs, rich clipboard guard, bookmark-safe
history, and presenter resume/search/bookmark parity. Windows WebView2 STT,
Windows mic selectors, `setx`, and Windows speech-pack dialogs are explicitly
excluded from macOS.
## 2026-05-05 Windows v4.1.14 Editor DOCX Rendering Port

macOS editor rendering now uses the Windows shared markup-decoration service
for imported `[u]` and `[bg=#...]` ranges. Hidden markup tags are excluded from
the visible bidi layout, then continuous underline/highlight geometry is painted
around the `TextField`. Normal text styling, selection, history, clipboard, and
bookmark ownership remain unchanged.
