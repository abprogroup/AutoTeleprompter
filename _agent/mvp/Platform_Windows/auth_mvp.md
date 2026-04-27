---
name: Auth MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Auth MVP (Windows)

Governs user authentication, session state management, and the visual login UI. 

---

## Owned Files

### Shared Contract
| File | Role |
|------|------|
| `lib/features/auth/providers/auth_provider.dart` | Manages global auth state (logged in/out, user token). |

### Platform_Windows Specifics
| File | Role |
|------|------|
| `lib/features/auth/widgets/login_screen.dart` | The UI for user login. Specific to Windows layout dimensions and interactions. |

---

## External API (what outside code may call)

| Method / Field | Caller |
|----------------|--------|
| `authProvider` state | `main.dart` / Router — To determine whether to show Login or Home screen. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| App Router | `main.dart` | Listens to auth state changes to redirect users. |

No other feature code should touch the Auth MVP directly. The Script Editor and STT Engine must NOT depend on Auth state internally; they simply assume a valid user if they are rendered on screen.

---

## Invariants

1. **State Isolation**: Auth state is completely isolated from Script state. Logging out must safely dispose of auth tokens without directly destroying local un-synced script data (that is the domain of the Script Editor MVP).

---

## Forbidden Changes

- Do not inject STT or Teleprompter logic into the Auth Provider.
- Do not bypass the auth provider to manually navigate past the login screen.
