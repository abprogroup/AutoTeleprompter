# Master TODO List: AutoTeleprompter v4.0.3
# (Surgical Terminal Sync v4.0.3)

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
- **Versioning**: Only the USER can authorize major stable version jumps. AI performs sub-version steps for internal tracking.
- **Cleanup**: `[U]` items are preserved for history and only cleared by the USER during major stable version transitions.
- **Surgical Updates**: Only modify specific item(s) related to the current task. Do NOT shorten, delete, or summarize unrelated items.
- **Persistence**: Deferred `[-]` and unfinished items are **NEVER** deleted.

## 🍎 iOS / Multi-Platform (v4.0.2–4.0.3)
- [P] **ARCH: Multi-Platform Separation**: `lib/platform/` layer with abstract interfaces + factory pattern. Zero `Platform.isXxx` in feature code. (AI VERIFIED 2026-04-17)
- [P] **BUG: DOCX Corrupted on Reload**: `_saveScript()` was writing plain UTF-8 bytes for `.docx`. Fixed: routes through `DocxService.generate()`. (AI VERIFIED 2026-04-17)
- [P] **BUG: RTF Loads Empty**: Save wrote plain UTF-8; load stripped bytes > 0x7F killing Hebrew. Fixed: `RtfService.generate()` + UTF-8 fallback on load. (AI VERIFIED 2026-04-17)
- [P] **FEATURE: Pages Export**: `PagesService.generate()` — valid ZIP with `index.xml`. Save dialog shows `.pages` on iOS/macOS only. Round-trip import works. (AI VERIFIED 2026-04-17)
- [P] **BUG: Mic Button Stuck on Mic Icon**: Race condition — iOS async `notListening` from previous stop() overrode new session's `isListening=true`. Fixed: `_startingSession` guard in `TeleprompterNotifier`. (AI VERIFIED 2026-04-17)
- [P] **BUG: Hebrew Colors Show White in Presenter (Toggle OFF)**: `showUpcomingWordColor` toggle ON correctly overrides all markup colors; toggle OFF shows per-word colors. Reverted incorrect "always win" fix. (AI VERIFIED 2026-04-17)

## 🖊️ Editor Hardening (v4.0.3)
- [P] **BUG: B/I/U Needs Two Clicks on Multi-Styled Text**: Forward scan `start+d` in `_isStyleActiveAt` caused false-positive "active" detection near opening tag of next styled block. First click was a no-op; second click applied correctly. Fixed: backward scan only. (AI VERIFIED 2026-04-17)
- [P] **BUG: Hebrew Alignment Shows Wrong State**: `_detectAlignAtCursor` searched for `[/right]` but editor writes `[/align=right]`. indexOf returned -1 always → alignment detection was sticky. Fixed: detect format and use correct close tag. (AI VERIFIED 2026-04-17)
- [P] **BUG: Layout Suite Alignment Highlight Not Updating**: Consequence of alignment detection bug above — now resolved. (AI VERIFIED 2026-04-17)

## 🛠️ UI & UX Fixes (Historical)
- [U] **BUG: Style Regression**: Text alignment and paragraph spacing ignored in the prompter. (USER VERIFIED v3.9.5.6)
- [U] **BUG: Paragraph Spacing**: Empty lines between paragraphs show disproportionately large gaps. (FIXED v3.9.5.1)
- [X] **FEATURE: History Persistence**: Save/Restore Undo stack in sessions. (AI VERIFIED v3.9.5.1; pending user re-test)
- [U] **BUG: Select All Failure**: "Select All" only selects the active paragraph. (FIXED v3.9.5.1)
- [U] **v3.9.5.1 Color & Sync Hardening**: Real-Time Editor Sync, Hardened Prompter Toggles, Authority Persistence. (USER VERIFIED)
- [U] **v3.5.x Hardening**: Persistence Guard, Surgical Mirrors, Task Timer, /logit Protocol. (USER VERIFIED)
- [U] **Recent Activity Bug**: Script appears twice after opening. (FIXED v3.5.3)
- [U] **URGENT: Live State Sync**: History list updates immediately after delete/save. (FIXED v3.5.1)
- [U] **BUG: Recent Activity Timer**: Activates 500ms after open. (FIXED v3.5.3)
- [U] **BUG: Recent Activity Duplication**: Loading same file twice creates duplicates. (FIXED v3.5.4)
- [U] **BUG: Auto-Save Error**: "Bad state: ref after disposed" in editor. (FIXED via state guards)
- [U] **FEATURE: Conflict Resolution**: Prompt to "Reload & Discard" or "Keep History". (FIXED v3.5.2)
- [U] **RTF Parsing Cleanup**: Removed stray '0' and 'none' artifacts. (USER VERIFIED)
- [U] **Autonomous Deployment**: Integrated /Emulator into Master Loop. (USER VERIFIED)
- [U] **Recent Scripts Delete**: Delete button works after "Show More". (USER VERIFIED)
- [U] **Undo/Redo**: Background colors. (USER VERIFIED)
- [U] **BUG: Color Picker Focus**: Applied colors revert due to radix-parsing failure. (AI Deep Fix Verified v3.9.5)
- [U] **Toolbar "C" Button**: Clear all styles/colors/align. (AI VERIFIED)
- [U] **BUG: History Sorting**: Latest at top. (AI VERIFIED)
- [U] **Splash Screen**: Removed "V3" text. (FIXED v3.5.3)
- [U] **Style Exposure Bug**: Raw codes exposed on selection. (AI VERIFIED: Transparent Tag Masking)
- [U] **BUG: Clear Styles History**: 3 history points instead of 1. (USER VERIFIED)
- [U] **URGENT: Emulator Hardware Bridge**: Mac Camera/Mic access. (AI VERIFIED v3.7.1)
- [U] **URGENT: Emulator Hardware ENG Keyboard Bridge**: Mac Keyboard. (AI VERIFIED v3.5.3)
- [-] **URGENT: Emulator Hardware HEB Keyboard Bridge**: Deferred — not critical; hard to implement.

## 📂 File Picker
- [U] **Security Fix**: Remove "last used folder" memory. (COMPLETED v2.x)
- [U] **Selection Fix**: Tapping supported file does nothing. (COMPLETED v2.x)
- [-] **Faded Files**: Grey out unsupported files. Deferred — needs dedicated file picker.

---
*Last Updated: 2026-04-17 (v4.0.3 Editor Hardening + Presenter Fixes)*
