---
description: "Master Broad loop for multi-task fix sessions (Planning → Fast-Execution → Verification)."
---
# /run Protocol [v3.9.5.1 MEGA_LOOP]

0. **Authority Ritual Phase (v3.9.5.2)**:
   - **0.0. Authority Clearance**: Run [/clearance](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/clearance.md) to trigger all OS/IDE permissions upfront. **USER MUST CLICK "ALWAYS ALLOW" ON POPUPS.**
   - **MANDATORY**: AI does NOT proceed to Step 1 until Authority level 1:1 is achieved.

1. **Initialization Phase**:
   - **1.1. Mode Selection**: Prompt the USER:
     - "A) How many TODOs should I fix in this session?"
     - "B) How much time (duration) should I run the loop for?"
   - **1.2. Protocol Lock**: Confirm that the Task Timer and Persistence Guard (caffeinate) are ready for the selected duration.

2. **Safety Phase (Session Start)**:
// turbo
   2.1. Start [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh) if not yet active (`caffeinate`).
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
   6.1. Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md).
// turbo
   6.2. Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md).
   6.3. Final Git Commit: Commit results to the repository.

7. **Next Task Polling**:
   - If User Mode (Count or Duration) has not been reached:
     - Clear the [Task Timer](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/task_timer.sh).
     - **Recurse to Step 3** (Planning Phase for the next task).
   - If Session Limit Reached:
     - **Teardown**: Stop [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh) & Clear all timers.
     - **Deployment Phase**: Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md).

---
> [!IMPORTANT]
> **[Persistence Guard]**: Ensures the Mac stays awake during 7-hour autonomous sessions (v3.9.5.1 Hardened).
