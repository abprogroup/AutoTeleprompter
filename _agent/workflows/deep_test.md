---
description: Surgical autonomous fixing for [X] items with Deep Verification.
---
// turbo-all

1. **Setup dedicated test environment**
   - Create folder in `test/deep_analysis/<bug_name>`.
   - Run [/emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) to ensure a fresh session.

2. **Step-by-Step Visual Verification**
   - Read the documented test steps (1. -> 2. -> 3.) from [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md).
   - **Loop through EACH step**:
     a. **Execute**: Perform the action in the emulator.
     b. **Capture**: Take a screenshot.
     c. **Verify**: Use the vision tool to visually verify the step was successful (compare with expected result).
     d. **Save**: Store the image in the dedicated bug folder under `test/deep_analysis/<bug_name>/`.

3. **Status Promotion & Log Generation**
   - If ALL steps pass:
     - SUCCESS: Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md) item from `[X]` to `[P]` (AI Verified).
   - If ANY step fails:
     - FAIL: Change `[X]` to `[R]` (Reverted) and undo the fix immediately.

4. **Detailed Verification Report**
   - Present the captured screenshots and the visual verification findings to the USER.
