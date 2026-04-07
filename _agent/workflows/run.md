---
description: Master autonomous loop. Executes the full development cycle sequentially with strict User Mode Selection, Optimized Dual-Backups, and Access Verification.
---
# /run Workflow [v3.6.1 MEGA_LOOP]

1. **Initialization Phase**:
   - **1.1. Mode Selection**: The AI must stop and ask the user:
     - "A) How many TODOs should I fix in this session?"
     - "B) How much time (duration) should I run the loop for?"
// turbo
   - **1.2. Workspace Access Verification [WAV]**: 
     - Run `ls -R lib _agent backups` and diagnostic `touch` to verify full R/W/X permissions.
     - **MANDATORY**: Report "Workspace Verified" or list missing permissions before proceeding.
   - **Gating**: Do NOT proceed to Step 2 until Mode is selected AND Workspace is verified.

2. **Safety Phase (Session Start)**:
// turbo
   2.1. Start [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh) if not yet active.
// turbo
   2.2. Start/Reset [Task Timer](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/task_timer.sh): `./_agent/scripts/task_timer.sh start`
// turbo
   2.3. Full Session Backup: Run `./_agent/scripts/backup.sh` (Snapshot entire project).

3. **Planning Phase**: Run [/plan](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/plan.md).

4. **Execution Phase**: 
// turbo
   4.1. Surgical Backup: Run `./_agent/scripts/pre_change_backup.sh [Target File]` before any edit.
   4.2. Run [/fix](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/fix.md).

5. **Verification Phase**: Run [/test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/test.md).

6. **Synchronization & Cleanup Phase**:
// turbo
   6.1. Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md) (Workspace Cleanup).
// turbo
   6.2. Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md) (Terminal Sync).
   6.3. Commit to Git.

7. **Next Task Polling**:
   - If User Mode (Count or Duration) has not been reached:
     - Clear the [Task Timer](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/task_timer.sh): `./_agent/scripts/task_timer.sh clear`
     - **Recurse to Step 3** (Planning Phase for the next task).
   - If Session Limit Reached:
     - **Teardown**: Stop [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh) & Clear all timers.
     - **Deployment Phase**: Run [/Emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md).

---
> [!IMPORTANT]
> **[WAV] Mandate**: Workspace verification is required at every session start to prevent permission-related stalls during fresh conversations.
