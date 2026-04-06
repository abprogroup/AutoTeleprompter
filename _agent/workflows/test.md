---
description: Verifies that the recent fix works correctly and hasn't introduced regressions.
---
# /test Workflow

1. **Safety Phase**:
// turbo
   1.1. Run [Safety Guard (Timer)](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/scripts/task_timer.sh) check.

2. **Verification Phase**: Execute the specific verification command (e.g., `flutter analyze` or `flutter test`).

3. **Success Branch**:
// turbo
   3.1. **Documentation Audit**: Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md) to synchronize all documentation.
// turbo
   3.2. Automated Versioning: `git add . && git commit -m "[V3-SYNC] <brief description>"`
// turbo
   3.3. Clear Timer: `./_agent/scripts/task_timer.sh clear`

4. **Failure Branch**: Document findings in `AI_PROPOSAL.md`.
