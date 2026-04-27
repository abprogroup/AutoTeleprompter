---
name: Script Editor MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Script Editor MVP (Windows)

Governs the creation, editing, parsing, saving, and rich-text markup generation of teleprompter scripts. (Note: History and Text Selection have their own specialized MVPs).

---

## Owned Files

### Shared Contract
| File | Role |
|------|------|
| `lib/features/script/providers/script_provider.dart` | Manages the list of scripts, CRUD operations. |
| `lib/features/script/models/script.dart` | The data model for a single script (title, raw text, parsed words). |
| `lib/features/script/services/script_parser.dart` | Converts raw text into tokenized `ScriptWord` objects. |

### Platform_Windows Specifics
| File | Role |
|------|------|
| `lib/features/script/widgets/script_editor_screen.dart` | The UI for typing, formatting text, and saving scripts. |
| `lib/features/script/widgets/script_list_screen.dart` | The library UI for selecting a script to read. |

---

## External API (what outside code may call)

| Method / Field | Caller |
|----------------|--------|
| `Script` object | `TeleprompterProvider` / `WordAligner` — For reading text and STT matching. |
| `ScriptProvider` state | `TeleprompterScreen` — To load the selected script. |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Teleprompter Engine | `teleprompter_screen.dart` | Reads the parsed `ScriptWord` list to render the scrolling text. |
| STT Word Aligner | `word_aligner.dart` | Reads the parsed `ScriptWord` list to track voice position. |

---

## Invariants

1. **Parser Isolation**: The `ScriptParser` MUST accurately map raw text (including complex rich-text tags like `[color=#FF0000]`) into plain `normalized` strings for the STT engine, while preserving the visual tags for the UI. It must never lose paragraph breaks.

---

## Forbidden Changes

- Do not implement real-time speech recognition logic inside the Script Editor. The editor is strictly for text manipulation.
- Do not alter the `Script` data model without updating both the Teleprompter rendering logic and the STT alignment logic, as they are strict consumers of this model.
