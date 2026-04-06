---
description: Universal documentation synchronization; updates TODOs, Logs, and Readmes.
---
# /logit Protocol [TERMINAL_SYNC]

This command ensures the project's documentation is perfectly synchronized via the Terminal Layer.

1. **Audit Phase**:
   - Collect all session changes, discovered bugs (even if unfixed), and hardening achievements.

2. **Terminal Synchronization**:
// turbo
   - Update `MASTER_TODO.md`, `DAILY_LOG.md`, and `README.md` using `cat << 'EOF' > path/to/file` commands.
   - **MANDATORY**: Do NOT use UI-based edit tools for these files to prevent sync bugs.

3. **Verification**:
   - Confirm file presence on disk: `ls -la *.md`
   - Verify content integrity: `tail -n 5 README.md`

---
> [!IMPORTANT]
> **Terminating Action**: `/logit` is the final required action for any successful `/run` or `/test` loop.
