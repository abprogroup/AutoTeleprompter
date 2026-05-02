---
name: Auth MVP
type: component
platform: Windows
last_updated: 2026-04-27
---

# Auth MVP - Windows

Governs local authentication state, mock Pro license activation, admin unlocks,
and the Windows login/activation interface. Auth is local-only in the current
Windows code and must not be treated as server-grade security.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/auth/providers/auth_provider.dart` | `AuthState`, `AuthNotifier`, persistence keys, `login`, `logout`, `activateLicense`, admin/pro state |
| `Platform_Windows/lib/features/auth/widgets/login_screen.dart` | Activation UI, email/license text controllers, purchase dialog, user feedback |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `authProvider` | Any UI that gates login/pro/admin state |
| `AuthState.email` | App routing, account display, login completion checks |
| `AuthState.isPro` | Premium feature gating and Pro dashboard eligibility |
| `AuthState.isAdmin` | Developer/admin bypass checks |
| `AuthState.licenseKey` | Account/license display and local persistence |
| `AuthNotifier.login(String email)` | `LoginScreen._handleActivation()` |
| `AuthNotifier.logout()` | Account/logout UI when auth UI is enabled |
| `AuthNotifier.activateLicense(String key)` | `LoginScreen._handleActivation()` after `login()` |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Activation button | `login_screen.dart` | Calls `login(email)` then `activateLicense(key)` |
| Purchase link | `login_screen.dart` | Opens `_showPurchaseDialog()` only; no provider mutation |
| Premium UI restored from V5 | `script_gallery_screen.dart` and settings/gallery surfaces | Expected to read `authProvider.email`, `isPro`, `isAdmin` |
| Future routing gate | `app.dart` or gallery shell if login is restored | Expected to route based on `AuthState.email` |

---

## Invariants

1. **Persistence keys are stable**: `auth_email`, `auth_is_pro`, and
   `auth_license_key` must not be renamed. Existing local Windows installs rely
   on these keys.

2. **Admin bypass is exact**: `abmpro.office@gmail.com` auto-enables Pro and
   Admin with license key `PRO-ADMIN-V3`. Do not broaden this match.

3. **License activation is local and mock-only**: A valid license currently means
   `key.startsWith('PRO-')`. Do not present this as server verification.

4. **Login precedes activation**: `activateLicense()` assumes email context
   exists. UI must call `login()` before activating a license.

5. **Logout preserves user scripts**: `logout()` clears only auth keys and auth
   state. It must not clear `recentScripts`, cached scripts, or settings.

6. **Mounted checks protect async UI**: After async activation, `login_screen.dart`
   must check `mounted` before navigation, snackbars, or dialogs.

---

## Forbidden Changes

- Do not change SharedPreferences auth keys without a migration plan and doc
  update.
- Do not wipe scripts, settings, or recent activity from `logout()`.
- Do not route into a login-gated app state when `AuthState.email` is empty.
- Do not call `activateLicense()` before `login()` in the activation flow.
- Do not remove the admin bypass unless the user explicitly requests a licensing
  redesign.

---

## Known Fragilities

- **Mock security**: Local SharedPreferences can be modified by a user. This MVP
  is product-flow state, not tamper-proof licensing.
- **Hidden feature state**: Auth UI is currently a dormant/premium feature. Code
  may be present even when entry points are hidden.
- **Async context risk**: `LoginScreen._handleActivation()` awaits provider calls
  and then touches UI. Missing `mounted` checks can crash on fast back navigation.

---

## Shared-File Ownership Notes

Auth owns only files under `features/auth`. If auth UI is restored in
`script_gallery_screen.dart`, that call site becomes a caller of this MVP but
does not transfer gallery ownership to Auth. Premium gating also intersects with
the V5 deferred-feature tracker.

---

## Preserved Original Contract Rows

The following rows and notes existed in the prior Windows Auth MVP and remain
preserved so hardening is additive, not destructive.

Legacy exact title marker: `# Auth MVP â€” Windows`

Prior scope statement: Governs user authentication, session state management,
Pro license key validation, and the high-end visual login interface.

| Original Owned File Row | Preserved Role |
|-------------------------|----------------|
| `Platform_Windows/lib/features/auth/providers/auth_provider.dart` | Global state management: `AuthState` model, `AuthNotifier` logic (`_loadState`, `login`, `logout`, `activateLicense`). |
| `Platform_Windows/lib/features/auth/widgets/login_screen.dart` | The visual activation interface: captures credentials, maps UI events to the backend provider. |

| Original API Row | Preserved Where Called |
|------------------|------------------------|
| `login(String email)` | `_handleActivation()` on button tap |
| `logout()` | Settings/Drawer logout action |
| `activateLicense(String key)` | `_handleActivation()` on button tap |
| `state.email` | Routing state checks, welcome banners |
| `state.isPro` | Gating premium feature overlays |
| `state.isAdmin` | Auto-unlocking Pro tools for developers |

| Original Caller Row | Preserved What It Calls |
|---------------------|-------------------------|
| Initial Boot Check / `main.dart` | Reads `authProvider` to route to `LoginScreen` or `TeleprompterScreen` |
| Settings Drawer / `settings_drawer.dart` | Calls `authNotifier.logout()` |

1. **State Persistence Keys**: The SharedPreferences keys MUST strictly be `auth_email`, `auth_is_pro`, and `auth_license_key`. Changing these will break backwards compatibility with existing local data.
2. **Admin Override Privilege**: The address `abmpro.office@gmail.com` is a hardcoded administrative bypass. Entering this email guarantees automatic Pro suite unlock using license key `PRO-ADMIN-V3`.
3. **License Format Control**: Valid license activation strings MUST start with `PRO-` prefix to bypass visual rejection.
4. **Cross-Feature Cleanliness**: Logging out wipes the auth tokens, but it DOES NOT wipe the cached scripts from the database.

- Do not call `activateLicense()` without first executing a valid `login()` pass to establish the email context.
- Do not route users to the application environment if `state.email` is empty.
- **Mock Verification**: The license key verification system is completely mocked locally. Do not trust it as an enterprise security layer against tampering.
- **Context Mounting**: `_handleActivation()` calls `Navigator.pop(context)` asynchronously. Ensure `if (mounted)` guards remain wrapped around dialog/snack dismissals.

```markdown
---
name: Auth MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Auth MVP â€” Windows

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
```
