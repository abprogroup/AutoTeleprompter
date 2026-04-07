---
description: Surgical autonomous fixing for [X] items with Deep Verification.
---
// turbo-all

1. Identify Failed Items
   - Read [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md).
   - Extract all lines starting with `[X]`.

2. Analyze Core Failure
   - Cross-reference the [X] description with recent screenshots and the [walkthrough.md](file:///Users/proapple/.gemini/antigravity/brain/4c7c9f5a-6d49-4b0e-8f22-efed4d0feb44/walkthrough.md).

3. Surgical Fix & Deep Verification
   - For each [X] item:
     a. Apply the FIX using `multi_replace_file_content`.
     b. Perform **Deep Logic Verification**:
        - Auditing property mapping (e.g. `isRtl` ⇔ `WrapAlignment`).
        - Verifying state preservation across widget lifecycles.
     c. Perform **Regression Audit**:
        - Check if the fix broke related features (e.g. does "Clear All" accidentally delete the script title?).

4. Record & Revert Policy
   - Update [MASTER_TODO.md](file:///Users/proapple/Desktop/AutoTeleprompter/MASTER_TODO.md):
     - SUCCESS: Change `[X]` → `[P]` (AI Verified).
     - FAIL/REGRESSION: Change `[X]` → `[R]` and UNDO the code changes to return the file to the last [X] state.

5. **Final Report & Cleanup**
   - Run [/organize](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/organize.md) to clear cache/temp files.
   - Run [/logit](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/logit.md) to sync TODOs and Logs.
   - Run [/Emulator](file:///Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/emulator.md) to provide a clean APK for manual test.
   - Summarize the "P vs R" results for the USER.
