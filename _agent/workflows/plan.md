---
description: Prioritizes and plans the next fix from the MASTER_TODO.md.
---
1. **Safety Guard**: Execute `./_agent/scripts/task_timer.sh check`. **STOP** if failure.
2. **Target Selection**: If part of an `/run` amount selection, use the selected task. Otherwise, select the most urgent item from [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md).
3. **Professional Reflection**: Answer:
    - **The Fix**: How precisely do I plan to solve this?
    - **Smart Logic**: Is this the most professional way for *this* project?
    - **Weight**: Is it lightweight and fast?
    - **Parity**: Is it cross-platform safe (Android/iOS/macOS)?
4. **Output**: Create an `implementation_plan.md` with these professional reflections.

---
*Command: /plan*
