---
name: Script Editor MVP
type: component
platform: Windows
last_updated: 2026-04-29
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
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.load_blocks.dart` | Extracted load, controller/block lifecycle, bookmark loading, cursor/style detection, and dispose-adjacent helpers |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.dialogs_history.dart` | Extracted rename dialog, refined text, clear-style helpers, history and state-restore logic |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.styling_commands.dart` | Extracted style, inline style, alignment, direction, font, color, and selection restore commands |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.file_present.dart` | Extracted import, save, clear, and present-mode handoff methods |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.debug_bookmarks_search.dart` | Extracted debug sentry, editor bookmarks, copy, search, select-all, and global selection resync |
| `Platform_Windows/lib/features/script/widgets/script_editor_screen.editor_block.dart` | Extracted `_EditorBlock` widget |
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
| `ScriptNotifier.updateStyleMetadata(...)` | Presenter/editor style sync without replacing script text |
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

3a. **Editor font size is the metadata value**: The editor text field, font
    suite, script metadata, settings provider, and file export must all use the
    same saved font-size number. The font suite reads `settingsProvider.fontSize`
    and `Script.fontSize`, not the cursor-detected `[size=...]` inline value.
    Presentation-only enlargement belongs to the Teleprompter Engine MVP, not
    the editor.

4. **Style metadata may update without text replacement**:
   `ScriptNotifier.updateStyleMetadata(...)` may change active script style
   fields and persistence metadata, but it must not rebuild words, replace
   `rawText`, reset `sessionId`, or clear history.

5. **Editor block lifecycle is centralized**: Controller creation, listener
   attachment, focus tracking, and disposal stay in `script_editor_screen.dart`.
   Do not create block controllers in suite widgets.

6. **Selection changes are silent**: Cursor/selection motion updates
   `cursorStyleProvider` but must not create history entries by itself.

7. **Import and save route through File I/O rules**: File extension decisions,
   DOCX/RTF/Pages generation, and platform format lists belong to File I/O MVP.

8. **Gallery re-entry must preserve history**: When opening a recent script,
   gallery/provider code must pass both `historyJson` and `historyIndex` to the
   editor load path.

9. **Settings updates are not editor rewrites**: Settings provider changes may
   update presentation defaults, but they must not rebuild controllers or discard
   raw editor text.

10. **Import parsing preserves intentional blank-line depth**: Script import
   paths must not collapse `\n\n\n` or larger newline runs before the script
   reaches editor/presentation state. Trimming outer file noise is allowed, but
   internal chapter/section spacing must be retained.

11. **Editor serialization preserves blank edges**: `_getRefinedFullText()` must
   join editor blocks without `trim()`. Leading, trailing, and repeated empty
   lines are script content, not cleanup noise.

12. **Editor search is keyboard-accessible**: `Ctrl+Shift+F` must open the editor
   search dialog from both the editor-level shortcut layer and individual block
   shortcut layers.

13. **Editor search preserves document structure**: Search may focus the matching
    block, select the matched raw-text range, and scroll the block into view, but
    it must not rewrite controller text, strip markup, create history entries, or
    change script metadata.

14. **Editor search wraps predictably**: Search starts after the current active
    selection/cursor, proceeds through later blocks, then wraps to the beginning
    through the original start point.

15. **Editor search is visible-text based**: Search must match the text the user
    can see, not hidden markup tags. After a visible match is found, it must
    translate the visual offset back to raw `MarkupController` offsets before
    setting selection.

16. **Default-relative spacing display**: Editor layout controls may store the
    real line-spacing value (`1.2` by default), but the visible value must show
    the user offset from default, so default reads `0.0`.

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
- Do not halve or double saved font-size metadata to compensate for presentation
  readability.
- Do not let cursor/inline `[size=...]` detection become the editor font-size
  dropdown authority. Changing the editor font-size control must update
  `settingsProvider.fontSize` and `ScriptNotifier.updateStyleMetadata(...)`.
- Do not add `Platform.isWindows` branching inside editor feature code unless the
  platform helper layer cannot represent the behavior.
- Do not implement editor search by flattening all controller text and rewriting
  blocks. Block boundaries and raw markup offsets must remain intact.
- Do not make `Ctrl+Shift+F` presentation-only. The editor owns its own search
  shortcut contract.
- Do not collapse internal multi-newline runs during import or provider parsing;
  they may mark scene/chapter breaks for presentation.
- Do not calculate editor search jumps from raw markup offsets alone; invisible
  tags must not push the selection or scroll target away from the visible match.

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
| Visible text mapping | Search matches tag-stripped visible text, then maps visual offsets back to raw controller offsets for selection. |
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
last_updated: 2026-04-28
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
---

## Windows v4.1.12 Final Seal Notes

- Editor search must search visible text and map matches back to raw markup
  offsets only after the visible match is known.
- Editor bookmark markers are UI markers only; they must never be inserted into
  script text.
- Editor bookmarks must share the same script/session scope as present mode so
  anchors created in either mode appear in both modes.
- Bookmark deletion must be possible from the visible marker and from an
  explicit remove button.
- Editor font-size controls must read/write the same script metadata value used
  by present mode, not a cursor-local fallback such as `18.0`.
- Intentional empty blocks and repeated blank lines are valid script structure
  and must not be trimmed by editor save/refresh paths.

---

## V5 File Split Contract

The sealed Windows script editor screen was split into Dart `part` files on
2026-04-29 for surgical V5 development. This was a behavior-preserving move:
logic was moved into the same library so private state access remains identical.

Line-count ceiling after split:

| File | Lines |
|------|------:|
| `script_editor_screen.dart` | 608 |
| `script_editor_screen.load_blocks.dart` | 609 |
| `script_editor_screen.debug_bookmarks_search.dart` | 541 |
| `script_editor_screen.styling_commands.dart` | 457 |
| `script_editor_screen.dialogs_history.dart` | 439 |
| `script_editor_screen.editor_block.dart` | 231 |
| `script_editor_screen.file_present.dart` | 198 |

Do not recombine these files. Future changes must edit the smallest owning part
file and the matching MVP docs.

---

## 2026-05-03 V5 Editor Stabilization Addendum

- The editor shell owns keyboard navigation across paragraph blocks. Empty
  blocks are real script structure and must be visited one-by-one by left/right
  arrows.
- The editor shell may clear app-owned selection on arrow movement, but must
  not change the working up/down navigation behavior unless testing proves a
  regression.
- `script_editor_screen.bookmarks.dart` owns text-flow bookmark sign
  normalization, bookmark metadata rebuild, and bookmark history ordering.
- `global_selection_overlay.dart` owns handle geometry, active handle drag
  state, endpoint normalization for visual highlights, and handle autoscroll
  lifetime.

## 2026-05-03 V5 Follow-Up: One Arrow Owner + Debug Sentry

- Windows editor arrow keys are owned by the global `HardwareKeyboard` route.
  The surrounding Focus widget is structural only and must return ignored for
  arrows to prevent duplicate movement.
- Empty blocks are not layout noise. Keyboard navigation must stop on each
  empty block before moving to the next block.
- Debug mode may show endpoint A, endpoint B, active endpoint, normalized
  selection range, and last arrow decision so device QA screenshots expose
  the internal selection state.

## 2026-05-03 V5 Follow-Up: Modified Arrow Fallback

- Plain arrow keys may use the Windows editor block-navigation route.
- Ctrl, Shift, Alt, and Meta arrow combinations must fall back to the native
  `EditableText` shortcut behavior unless an app-owned selection is currently
  active and must be cleared first.
- This preserves system/editor shortcut semantics such as Ctrl+Up/Down and
  Shift-based selection while keeping app-owned overlay deselection explicit.

## 2026-05-03 V5 Correction: Ctrl+Up/Down Are Block-Aware

- Ctrl+Up/Down cannot be left entirely to native `EditableText`, because each
  script paragraph is a separate field and native movement stalls at the field
  boundary.
- Windows editor owns Ctrl+Up/Down for paragraph/block traversal while leaving
  unrelated modified arrows native.
- Repeated Ctrl+Up/Down must cross one block at a time after reaching the
  current block boundary. Ctrl+Shift+Up/Down may extend into the overlay when
  the selection crosses block boundaries.

## 2026-05-03 V5 Correction: Boundary Arrows And Safe Autoscroll

- The editor page listener forwards active handle pointer movement back into
  `GlobalSelectionOverlay`, so edge autoscroll can stop as soon as the pointer
  returns to the safe center zone.
- Modified arrows are block-aware only at the point where native `EditableText`
  cannot cross to another paragraph field. This preserves normal in-field text
  editing while preventing stalls at block boundaries.
- Shift+arrow extension over an existing overlay selection must preserve the
  anchor edge and move only the focus edge. This is required for selecting
  multiple paragraphs with repeated Ctrl+Shift+Up/Down or Shift+arrows.
- Plain right/left can be routed through raw/visible offset mapping to avoid
  focus-transfer stalls after entering a new text block.

## 2026-05-03 V5 State-Machine Integration

- The editor screen reads `SelectionSessionSnapshot` from
  `GlobalSelectionOverlay` when extending an existing app-owned selection.
  Anchor/focus, not normalized document order, decide whether a modified-arrow
  press extends, shrinks, or collapses the range.
- The screen-level `HardwareKeyboard` route remains the only arrow owner. The
  structural Focus wrapper must continue returning ignored so one physical key
  cannot be processed by both the app route and native focus shell.
- Native `EditableText` still owns safe in-block editing. The app route takes
  over only for full/global selection clearing, existing app-owned selection
  extension, shortcut commands over app selection, and block-boundary movement
  that native fields cannot perform.
- The editor body is wrapped with a mouse-exit guard so hard handle exits stop
  the overlay gesture. After such an exit, body-drag promotion is suppressed
  until pointer-up/clear, preserving the selection while allowing the next
  normal click to deselect.
- Empty paragraph blocks remain valid stops for every app-owned cross-block
  navigation path.
