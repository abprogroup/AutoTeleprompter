---
name: Settings MVP
type: component
platform: Windows
last_updated: 2026-04-28
---

# Settings MVP - Windows

Governs Windows app settings, SharedPreferences persistence, recent-script
metadata, display defaults, presentation controls, hidden debug/STT toggles, and
the settings/profile UI.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/settings/providers/settings_provider.dart` | `AppSettings`, `SettingsNotifier`, persistence keys, recent-script JSON, setter methods |
| `Platform_Windows/lib/features/settings/widgets/app_settings_screen.dart` | Settings/profile UI and display-name editing |
| `Platform_Windows/lib/features/settings/widgets/cloud_sync_screen.dart` | Dormant cloud-sync UI placeholder for V5 |
| `Platform_Windows/lib/core/widgets/global_color_picker.dart` | Shared color picker used by editor and presentation settings |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `settingsProvider` | Editor, gallery, teleprompter, settings UI |
| `AppSettings.recentScripts` | Gallery, script provider, recent-script operations |
| `AppSettings.lastScript` / `lastScriptTitle` | Startup restore and active script persistence |
| `AppSettings.sttEngine` | `TeleprompterNotifier.startSession()` |
| `AppSettings.sttInputDeviceId` / `sttInputDeviceLabel` | Windows STT input selection and presenter/settings display |
| `AppSettings.debugMode` | Teleprompter debug logs and hidden gesture |
| `SettingsNotifier.saveScript(...)` | Editor/provider persistence and history metadata sync |
| `SettingsNotifier.addToRecent(...)` / `removeFromRecent(...)` | Gallery/recent management |
| `SettingsNotifier.applySessionStyles(...)` | Script restore flows |
| `SettingsNotifier.set*` methods | Editor suites, settings panels, teleprompter controls |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Script provider | `script_provider.dart` | Reads settings on build, calls `saveScript()` and style persistence |
| Script editor | `script_editor_screen.dart` | Reads display/style settings, calls setters and `saveScript()` |
| Script gallery | `script_gallery_screen.dart` | Reads and mutates `recentScripts` |
| Teleprompter provider | `teleprompter_provider.dart` | Reads `sttEngine`, `sttInputDeviceId`, `sttInputDeviceLabel`, `debugMode`, `scrollSpeed`, updates `scrollSpeed` via voice commands |
| Teleprompter screen | `teleprompter_screen.dart` | Reads display colors, scroll, mirror, spacing, fade, settings panel values, mic selection labels |
| Settings screen | `app_settings_screen.dart` | Calls display/profile setters and exposes Windows input settings/reset entry points |
| Color suite | `color_suite_mvp.dart` | Reads last chosen colors and background; calls color setters |

---

## Preserved State Properties Mapping

These `AppSettings` values and defaults were already documented by the earlier
Windows MVP file and remain part of the settings persistence contract:

| Variable | Default | Use Case |
|----------|---------|----------|
| `fontSize` | 20.0 | Text scaling |
| `languageMode` | `auto` | STT logic |
| `scrollLead` | 0.32 | Viewport constraints |
| `scrollSpeed` | 100.0 | Words per minute |
| `textAlign` | `center` | Layout |
| `mirrorHorizontal` | false | Glass prompts |
| `mirrorVertical` | false | Inverted overlays |
| `flipRotation` | 0 | Hardware orientations |
| `lineSpacing` | 1.2 | Scaling thresholds |
| `wordSpacing` | 0.0 | Padding bounds |
| `letterSpacing` | 0.0 | Compression bounds |
| `scriptBgColor` | 0xFF000000 | Chroma rendering |

---

## Invariants

1. **Persistence keys are stable**: Existing keys such as `fontSize`,
   `recentScripts`, `lastHistoryIndex`, `sttEngine`, and display/color keys must
   not be renamed without migration.

2. **Recent-script JSON is append-preserving metadata**: Entries must retain
   `sessionId`, `title`, `fullText`, `sourceType`, `historyIndex`,
   `historyJson`, and `style` fields when updating a known script.

3. **Silent save is real**: `saveScript(..., isSilent: true)` must write to disk
   without notifying UI listeners by changing `state.recentScripts`, except when
   a new entry must be created.

4. **Session ID beats title**: Recent updates should match by `sessionId` when
   present. Title matching is fallback only.

5. **Dynamic metadata repair stays active**: `_load()` sanitizes old recent
   entries and infers missing source types. Do not remove this compatibility
   path.

6. **Style bounds stay safe and platform-consistent**: Font size, line spacing,
   word spacing, letter spacing, colors, mirror flags, and rotation must remain
   valid for editor and teleprompter rendering. Windows editor and presenter
   controls must share the same font and spacing ranges: font `14.0..120.0`,
   line `0.5..3.0`, word `-5.0..20.0`, and letter `-2.0..5.0`.

6a. **Font size is a shared raw value**: `AppSettings.fontSize` is the raw script
    metadata number shown in both editor and present-mode controls. It must not
    store editor preview scaling, presenter render enlargement, or cursor-local
    inline `[size=...]` detection.

7. **Debug mode is hidden but functional**: `debugMode` may be toggled by hidden
   gallery gesture and read by teleprompter debug logs.

8. **Settings do not own raw editor text transforms**: Settings stores text and
   metadata; styling/tag mutation belongs to Script Editor/Styling MVPs.

9. **Debug mode gates diagnostics, not runtime state**: `debugMode` may reveal
   the sound bar, debug console, and debug-log copying/minimize controls, but
   toggling or collapsing diagnostics must not reset STT, scroll position, or
   `confirmedWordIndex`.

10. **Input-device selection is a Windows settings contract**: `sttEngine`,
    `sttInputDeviceId`, and `sttInputDeviceLabel` are persisted independently.
    Empty `sttInputDeviceId` means system default microphone. The label must be
    retained even if the device is not currently connected so the user can see
    what preference was saved.

---

## Forbidden Changes

- Do not overwrite the entire recent list when updating one entry.
- Do not drop `historyJson` or `historyIndex` during saves.
- Do not make silent saves notify full UI listeners unless the user explicitly
  accepts the flicker/regression risk.
- Do not clear `recentScripts` as part of auth logout or settings reset.
- Do not remove old-entry sanitization from `_load()`.
- Do not activate hidden V5 cloud/STT/recording settings without explicit scope.
- Do not treat `debugMode=false` as permission to stop STT or unload provider
  state. It is a diagnostics visibility setting.
- Do not save a microphone `deviceId` without the matching display label.
- Do not treat a missing saved microphone as a settings reset. The STT adapter
  owns runtime fallback to system default.
- Do not narrow present-mode spacing settings independently from the editor
  Layout Suite.
- Do not store half-size editor preview values in `fontSize`; settings store the
  real presenter font size.
- Do not let a hardcoded legacy default such as `18.0` override a loaded
  script/session font-size value or the current settings fallback.

---

## Known Fragilities

- **Large JSON strings**: Recent entries store full script text and history JSON;
  writes can be heavy.
- **Duplicate detection**: Matching by title can collide if session IDs are
  missing. Prefer preserving session IDs.
- **Silent state mismatch**: Silent writes update SharedPreferences without
  updating in-memory `state.recentScripts`; callers must know when they require a
  refreshed state view.
- **Legacy defaults**: Some reset paths use older defaults such as `fontSize`
  18.0 while current defaults may be 20.0. Treat resets carefully.
- **Device IDs can change**: WebView2/Chromium device IDs may change after
  permission resets, OS changes, or hardware reconnects. Preserve the saved
  label for user visibility and let STT fall back safely when the ID is stale.

---

## Shared-File Ownership Notes

History MVP owns the meaning of `historyIndex` and `historyJson`; Settings owns
their storage inside recent metadata. File I/O owns `sourceType` interpretation.
Teleprompter Engine owns runtime use of scroll/display settings.

---

## Preserved Original Contract Rows

The following rows and notes existed in the prior Windows Settings MVP and
remain preserved so hardening is additive, not destructive.

Legacy exact title marker: `# Settings MVP â€” Windows`

Prior scope statement: Governs the persistence of user UI defaults, scrolling
preferences, typography specifications, and external file paths mapped securely
to background isolates.

| Original Owned File Row | Preserved Role |
|-------------------------|----------------|
| `Platform_Windows/lib/features/settings/providers/settings_provider.dart` | Manages background persistence using `SharedPreferences`. |

| Original API Row | Preserved Where Called |
|------------------|------------------------|
| `setFontSize(double)` | Interactive control nodes |
| `saveScript(...)` | Writing script payloads |

| Original Caller Row | Preserved What It Calls |
|---------------------|-------------------------|
| Root Display Settings / `main.dart` | Subscribes to active layout configurations |

## State Properties Mapping

| Variable | Default | Use Case |
|----------|---------|----------|
| `fontSize` | 20.0 | Text scaling |
| `languageMode` | 'auto' | STT logic |
| `scrollLead` | 0.32 | Viewport constraints |
| `scrollSpeed` | 100.0 | Words per minute |
| `textAlign` | 'center' | Layout |
| `mirrorHorizontal` | false | Glass prompts |
| `mirrorVertical` | false | Inverted overlays |
| `flipRotation` | 0 | Hardware orientations |
| `lineSpacing` | 1.2 | Scaling thresholds |
| `wordSpacing` | 0.0 | Padding bounds |
| `letterSpacing` | 0.0 | Compression bounds |
| `scriptBgColor` | 0xFF000000 | Chroma rendering |

1. **Dynamic Format Sanitization**: When loading `recentScripts` on re-entry, missing types are parsed dynamically (`.pdf` -> `PDF`, `.docx` -> `DOCX`, `.txt` -> `TXT`) to maintain visual compatibility.
2. **Session ID Resilience**: Unidentified script entries generate distinct `rec_[time]` bounds.

- Never wipe metadata headers unexpectedly.
- **Race Conditions**: Large payload writes can saturate IO channels causing lag. Guard accordingly.

```markdown
---
name: Settings MVP
type: feature
platforms: Windows
last_updated: 2026-04-28
---

# Settings MVP â€” Windows

Governs the persistence of user UI defaults, scrolling preferences, typography specifications, and external file paths mapped securely to background isolates.

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/settings/providers/settings_provider.dart` | Manages background persistence using `SharedPreferences`. |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `setFontSize(double)` | Interactive control nodes |
| `saveScript(...)` | Writing script payloads |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Root Display Settings | `main.dart` | Subscribes to active layout configurations |

---

## State Properties Mapping

| Variable | Default | Use Case |
|----------|---------|----------|
| `fontSize` | 20.0 | Text scaling |
| `languageMode` | 'auto' | STT logic |
| `scrollLead` | 0.32 | Viewport constraints |
| `scrollSpeed` | 100.0 | Words per minute |
| `textAlign` | 'center' | Layout |
| `mirrorHorizontal` | false | Glass prompts |
| `mirrorVertical` | false | Inverted overlays |
| `flipRotation` | 0 | Hardware orientations |
| `lineSpacing` | 1.2 | Scaling thresholds |
| `wordSpacing` | 0.0 | Padding bounds |
| `letterSpacing` | 0.0 | Compression bounds |
| `scriptBgColor` | 0xFF000000 | Chroma rendering |

---

## Invariants

1. **Dynamic Format Sanitization**: When loading `recentScripts` on re-entry, missing types are parsed dynamically (`.pdf` -> `PDF`, `.docx` -> `DOCX`, `.txt` -> `TXT`) to maintain visual compatibility.
2. **Session ID Resilience**: Unidentified script entries generate distinct `rec_[time]` bounds.

---

## Forbidden Changes

- Never wipe metadata headers unexpectedly.

---

## Known Fragilities

- **Race Conditions**: Large payload writes can saturate IO channels causing lag. Guard accordingly.
```
