---
description: Surgical autonomous fixing for [X] items with Deep Verification.
---
// turbo-all

1. **Absolute Test Setup**
   - Create folder: `test/deep_analysis/[TASK_ID]/`.
   - Read the **Test Route**: `test/deep_analysis/[TASK_ID]_route.md`.
   - Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) to ensure a full fresh rebuild is active.

2. **Test Route Execution**
   - Follow the **exact steps** from the Test Route one-by-one.
   - For EACH step:
     a. **Action**: Perform in emulator via `uiautomator dump` + `input tap`.
     b. **Proof**: Capture screenshot (`screencap`).
     c. **Vision Analysis**: Verify the state matches the "Wanted Result".
     d. **Universal Mandates**:
        - **Deselection Proof**: Screenshot MUST show the fix without active handles.
        - **State Sync Proof**: Re-trigger the UI (e.g., reopen menu) to prove choice survived.

3. **Autonomous Verification Verdict**
   - If 100% of Route steps Pass:
     - Promoted: Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) item to `[P]`.
   - If ANY Route step Fails:
     - Reverted: Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) item to `[R]`.
     - Revert code changes immediately.

4. **Visual Proof Delivery**
   - Present ALL proofs from the Route in the final report.
