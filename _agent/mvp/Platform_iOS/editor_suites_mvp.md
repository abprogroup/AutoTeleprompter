---
name: Editor Suites MVP
type: component
platform: iOS
last_updated: 2026-05-02
---

# Editor Suites MVP - iOS

Governs the iOS editor toolbar/suite widgets that expose text, layout, color,
history, formatting, and project actions to the script editor.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/script/widgets/editor/suites/text_suite_mvp.dart` | Font family/size and text style controls |
| `Platform_iOS/lib/features/script/widgets/editor/suites/layout_suite_mvp.dart` | Alignment, spacing, and layout controls |
| `Platform_iOS/lib/features/script/widgets/editor/suites/color_suite_mvp.dart` | Color selection controls and color picker bridge |
| `Platform_iOS/lib/features/script/widgets/editor/suites/formatting_toolbar_mvp.dart` | Toolbar host and suite switching UI |
| `Platform_iOS/lib/features/script/widgets/editor/suites/history_suite_mvp.dart` | Undo/redo menu controls |
| `Platform_iOS/lib/features/script/widgets/editor/suites/project_actions_mvp.dart` | Save/import/export/project actions |
| `Platform_iOS/lib/features/script/widgets/editor/components/editor_primitives.dart` | Shared suite controls and `EditorSuite` enum |

## External API

| Method / Field | Caller |
|----------------|--------|
| `FormattingToolbarMVP` | `script_editor_screen.dart` |
| `TextSuite`, `LayoutSuite`, `ColorSuite` | Toolbar host/editor screen |
| `HistorySuite` | Toolbar host/editor history callbacks |
| `ProjectActionsSuite` | Toolbar host/save/import callbacks |
| `EditorSuite` | Editor toolbar state |
| `ToolBtn`, `FormatPopup`, `SliderRow` | Suite widgets |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Script editor | `script_editor_screen.dart` | Instantiates toolbar and handles callbacks |
| Styling Engine | `styling_logic_mixin.dart` | Receives style command callbacks |
| History MVP | `history_suite_mvp.dart`, editor screen | Receives undo/redo callbacks |
| File I/O MVP | `project_actions_mvp.dart`, editor screen | Receives save/import/export callbacks |
| Settings MVP | `settings_provider.dart` | Stores style/display changes |

## Invariants

1. Suite widgets are UI/control surfaces; editor state mutation remains in the
   editor screen or owning MVP callbacks.
2. `EditorSuite` values must stay in sync with toolbar switching logic.
3. History controls must call History-owned callbacks, not mutate `_history`
   directly.
4. Project actions must route through Script Editor/File I/O ownership.
5. Suite controls must be stable on mobile-sized iOS viewports.

## Forbidden Changes

- Do not create controllers inside suite widgets.
- Do not write directly to history stacks from suite widgets.
- Do not bypass settings/style callbacks with local-only state.
- Do not add platform behavior in shared suite controls without a platform MVP note.

## Known Fragilities

- Suite callbacks cross several MVP ownership boundaries.
- Toolbar state can drift from active selection/cursor style.
- Compact iOS screens can overflow if controls grow dynamically.

## Shared-File Ownership Notes

Suites own UI controls only. Styling, History, File I/O, Selection, and Script
Editor own the behavior invoked by suite callbacks.

---

## iOS Synced Spacing Ranges Port - 2026-05-02

- `layout_suite_mvp.dart` owns editor-facing spacing controls.
- Editor and present mode spacing ranges must match:
  - line spacing: `0.5..3.0`, displayed as an offset from default `1.2`
    where `1.2` reads `0.0`.
  - word spacing: `-5.0..20.0`.
  - letter spacing: `-2.0..5.0`.
- Editor spacing changes must call both the Settings setter and
  `ScriptNotifier.updateStyleMetadata(...)` for the matching spacing field.
- `SliderRow.displayValue` may be used for default-relative labels; it must not
  change the underlying saved numeric value.
