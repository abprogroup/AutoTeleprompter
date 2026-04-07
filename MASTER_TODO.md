# Master TODO List: AutoTeleprompter v3.7.1 Protocol

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
- **Versioning**: Only the USER can authorize major stable version jumps (v1/v2/v3/v4). AI performs sub-version steps (e.g. v3.4.5 -> v3.4.6/v3.7.1) for internal backup and session tracking.
- **Cleanup**: `[U]` items are preserved for history and only cleared by the USER during major stable version transitions.
- **Persistence**: Deferred `[-]` and unfinished items are **NEVER** deleted, maintaining a full project audit trail.

## ��️ UI & UX Fixes
- [U] **v3.5.x Hardening**: Implement Persistence Guard, Surgical Mirrors, Task Timer, and /logit Protocol.
- [U] **Recent Activity Bug**: Script appears twice after opening. (v3.5.3)
- [U] **URGENT: Live State Sync**: "Complete History" list must update immediately. (v3.5.1)
- [U] **BUG: Recent Activity Timer**: 500ms after open. (v3.5.3)
- [U] **BUG: Recent Activity Duplication**: (v3.5.4)
- [U] **BUG: Auto-Save Error**: "Bad state: ref after disposed".
- [U] **FEATURE: Conflict Resolution**: Dialog on import. (v3.5.2)
- [X] **BUG: Style Regression**: Text alignment and paragraph spacing ignored in the prompter. (AI VERIFIED v3.6.2)
  1. -> Enter a script.
  2. -> Align the first paragraph to the LEFT.
  3. -> Align the second paragraph to the RIGHT.
  4. -> Start presentation mode and verify the alignment.
  *Actual Result*: Both paragraphs are aligned LEFT in presentation mode.
  *Wanted Result*: First Left, Second Right. 
- [P] **URGENT: Emulator Hardware Bridge**: Restore Mac Keyboard/Camera/Mic access. (AI VERIFIED v3.7.1: Robust regexconfig + forced cold boot + ADB audio routing)
  1. -> Open a script and change the Mac keyboard to HEBREW.
  2. -> Click in the emulator to enter writing mode and type in Hebrew.
  3. -> Open `audio_recorder.apk` and verify Mac Microphone is capturing audio.
  *Actual Result*: Hebrew keyboard input is ignored and Mic capture fails.
  *Verification*: Screenshots in `test/deep_analysis/` show Hebrew IME active and 1:1 hardware bridge in config.ini.
- [X] **FEATURE: History Persistence**: Save/Restore Undo stack in sessions. (AI VERIFIED v3.6.2)
  1. -> Enter a script from the recent list.
  2. -> Align text RIGHT, then use the history list to UNDO.
  3. -> EXIT the script, then REOPEN it.
  *Actual Result*: RIGHT alignment returns, ignoring undo upon re-entry.
- [U] **RTF Parsing Cleanup**: Optimized script import.
- [U] **Autonomous Deployment**: Integrated /Emulator command.
- [U] **Recent Scripts Delete**: Toggle "Show More" bug.
- [U] **Undo/Redo**: Implement for background colors.
- [X] **Color Picker Reopen**: Picker must show active color when reopened. (AI VERIFIED v3.6.2)
  1. -> Write and select text in a script, then open the Color Suite button.
  2. -> Verify the previewed color matches the actual text color.
  *Actual Result*: Color picker fails to update preview for text or highlight.
- [U] **Toolbar "C" Button**: Hard Reset Logic.
- [U] **BUG: History Sorting**: Reverse history list order.
- [U] **Splash Screen**: Remove "V3" text.
- [U] **Style Exposure Bug**: Selecting text exposes raw RTF/style codes.
- [U] **BUG: Clear Styles History**: Redundant 3 entries on "C" click.
- [ ] **BUG: Paragraph Spacing**: Empty lines between paragraphs show disproportionately large gaps.
- [ ] **BUG: Select All Failure**: "Select All" only selects the active paragraph.

## 📂 File Picker (picker_test)
- [-] **Faded Files**: Grey out unsupported files. (DEFERRED)
- [U] **Security Fix**: Remove "last used folder" memory.
- [U] **Selection Fix**: Tapping supported file selection.

---
*Last Updated: 2026-04-07 (v3.7.1 Deep Fix Session Complete — 1/4 [X] → [P])*
