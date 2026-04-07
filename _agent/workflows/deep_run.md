---
description: Redefined autonomous loop for focused, one-at-a-time bug fixing with deep verification.
---
// turbo-all

1. **Identification Phase**
   - Read [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md).
   - Extract all items marked with `[X]`.
   - **STOP**: Present the list to the USER and ask: "Which bug should we focus on for this Deep Run?"

2. **Test Case Validation**
   - Check if the selected bug has complete documentation:
     - **1. -> 2. -> 3.** (Reproducing steps).
     - **\*Wanted Result\***: (Target outcome).
     - **\*Meaning\***: (Reasoning behind the failure).
   - If NOT complete:
     - **STOP**: Prompt the USER for the missing details.
     - Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) with the provided documentation.

3. **Session Preparation**
   - Run [/backup](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/backup.md) (Full Snapshot + Surgical Mirror).
   - Run [/sync](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/sync.md) to align with all project rules.
   - Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) to ensure a fresh session.

4. **Deep Fix & Test Execution**
   - Execute [/deep_fix](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/deep_fix.md) for the selected bug.
   - Execute [/deep_test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/deep_test.md) for the selected bug.

5. **Cycle Closure**
   - Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md).
   - Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md).
   - Final Report: Provide a summary of the fix and the visual verification results.
