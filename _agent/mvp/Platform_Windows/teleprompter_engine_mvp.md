---
name: Teleprompter Engine MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Teleprompter Engine MVP (Windows)

Governs the visual physics of the scrolling text, the fluid advance animations, play/pause controls, and layout rendering.

---

## Owned Files

### Shared Contract
| File | Role |
|------|------|
| `lib/features/teleprompter/providers/teleprompter_state.dart` | Manages rendering states (scrolling position, active speed). |

### Platform_Windows Specifics
| File | Role |
|------|------|
| `lib/features/teleprompter/widgets/teleprompter_screen.dart` | The core visual layer displaying the teleprompter script. |

---

## External API (what outside code may call)

| Method / Field | Caller |
|----------------|--------|
| `TeleprompterScreen` entry point | `main.dart` / Script Editor — Navigating to start reading. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| App Router | `main.dart` | Passes loaded script arguments to render the screen. |

---

## Invariants

1. **Strict Decoupling**: The engine handles visually updating the scroll offset based on position indexes. It must NEVER contain logic to process user speech—it only receives instructions from the external STT MVP.

---

## Forbidden Changes

- Do not place background audio listeners inside this visual component.
- Do not remove performance optimizations (like `ScrollablePositionedList`) that prevent UI lag during rapid scrolling.
