---
description: Orchestrates full project archives and surgical mirrors of modified files.
---
# /backup Workflow

This workflow ensures project safety by creating both full archives and surgical path-mirrors of modified files.

1. **Surgical Mirror**: If a specific file path is provided, run the following:
// turbo
```bash
./_agent/scripts/pre_change_backup.sh <file_path>
```

2. **Full Snapshot**: To create a complete timestamped archive of the source code, run:
// turbo
```bash
./_agent/scripts/backup.sh
```

---
> [!TIP]
> **Automation**: This command is automatically called by the `/run` and `/fix` loops.
