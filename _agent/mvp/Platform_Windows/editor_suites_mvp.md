---
name: Editor Suites MVP
type: component
platform: Windows
last_updated: 2026-04-27
---

# Editor Suites MVP - Windows

Governs the Windows editor toolbar and all Dart widgets named `*_mvp.dart` under
the editor suites folder. These widgets are UI/control surfaces only; they call
callbacks owned by Script Editor, Styling Engine, History, Selection, Settings,
and File I/O MVPs.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/widgets/editor/suites/formatting_toolbar_mvp.dart` | Toolbar orchestrator, suite toggles, callback plumbing, active suite surface |
| `Platform_Windows/lib/features/script/widgets/editor/suites/text_suite_mvp.dart` | Bold/italic/underline, font size, font family controls |
| `Platform_Windows/lib/features/script/widgets/editor/suites/layout_suite_mvp.dart` | Alignment buttons and spacing sliders |
| `Platform_Windows/lib/features/script/widgets/editor/suites/color_suite_mvp.dart` | Text color, highlight color, script background controls |
| `Platform_Windows/lib/features/script/widgets/editor/suites/history_suite_mvp.dart` | Undo/redo buttons and history popup |
| `Platform_Windows/lib/features/script/widgets/editor/suites/project_actions_mvp.dart` | Back/delete/save/import/present/rename project action surface |
| `Platform_Windows/lib/features/script/widgets/editor/components/editor_primitives.dart` | Shared editor button, slider, popup primitives |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `FormattingToolbarMVP(...)` constructor callbacks | `script_editor_screen.dart` |
| `TextSuite.onBold/onItalic/onUnderline/onFontSize/onFontFamily` | `FormattingToolbarMVP` |
| `LayoutSuite.onAlign/onDirection/onInteraction` | `FormattingToolbarMVP` |
| `ColorSuite.onTextColor/onBgColor/onBgColorChange` | `FormattingToolbarMVP` |
| `HistorySuite.onUndo/onRedo/onHistorySelected` | `FormattingToolbarMVP` |
| `ProjectActionsSuite` callbacks | `script_editor_screen.dart` |
| `cursorStyleProvider` reads | Text/Layout/Color suites |
| `settingsProvider` reads/writes | Layout and Color suites |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Editor screen build | `script_editor_screen.dart` | Instantiates toolbar and project actions with callbacks |
| Text suite | `text_suite_mvp.dart` | Reads `cursorStyleProvider` and invokes style callbacks |
| Layout suite | `layout_suite_mvp.dart` | Reads `cursorStyleProvider`/settings and invokes align/spacing callbacks |
| Color suite | `color_suite_mvp.dart` | Reads `cursorStyleProvider`/settings, calls color callbacks |
| History suite | `history_suite_mvp.dart` | Displays `EditorState` list and calls history callbacks |
| Global color picker | `global_color_picker.dart` | Used by `ColorSuite` buttons |

---

## Invariants

1. **Suites are UI-only**: Suite widgets must not directly mutate controller
   text, history stacks, or provider script state. They call supplied callbacks.

2. **Cursor style is read-only inside suites**: Suites may read
   `cursorStyleProvider`; mutation belongs to editor selection/style detection.

3. **Text suite values snap safely**: Font size/family dropdowns must handle
   unknown detected values by snapping to allowed UI values.

4. **Layout interactions identify sections**: Spacing/alignment callbacks must
   report interaction labels so History can section suite commits.

5. **History UI reverses display without reordering data**: The popup may show
   latest first, but `historyIndex` values must still map to original list
   indices.

6. **Project actions keep premium buttons hidden**: Record and Settings buttons
   remain hidden in stable/core Windows unless explicitly restored.

7. **Toolbar remains compact**: The toolbar uses fit/scale behavior to avoid
   overflow on narrow Windows window sizes.

8. **Line spacing displays from default**: `LayoutSuite` stores the real
   `settings.lineSpacing` value, but the visible line-spacing label is
   default-relative. The default stored value `1.2` must display as `0.0`.

---

## Forbidden Changes

- Do not add direct `TextEditingController` mutation inside suite widgets.
- Do not create history entries from suite widgets directly.
- Do not restore Record/Settings/premium actions in `ProjectActionsSuite` without
  checking V5 scope.
- Do not change history popup values to reversed indices.
- Do not remove safe snapping for font dropdown values.
- Do not show raw `1.2` as the default line-spacing label in the editor layout
  suite.

---

## Known Fragilities

- **Callback contracts are dense**: `FormattingToolbarMVP` has many callbacks;
  changing one constructor parameter affects `script_editor_screen.dart`.
- **Provider reads in UI**: Layout/Color suites read Settings directly; expensive
  provider churn can rebuild the toolbar.
- **Text overflow**: Labels inside toolbar buttons must remain compact on small
  desktop windows.

---

## Shared-File Ownership Notes

Editor Suites owns widget composition only. Styling Engine owns what style
callbacks do; History owns undo/redo semantics; Settings owns spacing/color
persistence; File I/O owns project save/import callbacks.
