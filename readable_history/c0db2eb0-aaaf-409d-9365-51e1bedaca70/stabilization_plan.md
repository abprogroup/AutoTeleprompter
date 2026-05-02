# Windows Build Fix & iOS Keyboard stabilization

## Problem Statement
1. **Windows Build Failure**: Recent manual and automated edits to `teleprompter_provider.dart` have introduced syntax errors (mismatched braces and missing indentation) that prevent compilation.
2. **iOS Editor Keyboard**: On newer iPhone models, the keyboard remains open even when editing is presumed finished.
3. **iOS Presentation Keyboard**: Adjusting the font size in the presentation settings panel triggers the keyboard to open, which disrupts the teleprompter flow.

## Proposed Changes

### [Component] Teleprompter Provider
#### [MODIFY] [teleprompter_provider.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart)
- [ ] Fix syntax errors in `_setupSttCallbacks`. Ensure all callbacks (`onResult`, `onStatusChange`, `onError`, `onLanguageUnavailable`, `onSoundLevelChange`, `onDiagnostic`) are correctly nested within the method.
- [ ] Fix indentation for better readability and to avoid future closure bugs.

### [Component] Script Editor (iOS stabilization)
#### [MODIFY] [script_editor_screen.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/script/widgets/script_editor_screen.dart)
- [ ] Ensure `TextField` has `onEditingComplete` or `onSubmitted` handlers that call `FocusScope.of(context).unfocus()`.
- [ ] Add a global tap gesture recognizer to the editor scaffold that dismisses the keyboard if tapping outside the text area.

### [Component] Teleprompter UI (Keyboard prevention)
#### [MODIFY] [teleprompter_screen.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart)
- [ ] Explicitly call `FocusScope.of(context).unfocus()` when opening the `TeleprompterSettingsPanel`.
- [ ] Ensure the font size adjustment buttons/sliders in the settings panel do not use focusable hit-testing that might trigger the OS keyboard.

## Verification Plan
1. **Windows Build**: Trigger a new GitHub push and verify that the "Build Windows" job completes successfully.
2. **iOS Manual Check**:
   - Open editor, verify keyboard closes when done.
   - Open presentation mode, adjust font size, verify keyboard NEVER appears.
