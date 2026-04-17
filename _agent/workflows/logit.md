---
description: Universal documentation synchronization; updates TODOs, Logs, and Readmes.
---
# /logit Protocol [TERMINAL_SYNC]

This command ensures the project's documentation is perfectly synchronized via the Terminal Layer.

1. **Audit Phase**:
   - Collect all session changes, discovered bugs (even if unfixed), and hardening achievements.

2. **Terminal Synchronization**:
// turbo
   - Update `MASTER_TODO_V4.md`, `DAILY_LOG.md`, and `README.md` using `cat << 'EOF' > path/to/file` commands.
   - **MANDATORY**: Do NOT use UI-based edit tools for these files to prevent sync bugs.
   - **GOVERNANCE**: NEVER delete lines from `MASTER_TODO_V4.md`. Sub-version increment ONLY (e.g. v3.6.1 to v3.6.2).
   - **PLATFORM-AWARE TODO UPDATES**: `MASTER_TODO_V4.md` is the single unified TODO file with four platform sections:
     - `## 🤖 APK — Sealed` — Android items only. **DO NOT MODIFY** (sealed at v4.0).
     - `## 🍎 iOS — Testing` — Append new iOS items here when developing for iOS.
     - `## 🖥️ macOS — Pending Development` — Append new macOS items here when developing for macOS.
     - `## 🪟 Windows — Pending Development` — Append new Windows items here when developing for Windows.
   - **Identify the active platform** from the current session context (e.g. IPA build = iOS, APK build = Android, macOS build = macOS) and append new TODO items ONLY to the matching platform section.

3. **Verification**:
   - Confirm file presence on disk: `ls -la *.md`
   - Verify content integrity: `tail -n 5 README.md`

---
> [!IMPORTANT]
> **Terminating Action**: `/logit` is the final required action for any successful `/run` or `/test` loop.
