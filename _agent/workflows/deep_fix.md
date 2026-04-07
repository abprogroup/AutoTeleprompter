---
description: Surgical autonomous fixing for [X] items with Deep Verification.
---
// turbo-all

1. **Phase 1: Deep Research (30 min)**
   - **Start**: Run `_agent/scripts/task_timer.sh start deep_research 30`.
   - Perform comprehensive root cause analysis.
   - Trace state management, lifecycle hooks, and cross-widget dependencies.
   - Identify all potential failure points related to the bug.

2. **Phase 2: Planning & Method Selection (15 min)**
   - **Start**: Run `_agent/scripts/task_timer.sh start deep_planning 15`.
   - Outline at least 2 potential fixing methods.
   - Analyze pros/cons for each method in terms of project stability.
   - **Choose**: Select the best surgical method.

3. **Phase 3: Execution (15 min)**
   - **Start**: Run `_agent/scripts/task_timer.sh start deep_execution 15`.
   - Apply the chosen FIX using `replace_file_content` or `multi_replace_file_content`.
   - Ensure the fix adheres to [AI_PROTOCOL.md](file:///Users/proapple/Desktop/AutoTeleprompter/AI_PROTOCOL.md) (e.g., dual-backups).

4. **Interim Consistency Check**
   - Verify code compiles and no obvious regressions were introduced during the fix itself.
