# Internal Guide: The Flawless Styling Engine (v3.9.5.7)

This guide serves as the ultimate "Step-by-Step" protocol to ensure no regressions and 100% MS Office parity.

## Stage 1: The Core Logic (StylingService)

### Rule 1: Aggressive Mutual Exclusivity
- When applying a "Singleton" style (Color, Font, Size, Align), NEVER allow a previous tag of the same type to persist within or *around* the selection.
- **Protocol**: 
  1. Scan for outer tags. If selection is fully contained, strip outer tags and re-apply specifically to the selection.
  2. Scan for inner tags. Strip all.
  3. Apply new tag.

### Rule 2: Baseline Revert (The "Left" Rule)
- For Alignment and Direction, if the user applies the *default* (Left/LTR) to an already styled block, the engine must REMOVE all tags. It should never result in `[left]text[/left]`.

## Stage 2: Interaction Stability (The "Zero-Blink" Rule)

### Rule 3: Granular Selection Detection
- **Protocol**: 
  1. `_onSelectionChanged` must only update the `cursorStyleProvider`.
  2. REMOVE `setState()` from `_onSelectionChanged`. 
  3. Moving the cursor should NEVER trigger a rebuild of the `_EditorBlock` list.

### Rule 4: Silent Persistence (Auto-Save)
- **Protocol**: 
  1. Auto-save must use `isSilent: true` in `saveScript`.
  2. The `settingsProvider` must have a `silentlyUpdateRecent` method that writes to `SharedPreferences` but does NOT call `notifyListeners()`. 
  3. This ensures the 30s timer triggers ZERO UI changes.

## Stage 3: Professional History (The "Bulking" Rule)

### Rule 5: State Deduplication
- **Protocol**: 
  1. Before adding to `_history`, check if `currentText == lastHistoryText`.
  2. If identical, abort save.

### Rule 6: Suite Session Registry
- **Protocol**: 
  1. Upon `_toggleSuite(suiteName)`, capture `_suiteSnapshot`.
  2. During suite activity, only set `_isSuiteDirty = true`.
  3. DO NOT save history for every click (Bold, then Italic). 
  4. Only upon `_toggleSuite(none)` or `_commitSuiteHistory()`, save ONE entry: `[TEXT SUITE UPDATE]`.

## Stage 4: Visual Integrity (Line Scaling)

### Rule 7: Proportional Spacing
- **Protocol**: 
  1. `height` = `1.5 + (lineSpacing - 1.0)`.
  2. `contentPadding` = `EdgeInsets.fromLTRB(8, 12, 8, 16)`.
  3. This ensures that even at 150px Font Size, the text remains vertically isolated and readable.
