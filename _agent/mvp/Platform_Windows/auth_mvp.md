---
name: Auth MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Auth MVP — Windows

Governs user authentication, session state management, Pro license key validation, and the high-end visual login interface.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/auth/providers/auth_provider.dart` | Global state management: `AuthState` model, `AuthNotifier` logic (`_loadState`, `login`, `logout`, `activateLicense`). |
| `Platform_Windows/lib/features/auth/widgets/login_screen.dart` | The visual activation interface: captures credentials, maps UI events to the backend provider. |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `login(String email)` | `_handleActivation()` on button tap |
| `logout()` | Settings/Drawer logout action |
| `activateLicense(String key)` | `_handleActivation()` on button tap |
| `state.email` | Routing state checks, welcome banners |
| `state.isPro` | Gating premium feature overlays |
| `state.isAdmin` | Auto-unlocking Pro tools for developers |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Initial Boot Check | `main.dart` | Reads `authProvider` to route to `LoginScreen` or `TeleprompterScreen` |
| Settings Drawer | `settings_drawer.dart` | Calls `authNotifier.logout()` |

---

## Invariants

1. **State Persistence Keys**: The SharedPreferences keys MUST strictly be `auth_email`, `auth_is_pro`, and `auth_license_key`. Changing these will break backwards compatibility with existing local data.

2. **Admin Override Privilege**: The address `abmpro.office@gmail.com` is a hardcoded administrative bypass. Entering this email guarantees automatic Pro suite unlock using license key `PRO-ADMIN-V3`.

3. **License Format Control**: Valid license activation strings MUST start with `PRO-` prefix to bypass visual rejection.

4. **Cross-Feature Cleanliness**: Logging out wipes the auth tokens, but it DOES NOT wipe the cached scripts from the database.

---

## Forbidden Changes

- Do not call `activateLicense()` without first executing a valid `login()` pass to establish the email context.
- Do not route users to the application environment if `state.email` is empty.

---

## Known Fragilities

- **Mock Verification**: The license key verification system is completely mocked locally. Do not trust it as an enterprise security layer against tampering.
- **Context Mounting**: `_handleActivation()` calls `Navigator.pop(context)` asynchronously. Ensure `if (mounted)` guards remain wrapped around dialog/snack dismissals.
