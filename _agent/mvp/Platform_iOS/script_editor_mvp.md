---
name: Script Editor MVP
type: component
platform: iOS
last_updated: 2026-04-29
---

# Script Editor MVP - iOS

Governs iOS editor orchestration: active script state, block controllers,
gallery/editor handoff, save/import flow, and coordination with History,
Selection, Styling, File I/O, Settings, and Editor Suites.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/script_editor_screen.dart` | Editor shell, block lifecycle, controller wiring, save/import orchestration |
| `Platform_iOS/lib/features/script/widgets/script_gallery_screen.dart` | Recent scripts, open/delete/rename, restore metadata |
| `Platform_iOS/lib/features/script/widgets/teleprompt_selector_sheet.dart` | File/source selector and recent source preferences |
| `Platform_iOS/lib/features/script/providers/script_provider.dart` | `ScriptNotifier`, active `Script`, `loadText`, `importFile`, `parseFile`, `clear` |
| `Platform_iOS/lib/features/script/models/script.dart` | Script text, title, source/session/history/style metadata |
| `Platform_iOS/lib/features/script/models/script_word.dart` | Word token consumed by STT alignment and teleprompter rendering |
| `Platform_iOS/lib/features/script/models/editor_state.dart` | Editor history snapshot model |
| `Platform_iOS/lib/features/script/models/cursor_style.dart` | `cursorStyleProvider` bridge for suite state |
| `Platform_iOS/lib/features/script/widgets/editor/editor_dialogs.dart` | Rename/save/import dialogs |
| `Platform_iOS/lib/features/script/widgets/editor/lobby_settings_panel.dart` | Lobby/editor settings UI |

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
3. Style metadata (`fontSize`, `fontFamily`, spacing, alignment, colors) and
   history metadata (`sessionId`, `historyJson`, `historyIndex`) travel through
   all open/save/import paths.
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

---

## Windows v4.1.12 Final Migration Target

When iOS editor work resumes, port these verified Windows editor contracts:

- Editor search must match visible text and then map back to raw markup offsets.
- Bookmarks must display visible markers, support add/remove/previous/next, and
  sync with present mode.
- Font-size controls must read and write the same metadata value used by present
  mode; editor visual scale must not create a second saved font number.
- Intentional blank lines, quotes, punctuation, and standalone symbols must be
  preserved while editing and when handing off to present mode.
