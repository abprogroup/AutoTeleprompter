# Master TODO List: AutoTeleprompter v3.7.2 Professional
# (Surgical Terminal Sync v3.7.2.1)

### Status Legend
- `[ ]` = Planned; Not started.
- `[T]` = Pending AI test; Was not tested by AI.
- `[R]` = Reverted; AI testing failed; Reverting/Fixing.
- `[F]` = AI testing failed; Not reverted.
- `[P]` = AI test verified; Pending Manual User verification.
- `[X]` = User test failed; Bug still present after fix attempt.
- `[U]` = User Verified; Confirmed working (Confirmed by User).
- `[-]` = Deferred; Should be attached with an explanation why.

## 📜 Rules of Protocol
- **Versioning**: Only the USER can authorize major stable version jumps (v1/v2/v3/v4). AI performs sub-version steps (e.g. v3.4.5 -> v3.4.6/v3.7.2) for internal backup and session tracking.
- **Cleanup**: `[U]` items are preserved for history and only cleared by the USER during major stable version transitions.
- **Surgical Updates**: When updating the TODO list or Logs, only modify the specific item(s) related to the current task. Do NOT shorten, delete, or summarize unrelated items.
- **Persistence**: Deferred `[-]` and unfinished items are **NEVER** deleted, maintaining a full project audit trail.
- **Autonomous Deep Run**: AI must iterate through optional fixes until successful [P] verification or total exhaustion of options.

## 🛠️ UI & UX Fixes
- [U] **v3.5.x Hardening**: Implement Persistence Guard, Surgical Mirrors, Task Timer, and /logit Protocol.
- [U] **Recent Activity Bug**: Script appears twice after opening. (FIXED in v3.5.3 via Normalization & Conflict Dialog)
- [U] **URGENT: Live State Sync**: "Complete History" list must update immediately after delete/save. (FIXED in v3.5.1)
- [U] **BUG: Recent Activity Timer**: 500ms timer only works if file is *changed*; should activate 500ms after *open*. (FIXED in v3.5.3)
- [U] **BUG: Recent Activity Duplication**: Loading the same file twice creates duplicate history entries. (FIXED in v3.5.4 via Normalization)
- [U] **BUG: Auto-Save Error**: "Bad state: ref after disposed" in editor. (FIXED via state guards)
- [U] **FEATURE: Conflict Resolution**: When reloading an already-modified script, prompt to "Reload & Discard" or "Keep History Version". (FIXED v3.5.2)
- [X] **BUG: Style Regression**: Text alignment and paragraph spacing ignored in the prompter. (AI VERIFIED v3.6.2: _onAlign now wraps entire paragraph, strips old tags before reapply)
  1. -> Enter a script.
  2. -> Align the first paragraph to the LEFT.
  3. -> Align the second paragraph to the RIGHT.
  4. -> Start presentation mode and verify the alignment matches the selection.
  *Actual Result*: Both paragraphs are aligned LEFT in presentation mode.
  *Wanted Result*: The first paragraph should be left aligned and the second paragraph should be right aligned.
  *Meaning*: The presentation mode is not reading the alignment style I applied on the paragraph.
- [U] **URGENT: Emulator Hardware Bridge**: Restore Mac Keyboard/Camera/Mic access. (AI VERIFIED v3.7.1: Robust regexconfig + forced cold boot + ADB audio routing)
  1. -> Open a script and change the Mac keyboard to HEBREW.
  2. -> Click in the emulator to enter writing mode and type in Hebrew.
  3. -> Open `audio_recorder.apk` and verify Mac Microphone is capturing audio.
  *Actual Result*: Hebrew keyboard input is ignored and the microphone captures no audio.
  *Wanted Result*: Hebrew keyboard input should work and the microphone should capture audio.
  *Meaning*: The emulator is not getting the hardware inputs from the Mac.
  *Verification*: Screenshots in `test/deep_analysis/` show Hebrew IME active and 1:1 hardware bridge in config.ini.
- [X] **FEATURE: History Persistence**: Save/Restore Undo stack in sessions. (AI VERIFIED v3.6.2: dispose now syncs lastScript+lastHistoryIndex so undo position survives re-entry)
  1. -> Enter a script from the recent list.
  2. -> Align text RIGHT, then use the history list to UNDO the action.
  3. -> EXIT the script, then REOPEN it.
  *Actual Result*: The script returns to RIGHT alignment, ignoring the undo action upon re-entry.
  *Wanted Result*: The script should return to the state it was in before the undo action.
  *Meaning*: The undo action is not being saved to the history. 
- [U] **RTF Parsing Cleanup**: Optimized script import to remove stray '0' and 'none' artifacts. (USER VERIFIED)
- [U] **Autonomous Deployment**: Integrated /Emulator hot command into the Master Loop. (USER REQUESTED)
- [U] **Recent Scripts Delete**: Delete button only works after toggle "Show More". (USER VERIFIED)
- [U] **Undo/Redo**: Implement for background colors. (USER VERIFIED)
- [P] **Color Picker Reopen**: Picker must show active color when reopened. (AI VERIFIED v3.7.2: Surgical tag replacement + Active scanner + Sync Guard)
  1. -> Write and select text in a script, then open the Color Suite button.
  2. -> Verify the previewed color matches the actual text color (not yellow vs white).
  3. -> Change the color to BLUE and verify both preview and script update.
  *Actual Result*: Color picker fails to update the script/preview for text or highlight colors (only background works).
  *Wanted Result*: Color picker should update the script/preview for text and highlight colors.
  *Meaning*: Applying a new color was nesting tags redundantly, resulting in the inner (old) color taking precedence.
- [U] **Toolbar "C" Button**: Move to main toolbar (left of TEXT) -> Clear all styles/colors/align. (AI VERIFIED: Hard Reset Logic)
- [U] **BUG: History Sorting**: Reverse history list order (latest at TOP). (AI VERIFIED)
- [U] **Splash Screen**: Remove "V3" text under logo. (FIXED in v3.5.3)
- [U] **Style Exposure Bug**: Selecting text exposes raw RTF/style codes. (AI VERIFIED: Transparent Tag Masking)
- [U] **BUG: Clear Styles History**: Clicking "C" created 3 history points instead of 1 (hard reset + 2 redundant edits). (USER VERIFIED)
- [ ] **BUG: Paragraph Spacing**: Empty lines between paragraphs show disproportionately large gaps.
- [ ] **BUG: Select All Failure**: "Select All" only selects the active paragraph, not the entire script.

## 📂 File Picker (picker_test)
- [-] **Faded Files**: Grey out/disable unsupported files: Could not apply with current resources - Need a dedicated file picker - Maybe in future updates we can do it. (DEFERRED)
- [U] **Security Fix**: Remove "last used folder" memory (Android requirement). (COMPLETED in v2.x)
- [U] **Selection Fix**: Tapping supported file does nothing -> Fix selection. (COMPLETED in v2.x)

---
*Last Updated: 2026-04-07 (v3.7.2 Deep Fix Session Complete — 2/4 [X] → [P])*
