# Build Stabilization & iOS Keyboard UX Fixes

## Problem Statement
1. **Windows Build Failure**: Commit `v4.1.8` introduced a syntax error in `teleprompter_provider.dart` (brace mismatch) which broke the Windows CI pipeline.
2. **iOS Keyboard Desync**:
    - The editor keyboard is sticky on newer iPhone models.
    - The keyboard opens unexpectedly in presentation mode during settings adjustment.
    - The "PRESENT" button is often hidden behind the keyboard, preventing a "start" workaround in some orientations.

## Proposed Changes

### [Component] Teleprompter State (Shared)
#### [MODIFY] [teleprompter_provider.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart)
- [ ] **Surgical Syntax Repair**: Re-align and correctly close the `_setupSttCallbacks` method to unblock the Windows/iOS build pipelines.

### [Component] Script Editor (iOS Optimization)
#### [MODIFY] [script_editor_screen.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/script/widgets/script_editor_screen.dart)
- [ ] **Global Dismissal**: Wrap the Scaffold in a `GestureDetector(onTap: unfocus)` so tapping outside text blocks hides the keyboard.
- [ ] **Keyboard-Aware Button**: Wrap the bottom "PRESENT" container in a dynamic padding that uses `MediaQuery.of(context).viewInsets.bottom`. This will lift the "PRESENT" button above the keyboard if it stays open.

### [Component] Presentation Mode (Focus Prevention)
#### [MODIFY] [teleprompter_screen.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart)
- [ ] **Forced Unfocus**: Explicitly call `FocusManager.instance.primaryFocus?.unfocus()` when opening the Settings drawer.
- [ ] **Focus Lockdown**: Ensure settings sliders and buttons explicitly do not request or accept focus that might trigger the OS keyboard.

## Verification Plan

### Automated Checks
- Verify `flutter analyze` passes on all modified files to ensure no syntax regressions.

### Manual Verification (User)
1. **Editor Test**: Open the script editor on device. Tap outside the paragraphs. Verify keyboard closes.
2. **"Floating" Button**: Keep the keyboard open (e.g., by staying in a block). Verify the "PRESENT" button is visible above the keyboard and clickable.
3. **Presentation Test**: In presentation mode, adjust font size. Verify keyboard DOES NOT open.
