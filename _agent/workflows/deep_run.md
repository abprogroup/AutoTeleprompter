---
description: Redefined autonomous loop for focused, one-at-a-time bug fixing with deep verification. Hardened for 7-Hour Autonomous Sentry Mode (v3.9.5.1).
---
// turbo-all

0. **Sentry Initialization Phase (New v3.9.5.1)**:
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
     - **Standard Mode**: Present the list to the USER and ask for focus.
     - **Sentry Mode**: Automatically select the first non-deferred item from the priority list.

2. **Test Case Validation**
   - Check if the selected bug has complete documentation:
     - **1. -> 2. -> 3.** (Reproducing steps).
     - **\*Wanted Result\***: (Target outcome).
     - **\*Meaning\***: (Reasoning behind the failure).
   - If NOT complete (In Sentry Mode): Mark as `[-]` (Deferred; Missing Info) and move to next target.
   - If NOT complete (In Standard Mode): Prompt USER for details.

3. **Session Preparation**
   - Run [/backup](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/backup.md) (Full Snapshot).
   - Run [/sync](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/sync.md) to align rules.
   - Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) for a fresh clean session.

4. **Deep Fix & Test Execution [ABSOLUTE_VERIFICATION]**
   - The AI must autonomously iterate through:
     - (1) **Research [TRIO-PATH]**: Identify root cause + collect at least **THREE (3) distinct optional fix paths** before coding.
     - (2) **Test Route Planning**: Document steps in `test/deep_analysis/[TASK_ID]_route.md`.
     - (3) **Execute**: Apply best fix from the Trio.
     - (4) **[MANDATORY] Rebuild**: Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md).
     - (5) **Absolute Test**: Execute [/deep_test](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/deep_test.md).
     - (6) **Iterate [CAP=4]**: Maximum 4 autonomous loops.
   - **Recovery**: If a bug fails after Cap=4: Mark as `[F]` (Failed) and check recursion gate.

5. **Cycle Closure**
   - Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md).
   - Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md) (Terminal Sync).
   - Final Git Commit: Commit results to the repository.

6. **Sentry Recursion Gate (New v3.9.5.1)**:
   - If Sentry Mode is active AND `NOW < SENTRY_END_TIME`:
     - Clear the [Task Timer](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/task_timer.sh).
     - **Recurse to Step 1** (Target Selection for the next bug).
   - Else:
     - **Teardown**: Stop [Persistence Guard](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/persistence_guard.sh).
     - Provide a full session summary of all bugs addressed.

---
> [!IMPORTANT]
> **[Persistence Guard]**: Ensures the Mac stays awake during 7-hour autonomous sessions.
