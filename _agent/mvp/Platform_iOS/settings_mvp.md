---
name: Settings MVP
type: component
platform: iOS
last_updated: 2026-04-29
---

# Settings MVP - iOS

Governs iOS app settings, SharedPreferences persistence, recent-script
metadata, presentation defaults, hidden debug/STT controls, cloud-sync
placeholder UI, and profile/settings screens.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/settings/providers/settings_provider.dart` | `AppSettings`, `SettingsNotifier`, persistence keys, recent-script JSON, setters |
| `Platform_iOS/lib/features/settings/widgets/app_settings_screen.dart` | Settings/profile UI, display name, engine/debug controls |
| `Platform_iOS/lib/features/settings/widgets/cloud_sync_screen.dart` | Dormant cloud-sync UI placeholder |
| `Platform_iOS/lib/core/widgets/global_color_picker.dart` | Shared color picker used by settings/editor/presentation |

## External API

| Method / Field | Caller |
|----------------|--------|
| `settingsProvider` | Editor, gallery, teleprompter, settings UI |
| `AppSettings.recentScripts` | Gallery and restore flows |
| `AppSettings.lastScript` / `lastScriptTitle` | Startup/active script persistence |
| `AppSettings.sttEngine` | Teleprompter session start |
| `AppSettings.debugMode` | Debug logs and hidden gestures |
| `SettingsNotifier.saveScript(...)` | Editor/provider persistence |
| `SettingsNotifier.addToRecent(...)` / `removeFromRecent(...)` | Gallery/recent management |
| `SettingsNotifier.applySessionStyles(...)` | Restore flows |
| `SettingsNotifier.set*` methods | Settings, editor suites, teleprompter controls |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Script provider | `script_provider.dart` | Reads settings and calls `saveScript()` |
| Script editor | `script_editor_screen.dart` | Reads/writes display/style settings |
| Script gallery | `script_gallery_screen.dart` | Reads/mutates `recentScripts` |
| Teleprompter provider/screen | `teleprompter_provider.dart`, `teleprompter_screen.dart` | Reads STT, debug, scroll, mirror, color, spacing settings |
| Settings UI | `app_settings_screen.dart` | Calls profile/display setters |
| Color suite | `color_suite_mvp.dart` | Reads and writes color settings |

## Invariants

1. Persistence keys for settings, recent scripts, last script, history, STT
   engine, and display colors must stay stable without migration.
2. Recent-script JSON must preserve `sessionId`, `title`, `fullText`,
   `sourceType`, `historyIndex`, `historyJson`, and `style`.
3. Silent saves must not notify full UI listeners unless a new entry is created.
4. Recent updates prefer `sessionId`; title matching is fallback only.
5. Resetting appearance must not clear script/history data.

## Forbidden Changes

- Do not overwrite the entire recent list when updating one entry.
- Do not drop `historyJson` or `historyIndex`.
- Do not clear `recentScripts` from auth logout or settings reset.
- Do not enable dormant cloud/STT/recording features without explicit scope.

## Known Fragilities

- Recent entries can contain large script/history JSON strings.
- Duplicate titles collide when session IDs are missing.
- Silent writes can leave in-memory state stale by design.
- Legacy reset defaults may differ from current constructor defaults.

## Shared-File Ownership Notes

Settings owns storage. History owns history payload meaning; File I/O owns
`sourceType`; Teleprompter Engine owns runtime use of presentation settings.

---

## Windows v4.1.12 Final Migration Target

When iOS settings work resumes, port these verified Windows settings contracts
where the platform supports them:

- Font size has one persisted metadata/settings value shared by editor and
  presenter controls.
- Line, word, and letter spacing ranges must match between editor and presenter.
- Visible text skip must default off.
- External microphone selection must be documented before implementation. If
  iOS only supports OS-routed input selection, store no fake in-app device ID.
- Debug settings must expose diagnostics without resetting STT state, scroll
  targets, bookmarks, or confirmed word indices.
