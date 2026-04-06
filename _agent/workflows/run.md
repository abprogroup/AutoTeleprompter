---
description: Master autonomous loop. Executes the full development cycle sequentially.
---
1. **Initialize**: Run [/sync](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/sync.md).
2. **Session Setup**: Ask the user: **"Loop by time OR by amount?"**
    - **If TIME**: 
        a. Ask "How long we want the loop to work?"
        b. Ask "Fix by urgency OR by the list order (1-by-1)?"
    - **If AMOUNT**: 
        a. Present [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) by urgency.
        b. Ask for selection and task quota.
3. **Plan Phase**: Execute `./_agent/scripts/task_timer.sh start` then run [/plan](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/plan.md).
4. **Fix Phase**: Run [/fix](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/fix.md).
5. **Verify Phase (GUARD)**: Run [/test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/test.md).
    - **RULE**: If `/test` does not return a "Success" verification, STOP the loop. Do not proceed to the next task.
6. **Safety Phase**: After a successful test, run the backup utility:
    - **ACTION**: Execute `./scripts/backup.sh`.
    - **RULE**: If the backup fails, STOP the loop. 
7. **Cycle**: Repeat only if the previous task was successfully verified, committed, and backed up.

---
*Command: /run*
