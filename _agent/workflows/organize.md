---
description: Cleans the workspace of temporary files, build logs, and test artifacts.
---
1. **Identify Junk**: Find temporary files in `/tmp`, build logs/caches, or one-off test scripts created during the session.
2. **Cleanup**: Remove these files using `run_command` or project-specific tools.
3. **Verify Integrity**: Ensure no essential source files were accidentally targeted.
4. **Conclusion**: Signal a "Fresh Start" state to the user.

---
*Command: /organize*
