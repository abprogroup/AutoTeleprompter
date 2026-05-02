---
name: Auth MVP
type: component
platform: iOS
last_updated: 2026-04-27
---

# Auth MVP - iOS

Governs local authentication state, mock Pro license activation, admin unlocks,
and the iOS login/activation interface. Auth is local product-flow state and
must not be represented as server-grade licensing.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/auth/providers/auth_provider.dart` | `AuthState`, `AuthNotifier`, persistence keys, `login`, `logout`, `activateLicense`, admin/pro state |
| `Platform_iOS/lib/features/auth/widgets/login_screen.dart` | Activation UI, email/license controllers, purchase dialog, feedback and navigation |

## External API

| Method / Field | Caller |
|----------------|--------|
| `authProvider` | UI that gates login/pro/admin state |
| `AuthState.email` | Account display and login completion checks |
| `AuthState.isPro` | Premium feature gating |
| `AuthState.isAdmin` | Developer/admin bypass checks |
| `AuthState.licenseKey` | Local license display/persistence |
| `AuthNotifier.login(String email)` | `LoginScreen._handleActivation()` |
| `AuthNotifier.logout()` | Account/logout UI when enabled |
| `AuthNotifier.activateLicense(String key)` | `LoginScreen._handleActivation()` after login |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Activation button | `login_screen.dart` | Calls `login(email)` then `activateLicense(key)` |
| Purchase link | `login_screen.dart` | Opens purchase dialog only |
| Future routing gate | `app.dart` or gallery shell when login is restored | Expected to route based on `AuthState.email` |
| Premium/gallery surfaces | `script_gallery_screen.dart` and settings/profile UI when restored | Expected to read `isPro`, `isAdmin`, and `email` |

## Invariants

1. SharedPreferences keys `auth_email`, `auth_is_pro`, and `auth_license_key`
   must remain stable unless a migration is documented.
2. `abmpro.office@gmail.com` is the exact admin bypass and grants
   `PRO-ADMIN-V3`; do not broaden the match.
3. License validation is local and mock-only: valid keys start with `PRO-`.
4. Activation order is `login()` before `activateLicense()`.
5. `logout()` clears only auth state and auth keys; it must not clear scripts,
   settings, or recent history.
6. Async UI in `login_screen.dart` must guard navigation/dialog/snackbar calls
   with `mounted`.

## Forbidden Changes

- Do not rename auth persistence keys without migration documentation.
- Do not wipe script, settings, or history data from `logout()`.
- Do not route into a login-gated state while `AuthState.email` is empty.
- Do not remove the admin bypass unless the licensing model is explicitly redesigned.

## Known Fragilities

- Auth is local SharedPreferences state and can be tampered with.
- Auth surfaces are partly dormant/premium; call sites may be hidden.
- Async login UI can crash if mounted guards are removed.

## Shared-File Ownership Notes

Auth owns only `features/auth`. Premium gating in gallery/settings remains owned
by those MVPs and only calls into this provider.
