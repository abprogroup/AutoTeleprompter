# Implementation Plan - Phase 1.6: Style-Triggered Persistence

We will ensure that styling changes (Font Size, Spacing, Colors) are treated as "First Class Citizens" in the history and auto-save system.

## User Review Required

> [!IMPORTANT]
> - **Formatting History**: Changing the font size or spacing will now create an "Undo" point. If you accidentally make the text too large or small, you can simply click **Undo** to revert back.
> - **Immediate Auto-save**: Any styling change will trigger a fast background save (500ms debounce), ensuring that even if you close the app immediately after changing the font, it will be preserved.

## Proposed Changes

### Script Editor Screen
#### [MODIFY] [script_editor_screen.dart](file:///Users/proapple/Desktop/AutoTeleprompter/AutoTeleprompter/lib/features/script/widgets/script_editor_screen.dart)
- **Implement Settings Listener**: Add `ref.listen(settingsProvider, ...)` in the `build` method.
- **Detect Styling Drifts**: Compare current settings with the latest history state.
- **Trigger History Push**: If a drift is detected, call `_saveHistory(description: 'Update Styling', debounce: true)`.
- **Harden `_saveHistory`**: Add a call to `_scheduleRecentUpdate()` at the end of `_saveHistory` to ensure all history changes are committed to `SharedPreferences` within 500ms.

---

## Verification Plan
1. **Style History Test**:
   - Open a script.
   - Change Font Size from 18px to **48px**.
   - Verify that the **Undo** button becomes active.
   - Reopen the script from Recent Activity and verify it remains at **48px**.
2. **Bulk Consistency Test**:
   - Change Font Size, then Line Spacing, then Text Alignment.
   - Verify that you can "Undo" each of these specific styling steps individually.

> [!NOTE]
> This completes the "Live Document" behavior where every interaction—not just typing—is respected and protected.
