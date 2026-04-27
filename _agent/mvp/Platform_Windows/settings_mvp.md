---
name: Settings MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Settings MVP (Windows)

Governs global application settings, persistent user configurations, custom themes, and typography options.

---

## Owned Files

### Shared Contract
| File | Role |
|------|------|
| `lib/features/settings/providers/settings_provider.dart` | Riverpod provider maintaining current state of settings. |
| `lib/features/settings/models/app_settings.dart` | The immutable model containing scrolling speeds, font sizes, colors. |

### Platform_Windows Specifics
| File | Role |
|------|------|
| `lib/features/settings/widgets/settings_drawer.dart` | The sidebar/modal UI for users to adjust values locally. |

---

## External API (what outside code may call)

| Method / Field | Caller |
|----------------|--------|
| `settingsProvider` | Used everywhere to adapt visual rendering to user preferences. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| UI Theme wrappers | `main.dart` | Pulls core color values. |
| Teleprompter Engine | `teleprompter_screen.dart` | Pulls target font sizes and line heights. |

---

## Invariants

1. **Persist on Change**: Any user modification via the `settings_drawer` MUST immediately trigger a write to local storage (e.g. `SharedPreferences`) to avoid data loss across app restarts.

---

## Forbidden Changes

- Do not move the active STT locale selection logic out of the `TeleprompterProvider` into Settings (Settings only stores user defaults, not live session data).
- Do not write large, heavy data blobs (like scripts) into the settings storage mechanism.
