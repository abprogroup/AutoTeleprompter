---
description: Autonomous verified state tracking for pending v3.6 AI tests.
---
// turbo-all

1. Locate the Project Governance File
   - Read [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md).

2. Identify Pending Tests
   - Extract all lines starting with `[T]`.
   - If no `[T]` items exist, report "No pending AI tests found." and stop.

3. Execute Autonomous Verification
   - For each item found:
     a. Determine the relevant code or manifest file.
     b. Perform a deep logic check using `view_file` or a technical diagnostic (e.g. `flutter test`, `ls`, `grep`).
     c. If the item is a UI fix, simulate the rendering logic or check the Widget properties/mapping.

4. Record Internal Verification Results
   - Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) based on results:
     - SUCCESS: Change `[T]` → `[P]` (AI test verified; Pending Manual User verification).
     - FAILURE: Change `[T]` → `[R]` (Reverted; AI testing failed; Reverting/Fixing).

5. Update Global Documentation
   - Run `/logit` to ensure the session logs and Task Tracker are synchronized.
   - Summarize the results (P vs R counts) for the USER.
