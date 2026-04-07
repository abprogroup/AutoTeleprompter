# Master TODO List: AutoTeleprompter v3.6 Protocol

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
- **Versioning**: Only the USER can authorize major stable version jumps (v1/v2/v3/v4). AI performs sub-version steps (e.g. v3.4.5 -> v3.4.6) for internal backup and session tracking.
- **Cleanup**: `[U]` items are preserved for history and only cleared by the USER during major stable version transitions.
- **Persistence**: Deferred `[-]` and unfinished items are **NEVER** deleted, maintaining a full project audit trail.

## 🛠️ UI & UX Fixes
- [U] **v3.5.x Hardening**: Implement Persistence Guard, Surgical Mirrors, Task Timer, and /logit Protocol.
- [U] **Recent Activity Bug**: Script appears twice after opening. (FIXED in v3.5.3 via Normalization & Conflict Dialog)
- [U] **URGENT: Live State Sync**: "Complete History" list must update immediately after delete/save. (FIXED in v3.5.1)
- [U] **BUG: Recent Activity Timer**: 500ms timer only works if file is *changed*; should activate 500ms after *open*. (FIXED in v3.5.3)
- [U] **BUG: Recent Activity Duplication**: Loading the same file twice creates duplicate history entries. (FIXED in v3.5.4 via Normalization)
- [U] **BUG: Auto-Save Error**: "Bad state: ref after disposed" in editor. (FIXED via state guards)
- [U] **FEATURE: Conflict Resolution**: When reloading an already-modified script, prompt to "Reload & Discard" or "Keep History Version". (FIXED v3.5.2)
- [X] **BUG: Style Regression**: Text alignment and paragraph spacing ignored in the prompter. (AI VERIFIED: Deep alignment scanning implemented) - its the second time its failing! - i select a certain alignment for the text, 1 paragraph to the left, the next paragraph aligned to the right. when i start the prompter mode - its all aligned to one side and doesnt maintain the style i selected.
- [X] **URGENT: Emulator Hardware Bridge**: Restore Mac Keyboard/Camera/Mic access. (AI VERIFIED: v3.9 Forced Hebrew IME & Host Mic) - its the second time its failing! - the emulator still doesnt recognize the mac keyboard, and the mac microphone.
- [X] **FEATURE: History Persistence**: Save/Restore Undo stack in sessions. (AI VERIFIED: v3.9 Sync History Restoration) - when i choose to go back in the history list to a previous point of the script edit - it will select the point in history that i asked for - but when i close and return to the script - it will again go to the latest edit that was known and cancel the undo i did. its ok that we dont delete the history points if we go back to an older version, but you know how to work with new edits in that case and you will need to remember the history point that i selected to undo to even if i leave the script and go back to it later. 
- [U] **RTF Parsing Cleanup**: Optimized script import to remove stray '0' and 'none' artifacts. (USER VERIFIED)
- [U] **Autonomous Deployment**: Integrated /Emulator hot command into the Master Loop. (USER REQUESTED)
- [U] **Recent Scripts Delete**: Delete button only works after toggle "Show More". (USER VERIFIED)
- [U] **Undo/Redo**: Implement for background colors. (USER VERIFIED)
- [X] **Color Picker Reopen**: Picker must show active color when reopened. (AI VERIFIED: Ring Indicator & Black Preset) - its the second time its failing! - you didnt add the black color to the color picker presets - and you still dont show the active colors for the highlighted and text colors. you now added this list of colors presets outside of the color picker suite next to the text and highlight color pickers, its not working and its not wanted. colors should be picked from within the color picker suite.
- [U] **Toolbar "C" Button**: Move to main toolbar (left of TEXT) -> Clear all styles/colors/align. (AI VERIFIED: Hard Reset Logic)
- [U] **BUG: History Sorting**: Reverse history list order (latest at TOP). (AI VERIFIED)
- [U] **Splash Screen**: Remove "V3" text under logo. (FIXED in v3.5.3)
- [U] **Style Exposure Bug**: Selecting text exposes raw RTF/style codes. (AI VERIFIED: Transparent Tag Masking)
- [U] **BUG: Clear Styles History**: Clicking "C" created 3 history points instead of 1 (hard reset + 2 redundant edits). (USER VERIFIED)

## 📂 File Picker (picker_test)
- [-] **Faded Files**: Grey out/disable unsupported files: Could not apply with current resources - Need a dedicated file picker - Maybe in future updates we can do it. (DEFERRED)
- [U] **Security Fix**: Remove "last used folder" memory (Android requirement). (COMPLETED in v2.x)
- [U] **Selection Fix**: Tapping supported file does nothing -> Fix selection. (COMPLETED in v2.x)

---
*Last Updated: 2026-04-07 (v3.6 Consistency Recovery Build)*
