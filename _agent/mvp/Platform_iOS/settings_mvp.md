---
name: Settings MVP
type: component
platform: iOS
last_updated: 2026-05-02
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
| `AppSettings.sttVisibleSkipEnabled` | Presenter visible-skip setting; default off |
| `AppSettings.sttInputDeviceId` / `sttInputDeviceLabel` | iOS presenter mic route selector |
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
- External microphone selection stores native iOS route IDs only. Empty ID
  means System Default; do not store fake Windows/WebView device IDs.
- Debug settings must expose diagnostics without resetting STT state, scroll
  targets, bookmarks, or confirmed word indices.

---

## iOS One Font-Size Authority Port - 2026-05-02

- `AppSettings.fontSize` is the live settings value that editor and presenter
  controls display.
- Script-specific changes must also be persisted into recent-script style
  metadata through `ScriptNotifier.updateStyleMetadata(fontSize: ...)`.
- Present mode may render larger for readability, but presenter settings
  labels and sliders must show/edit the raw metadata value, not the enlarged
  render value.
- Do not add a second presenter-only font-size preference.

---

## iOS Synced Spacing Ranges Port - 2026-05-02

- Settings setters enforce the shared editor/presenter spacing ranges:
  `lineSpacing 0.5..3.0`, `wordSpacing -5.0..20.0`, and
  `letterSpacing -2.0..5.0`.
- Line spacing default display is default-relative: saved `1.2` is shown as
  `0.0` in editor and present controls.
- Spacing changes must persist to settings preferences and script metadata.
- Do not keep a presenter-only spacing range that differs from the editor
  Layout Suite.

---

## iOS External Microphone Settings Port - 2026-05-02

- iOS persists `sttInputDeviceId` and `sttInputDeviceLabel` for the presenter
  Speech Input selector.
- Empty `sttInputDeviceId` means System Default microphone.
- iOS device IDs are `AVAudioSessionPortDescription.uid` values from the native
  route list. They must not be shared with Windows WebView2 device IDs.
- If a saved route is unavailable, the STT adapter must fall back to the active
  iOS/system route without resetting script position.

---

## iOS Visible Skip Settings Port - 2026-05-02

- `AppSettings.sttVisibleSkipEnabled` remains default `false`.
- `TeleprompterSettingsPanel` exposes the present-mode
  `Allow visible text skip` switch.
- When the switch is off, STT may use only the default local recovery window.
- When the switch is on, the provider may pass the currently rendered visible
  word window to the aligner; visible skip must remain bounded to that window.
- Do not enable visible skip automatically during STT start, resume, search,
  bookmark jumps, or settings restore.
