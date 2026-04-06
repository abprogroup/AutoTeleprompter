---
description: Master autonomous loop. Executes the full development cycle sequentially.
---
# /run Workflow

1. **Safety Phase**:
// turbo
   1.1. Start [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh): `./_agent/scripts/persistence_guard.sh start`
// turbo
   1.2. Archive State: Run [/backup](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/backup.md)
   1.3. Run [Safety Guard (Timer)](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/task_timer.sh) check.

2. **Planning Phase**: Run [/plan](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/plan.md).

3. **Execution Phase**: Run [/fix](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/fix.md).

4. **Verification Phase**: Run [/test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/test.md).

5. **Synchronization Phase**:
// turbo
   5.1. Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md) to sync all documentation.

6. **Teardown**:
// turbo
   6.1. Stop [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh): `./_agent/scripts/persistence_guard.sh stop`
   6.2. Clear timers.
