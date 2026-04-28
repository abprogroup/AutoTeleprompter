---
name: Script Editor MVP
type: component
platform: Windows
last_updated: 2026-04-28
---

# Script Editor MVP - Windows

Governs the Windows script-editing surface: block controller orchestration,
gallery/editor handoff, script provider state, editor load/save flows, and the
coordination points that connect selection, styling, history, file I/O, and
settings.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | Editor orchestration, block lifecycle, editor actions, suite wiring, load/save/import coordination |
| `Platform_Windows/lib/features/script/widgets/script_gallery_screen.dart` | Recent-script gallery, script open/delete/rename entry points, history metadata handoff |
| `Platform_Windows/lib/features/script/widgets/teleprompt_selector_sheet.dart` | Script source selection UI |
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | `ScriptNotifier`, active `Script`, `loadText`, `importFile`, `parseFile`, `clear` |
| `Platform_Windows/lib/features/script/models/script.dart` | `Script` model and style/history metadata contract |
| `Platform_Windows/lib/features/script/models/script_word.dart` | Token model consumed by teleprompter and aligner |
| `Platform_Windows/lib/features/script/models/editor_state.dart` | History snapshot model owned jointly with History MVP |
| `Platform_Windows/lib/features/script/models/cursor_style.dart` | `cursorStyleProvider` bridge for editor suite state |
| `Platform_Windows/lib/features/script/widgets/editor/lobby_settings_panel.dart` | Lobby/editor settings surface |
| `Platform_Windows/lib/features/script/widgets/editor/editor_dialogs.dart` | Editor dialogs for rename/save/import support |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `scriptProvider` | Gallery, editor, teleprompter screen |
| `ScriptNotifier.loadText(...)` | Gallery open, editor import, new-script flows |
| `ScriptNotifier.importFile(File)` | File import entry points |
| `ScriptNotifier.parseFile(File)` | Import preview/error handling |
| `ScriptNotifier.clear()` | Clear/new script flows |
| `Script.rawText` | Teleprompter rendering and save/export paths |
| `Script.words` | `teleprompter_provider.dart`, `word_aligner.dart`, teleprompter UI |
| `Script.historyJson` / `historyIndex` | History restore and recent metadata |
| `cursorStyleProvider` | Editor suites and `_onSelectionChanged()` |
| `_showSearchDialog()` / `_findInEditor(String query)` | Editor `Ctrl+Shift+F` search, wraparound match, focus, and selection |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Teleprompter screen | `teleprompter_screen.dart` | Reads active `Script`, `rawText`, `words`, style metadata |
| Teleprompter provider | `teleprompter_provider.dart` | Consumes `Script.words` for session start and advancement |
| Word aligner | `word_aligner.dart` | Consumes `ScriptWord` data and normalized text |
| Settings provider | `settings_provider.dart` | Persists `lastScript`, recent metadata, style metadata |
| Editor suites | `formatting_toolbar_mvp.dart` and suite files | Receive callbacks from `script_editor_screen.dart` |
| File I/O services | `docx_service.dart`, `rtf_service.dart`, `pages_service.dart` | Generate bytes from editor markup during save/export |

---

## Preserved Style Metadata Keys

These keys were already documented by the earlier Windows MVP file and remain
part of the Script model/import contract:

| Property | Type | Use Case |
|----------|------|----------|
| `fontSize` | Double | Visual scale |
| `fontFamily` | String | Typeface |
| `lineSpacing` | Double | Gap layout |
| `letterSpacing` | Double | Character bounds |
| `wordSpacing` | Double | Word distances |
| `textAlign` | String | Block alignments |
| `scriptBgColor` | Int | Hex backgrounds |

---

## Invariants

1. **Raw text remains markup-bearing**: `Script.rawText` and
   `MarkupController.text` store internal markup tags. Rendering hides tags;
   persistence and exports must explicitly decide whether to preserve or strip
   them.

2. **Words derive from current raw text**: `ScriptNotifier._createScript()` must
   tokenize the same text that is loaded into `Script.rawText`, preserving word
   indices used by STT alignment.

3. **Script metadata travels with the script**: `fontSize`, `fontFamily`,
   spacing, alignment, colors, `sessionId`, `historyJson`, and `historyIndex`
   must be passed through load/save/open paths.

4. **Editor block lifecycle is centralized**: Controller creation, listener
   attachment, focus tracking, and disposal stay in `script_editor_screen.dart`.
   Do not create block controllers in suite widgets.

5. **Selection changes are silent**: Cursor/selection motion updates
   `cursorStyleProvider` but must not create history entries by itself.

6. **Import and save route through File I/O rules**: File extension decisions,
   DOCX/RTF/Pages generation, and platform format lists belong to File I/O MVP.

7. **Gallery re-entry must preserve history**: When opening a recent script,
   gallery/provider code must pass both `historyJson` and `historyIndex` to the
   editor load path.

8. **Settings updates are not editor rewrites**: Settings provider changes may
   update presentation defaults, but they must not rebuild controllers or discard
   raw editor text.

9. **Import parsing preserves intentional blank-line depth**: Script import
   paths must not collapse `\n\n\n` or larger newline runs before the script
   reaches editor/presentation state. Trimming outer file noise is allowed, but
   internal chapter/section spacing must be retained.

10. **Editor search is keyboard-accessible**: `Ctrl+Shift+F` must open the editor
   search dialog from both the editor-level shortcut layer and individual block
   shortcut layers.

11. **Editor search preserves document structure**: Search may focus the matching
    block, select the matched raw-text range, and scroll the block into view, but
    it must not rewrite controller text, strip markup, create history entries, or
    change script metadata.

12. **Editor search wraps predictably**: Search starts after the current active
    selection/cursor, proceeds through later blocks, then wraps to the beginning
    through the original start point.

---

## Forbidden Changes

- Do not move STT logic into the script editor. The editor does not own speech
  recognition.
- Do not strip markup from `Script.rawText` or controller text as a generic
  cleanup step.
- Do not create history entries for cursor movement, selection changes, or suite
  focus changes.
- Do not bypass `ScriptNotifier.loadText()` for active script replacement.
- Do not remove history metadata from recent-script JSON.
- Do not add `Platform.isWindows` branching inside editor feature code unless the
  platform helper layer cannot represent the behavior.
- Do not implement editor search by flattening all controller text and rewriting
  blocks. Block boundaries and raw markup offsets must remain intact.
- Do not make `Ctrl+Shift+F` presentation-only. The editor owns its own search
  shortcut contract.
- Do not collapse internal multi-newline runs during import or provider parsing;
  they may mark scene/chapter breaks for presentation.

---

## Known Fragilities

- **Large shared file**: `script_editor_screen.dart` contains editor, history,
  selection, styling, save/import, and suite orchestration. Read every affected
  MVP before editing a section.
- **Controller listener loops**: Programmatic text/selection changes can trigger
  `_onBlockChanged()` and `_onSelectionChanged()`. Guard flags must be preserved.
- **History re-entry race**: Recent metadata, provider state, and editor local
  history must agree on `historyIndex`.
- **Markup/raw offset mismatch**: Visible selection positions and raw markup
  offsets diverge because tags render invisible.
- **Search selection is raw-text based**: The current editor search selects the
  matched raw controller range. If the query matches text adjacent to invisible
  markup tags, visual selection may not perfectly reflect perceived plain text.

---

## Recent Windows Contracts Added 2026-04-28

| Feature | Contract |
|---------|----------|
| Editor search shortcut | `Ctrl+Shift+F` opens the search dialog in script editor mode. |
| Match behavior | Search starts after the active selection/cursor, wraps through the document, focuses the matching block, selects the match, and scrolls it into view. |
| Ownership boundary | Editor search owns block focus/selection only. Present-mode search and resume-point jumps belong to Teleprompter Engine MVP. |

---

## Shared-File Ownership Notes

`script_editor_screen.dart` is section-owned by Script Editor, History,
Selection, Styling Engine, Editor Suites, and File I/O MVPs. This MVP owns the
orchestration and load/save shell, not the detailed invariants of every section.

---

## Preserved Original Contract Rows

The following rows and notes existed in the prior Windows Script Editor MVP and
remain preserved so hardening is additive, not destructive.

Legacy exact title marker: `# Script Editor MVP â€” Windows`

Prior scope statement: Governs the underlying tokenization pipeline, the robust
multi-extension parser (`.docx`, `.pages`, `.rtf`, `.doc`), formatting mappings,
and persistent local script state transitions.

| Original Owned File Row | Preserved Role |
|-------------------------|----------------|
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | The engine core: manages CRUD pipelines via `loadText`, `importFile`, `parseFile`, and deep string parsers. |
| `Platform_Windows/lib/features/script/models/script.dart` | Immutable model containing metadata (`sourceType`, `sessionId`, `historyIndex`, rich text attributes). |
| `Platform_Windows/lib/features/script/models/script_word.dart` | The smallest unit of measurement for voice alignment. |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | Deep editor experience with style mapping bindings. |
| `Platform_Windows/lib/features/script/widgets/script_gallery_screen.dart` | Visual folder views. |

| Original API Row | Preserved Where Called |
|------------------|------------------------|
| `loadText(String text, ...)` | Global load paths |
| `clear()` | Clearing memory |
| `importFile(File file)` | File system imports |
| `parseFile(File file)` | Parsing boundaries |

| Original Caller Row | Preserved What It Calls |
|---------------------|-------------------------|
| Teleprompter UI / `teleprompter_screen.dart` | Reads active text parameters |
| Audio Aligner / `word_aligner.dart` | Maps indices |

## Style Metadata Keys

| Property | Type | Use Case |
|----------|------|----------|
| `fontSize` | Double | Visual scale |
| `fontFamily` | String | Typeface |
| `lineSpacing` | Double | Gap layout |
| `letterSpacing` | Double | Character bounds |
| `wordSpacing` | Double | Word distances |
| `textAlign` | String | Block alignments |
| `scriptBgColor` | Int | Hex backgrounds |

1. **State Isolation**: Modifying styling states must never break raw text bounds.

- Never dump active parsers.
- **Heavy XML bounds**: Parsing large formats can consume main isolate memory loops. Use carefully.

```markdown
---
name: Script Editor MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Script Editor MVP â€” Windows

Governs the underlying tokenization pipeline, the robust multi-extension parser (`.docx`, `.pages`, `.rtf`, `.doc`), formatting mappings, and persistent local script state transitions.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | The engine core: manages CRUD pipelines via `loadText`, `importFile`, `parseFile`, and deep string parsers. |
| `Platform_Windows/lib/features/script/models/script.dart` | Immutable model containing metadata (`sourceType`, `sessionId`, `historyIndex`, rich text attributes). |
| `Platform_Windows/lib/features/script/models/script_word.dart` | The smallest unit of measurement for voice alignment. |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart` | Deep editor experience with style mapping bindings. |
| `Platform_Windows/lib/features/script/widgets/script_gallery_screen.dart` | Visual folder views. |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `loadText(String text, ...)` | Global load paths |
| `clear()` | Clearing memory |
| `importFile(File file)` | File system imports |
| `parseFile(File file)` | Parsing boundaries |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Teleprompter UI | `teleprompter_screen.dart` | Reads active text parameters |
| Audio Aligner | `word_aligner.dart` | Maps indices |

## Style Metadata Keys

| Property | Type | Use Case |
|----------|------|----------|
| `fontSize` | Double | Visual scale |
| `fontFamily` | String | Typeface |
| `lineSpacing` | Double | Gap layout |
| `letterSpacing` | Double | Character bounds |
| `wordSpacing` | Double | Word distances |
| `textAlign` | String | Block alignments |
| `scriptBgColor` | Int | Hex backgrounds |

---

## Invariants

1. **State Isolation**: Modifying styling states must never break raw text bounds.

---

## Forbidden Changes

- Never dump active parsers.

---

## Known Fragilities

- **Heavy XML bounds**: Parsing large formats can consume main isolate memory loops. Use carefully.
```
