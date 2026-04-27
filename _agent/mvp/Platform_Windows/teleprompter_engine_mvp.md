---
name: Teleprompter Engine MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Teleprompter Engine MVP — Windows

Governs the rendering architectures and hardware execution flags.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | Riverpod controller handling voice command prioritization and manual overrides. |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `_handleSttResult(...)` | Callback routers parsing active inputs. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Teleprompter UI | `teleprompter_screen.dart` | Listens to scrolling offsets. |

---

## Invariants

1. **Bypass Limits**: Maximum words allowed per single frame update cannot break boundaries.

---

## Forbidden Changes

- Never interrupt active layout listeners.

---

## Known Fragilities

- Stale timers can occasionally cascade. Ensure safe clears.
