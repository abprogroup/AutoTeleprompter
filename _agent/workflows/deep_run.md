---
description: Redefined autonomous loop for focused, one-at-a-time bug fixing with deep verification. Hardened for 7-Hour Autonomous Sentry Mode (v3.9.5.1).
---
// turbo-all

0. **Sentry Initialization Phase (v3.9.5.1)**:
   - **0.1. Mode Selection**: Prompt the USER:
     - "A) Standard Deep Run (Single target)?"
     - "B) Sentry Mode (Multi-bug; autonomous loop)?"
   - **0.2. Duration Input**: If Sentry Mode: "How many hours should the Sentry run?" (Default 7h).
   - **0.3. Persistence Start**: Launch [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh) (`caffeinate`).
   - **0.4. Session Clock**: Initialize `SENTRY_END_TIME` = `NOW + Duration`.

1. **Identification Phase**
   - Read [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md).
   - Extract all items marked with `[X]` or `[ ]`.
   - **Target Selection**:
     - **Standard Mode**: Present list and ask.
     - **Sentry Mode**: Automatically select the first non-deferred item.

2. **Test Case Validation**
   - Confirm reproducing steps, wanted result, and meaning.
   - If missing: **Mark as `[-]` and MOVE TO NEXT TARGET** (Sentry Mode) or prompt user (Standard Mode).

3. **Session Preparation**
   - Run [/backup](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/backup.md).
   - Run [/sync](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/sync.md).
   - Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) (Tier 1 Recovery).

4. **Deep Fix & Test Execution [ABSOLUTE_VERIFICATION]**
   - **(1) Research [TRIO-PATH]**: Identify root cause + 3 distinct fix paths.
   - **(2) Test Route Planning**: Document steps in `test/deep_analysis/[TASK_ID]_route.md`.
   - **(3) Execute**: Apply best fix.
   - **(4) Rebuild & Deploy**: [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md).
   - **(5) Absolute Test**: [/deep_test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/deep_test.md).
   - **(6) Iterate [CAP=4]**:
     - If fail after 4 loops: **Mark as `[F]` and check Recursion Gate**.
   - **Recovery Phase (Tiered)**:
     - If build/install fails:
       - **Easy Resolve**: `adb kill-server` + Restart.
       - **Deeper Resolve**: Full Cold-Boot Restart of the AVD.

5. **Cycle Closure**
   - Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md).
   - Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md).
   - Git Commit: `[V3.9.5.1-SENTRY] SUCCESS: [Task ID]`.

6. **Sentry Recursion Gate**:
   - If Sentry Mode AND `NOW < SENTRY_END_TIME`:
     - Clear timers and **Loop to Step 1**.
   - Else:
     - Teardown: Stop [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh).
     - Final session summary report.
