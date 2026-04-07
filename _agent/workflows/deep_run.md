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
   - Run [/backup](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/backup.md) (Full Snapshot).
   - Run [/sync](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/sync.md) to align rules.
   - Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) for a fresh clean session.

4. **Deep Fix & Test Execution [ABSOLUTE_VERIFICATION]**
   - The AI must autonomously iterate through:
     - (1) **Research**: Identify root cause + collect all optional fix paths.
     - (2) **Test Route Planning**: Document the exact visual/logical steps to verify success for this SPECIFIC bug in `test/deep_analysis/[TASK_ID]_route.md`.
     - (3) **Execute**: Apply best fix.
     - (4) **[MANDATORY] Rebuild**: Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) to full-rebuild APK.
     - (5) **Absolute Test**: Execute [/deep_test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/deep_test.md).
     - (6) **Iterate**: Revert and try next fix if failed.
   - Present the fix for review ONLY after a successful [/deep_test].

5. **Cycle Closure**
   - Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md).
   - Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md).
   - Final Report: Provide a summary of the fix and the visual verification results.
