---
name: Script Editor MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Script Editor MVP — Windows

Governs the underlying tokenization pipeline, the robust multi-extension parser (`.docx`, `.pages`, `.rtf`, `.doc`), formatting mappings, and persistent local script state transitions.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/script/providers/script_provider.dart` | The engine core: manages CRUD pipelines via `loadText`, `importFile`, `parseFile`, and deep string parsers. |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `loadText(String text, ...)` | Main file access handlers |
| `clear()` | Erasing persistent session states |
| `importFile(File file)` | System picker callback paths |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Initial UI Layout | `teleprompter_screen.dart` | Pulls active parsed sentences |

---

## Invariants

1. **Safe Fallback Indexing**: Raw string searches mapping file boundaries fallback to index zero automatically.

---

## Forbidden Changes

- Never drop core formatting metadata passes.

---

## Known Fragilities

- **Corrupt Archives**: Malformed `.docx` files throw heavy central directory read exceptions. Ensure robust try-catch guards.
