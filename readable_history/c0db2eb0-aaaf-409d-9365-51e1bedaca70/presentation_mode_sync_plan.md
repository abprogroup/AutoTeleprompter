# Presentation Mode Synchronization & Spacing Hardening

## Problem Statement
1. **Spacing Desync**: The editor handles line spacing as a relative offset (showing 0.0 by default) while the presentation mode shows the raw multiplier (1.2). Additionally, negative scaling for word, letter, and line spacing is currently restricted or inconsistent between the two modes.
2. **Upcoming Text Highlight**: Users want a way to override manual background highlights in presentation mode for text that hasn't been read yet, similar to how "Upcoming Text Color" works.

## Proposed Changes

### [Component] AppSettings & State Management
#### [MODIFY] [settings_provider.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/settings/providers/settings_provider.dart)
- [ ] Add `showUpcomingWordHighlight` (bool, default: `false`).
- [ ] Add `upcomingWordHighlightColor` (int, default: `0x00000000` / transparent).
- [ ] Change `lineSpacing` default from `1.2` to `0.0` (treating it as an offset from a base of `1.2`).
- [ ] Update `setLineSpacing`, `setWordSpacing`, and `setLetterSpacing` to support wider ranges (including negative values down to -1.0 for line spacing).
- [ ] Add a helper getter `effectiveLineHeight => 1.2 + lineSpacing`.

### [Component] Editor UI
#### [MODIFY] [layout_suite_mvp.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/script/widgets/editor/suites/layout_suite_mvp.dart)
- [ ] Adjust Line Spacing slider: `min: -1.0, max: 2.0` (with 0.1 divisions).
- [ ] Ensure Letter/Word spacing sliders support the expanded negative ranges requested by the user.

### [Component] Teleprompter Rendering
#### [MODIFY] [teleprompter_screen.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart)
- [ ] **Highlight Override Logic**: 
  - Update `effectiveBg` calculation to check `settings.showUpcomingWordHighlight`.
  - If `true`, upcoming words use `settings.upcomingWordHighlightColor` instead of the manual tag highlight.
- [ ] **Spacing Sync**:
  - Update `TextStyle` to use `height: settings.effectiveLineHeight`.
  - Ensure the paragraph bottom padding also uses the synchronized spacing logic.
- [ ] **Settings Panel**:
  - Add a "Upcoming Text Highlight" Switch.
  - Add a color grid for the upcoming highlight color (visible only when the switch is ON).
  - Synchronize all spacing sliders with the expanded ranges.

## Verification Plan
1. **Editor Check**: Open layout suite, verify Line Spacing starts at 0.0. Move to -1.0 and verify text gets tighter.
2. **Presentation Sync**: Open presentation mode.
   - Verify line spacing matches the editor visually.
   - Verify the settings panel shows the same numeric values (0.0 default).
3. **Upcoming Highlight Feature**:
   - Style a word with a RED background in the editor.
   - Start prompter. Verify the word has a RED background.
   - Toggle "Upcoming Text Highlight" ON and set color to Transparent (or another color).
   - Verify the RED highlight is overridden for future words.
   - Advance the marker past that word and verify its background (red) optionally returns with reduced opacity (existing behavior) or follows new rules.

> [!IMPORTANT]
> Since `lineSpacing` storage is changing from raw `1.2` to offset `0.0`, current user settings might look loose (1.2 becomes 1.2+1.2=2.4) unless I add a micro-migration in `_load()`. I will implement a migration check to detect if `lineSpacing >= 1.0` and subtract 1.2 once.
