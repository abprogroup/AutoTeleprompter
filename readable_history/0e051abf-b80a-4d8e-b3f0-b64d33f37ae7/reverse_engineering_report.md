# Styling Engine Reverse-Engineering Report (v3.9.5.7)

I have performed a deep-dive into the current codebase to identify why regressions (Blinks/Overflow/Stacking) occurred and how to finalize the "Perfect" implementation.

## 1. The Rendering Pipeline (`_MarkupController`)
- **Mechanism**: Uses a recursive `_buildMarkup` parser with a flat `_markupRegex`.
- **Flaw**: Because it's flat, overlapping tags (e.g., `[color]**Bold[/color]**`) can cause parsing loops or "masking" where the bold state isn't correctly inherited by the color block.
- **Perfect Fix**: Ensure `StylingService` only allows "Well-Formed" tags where internal tags are fully contained within parent tags.

## 2. Style Detection Logic (`_onSelectionChanged`)
- **Mechanism**: Every cursor movement triggers a full scan of the text buffer to find tags surrounding the cursor.
- **Flaw**: Triggers `setState` on every pixel of cursor movement. This causes the UI to re-render the entire editor, leading to "Heavy Keyboard" and "Selection Blinking."
- **Perfect Fix**: Detach Style Detection from the main UI thread. Use a `ValueNotifier` or a more granular provider that only updates the Toolbar, NOT the whole Editor.

## 3. Persistence & Auto-Save (`_startAutoSave`)
- **Mechanism**: A 30-second timer forces a save to `settingsProvider`.
- **Flaw**: `settingsProvider` notifies all listeners. Since `ScriptEditorScreen` watches this provider for background/spacing settings, it rebuilds the entire widget tree, causing the "30s Blink."
- **Perfect Fix**: Implement a `PersistentNotifier` that allows "Silent Saves" (writing to disk without notifying UI listeners).

## 4. Layout Scaling (`_EditorBlock`)
- **Mechanism**: Uses a fixed `height` multiplier (1.2) for TextFields.
- **Flaw**: At 100px+ font sizes, the standard 1.2 height is insufficient for characters with descenders (g, j, y), leading to row overlap and collision.
- **Perfect Fix**: Proportional scaling (1.5x) and `contentPadding` buffers to ensure vertical isolation between paragraphs.

## 5. Collision & Stacking (`StylingService`)
- **Mechanism**: `wrapWithStyle` handles mutual exclusivity.
- **Flaw**: Currently only purges *inner* tags. If a selection partially overlaps an *outer* tag, it creates raw markup leaks.
- **Perfect Fix**: Implement "Boundary Intelligence" — if a selection touches a tag boundary, it must either expand to include the tag or shrink to avoid breaking it.
