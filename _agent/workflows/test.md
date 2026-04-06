---
description: Verifies that the recent fix works correctly and hasn't introduced regressions.
---
1. **Safety Guard**: Execute `./_agent/scripts/task_timer.sh check`. **STOP** if failure.
2. **Analysis**: Run `/Users/proapple/development/flutter/bin/flutter analyze`.
3. **Internal Test**: If applicable, run `/Users/proapple/development/flutter/bin/flutter test`.
4. **Failure Recovery (MANDATORY)**: If any command fails:
    - **DO NOT** update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) to `[x]`.
    - **ACTION**: Create [development/AI_PROPOSAL.md](file:///Users/proapple/Desktop/AutoTeleprompter/development/AI_PROPOSAL.md) explaining failure.
    - **STOP**: Terminate the `/run` loop immediately.
5. **Success Branch**: Only if the analysis/tests pass:
    - **GIT**: Run `git add .` and `git commit -m "[V3-FIX] {Brief Task Summary}"`.
    - **LOG**: Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) and [development/PROJECT_RECORDS.md](file:///Users/proapple/Desktop/AutoTeleprompter/development/PROJECT_RECORDS.md).
    - **TIMER**: Run `./_agent/scripts/task_timer.sh clear`.

---
*Command: /test*
