---
name: Settings MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Settings MVP — Windows

Governs the persistence of user UI defaults, scrolling preferences, typography specifications, and external file paths mapped securely to background isolates.

---

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

## Invariants

1. **Strict Lower Bounds**: Spacing settings are clamped above 0.1 to preserve screen draw calculations safely.

---

## Forbidden Changes

- Never wipe metadata headers unexpectedly.

---

## Known Fragilities

- **Race Conditions**: Large payload writes can saturate IO channels causing lag. Guard accordingly.
