---
name: Remote MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Remote MVP (Windows)

Governs the integration of external hardware remote controls (e.g., Bluetooth clickers, pedals) to manually control the teleprompter scrolling.

---

## Owned Files

### Shared Contract
| File | Role |
|------|------|
| `lib/features/remote/services/remote_control_service.dart` | The core listener for keyboard/HID events sent by remote hardware. |
| `lib/features/remote/models/remote_command.dart` | Enums and models defining actions like 'Play', 'Pause', 'SpeedUp', 'SpeedDown'. |

### Platform_Windows Specifics
| File | Role |
|------|------|
| `lib/features/remote/services/windows_hid_listener.dart` | (If applicable) Windows-specific HID event capture layer. |

---

## External API (what outside code may call)

| Method / Field | Caller |
|----------------|--------|
| `commandStream` / callbacks | `TeleprompterScreen` — To react to physical button presses. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Teleprompter UI | `teleprompter_screen.dart` | Listens to the Remote Service to trigger `TeleprompterProvider` methods (scroll, pause, adjust speed). |

---

## Invariants

1. **Passive Emitting**: The Remote MVP must ONLY emit command events. It must NEVER directly mutate the `TeleprompterProvider` state or directly manipulate the scroll controller. The UI layer receives the command and decides how to act on it.

---

## Forbidden Changes

- Do not hardcode specific scroll speeds inside the remote listener (it only sends commands, the provider applies the speed changes).
- Do not make the STT MVP listen to the Remote MVP directly. Both must communicate via the UI/Provider layer.
