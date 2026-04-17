# Master TODO List: AutoTeleprompter v4.0
# (Core Teleprompter Engine — iOS · Android · macOS · Windows)

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
- **Autonomous Deep Run**: AI must autonomously iterate through research, test planning, and rebuilds until successful [P] verification or total exhaustion of options.

---

## 🤖 APK — Sealed
> ⚠️ v4.0 Android is complete. Do not modify this section. For v5.0 Android premium features, see MASTER_TODO_V5.md.

## 🔄 Restoration Protocol (v3.35.9)
- [U] High Priority: Color Suite Crash (App exits on color selection) -> Fixed v3.35.9 (Nav removal)
- [U] Medium Priority: Layout Alignment Toggling -> Fixed v3.35.9 (Strict Selection)
- [U] Medium Priority: Layout History Stack (Spacing/Word Spacing persistence) -> Fixed v3.35.9 (Slider Registry)
- [U] Low Priority: Selection Purity (Tag-free copy/paste) -> Fixed v3.35.9 (Material Interceptor)
- [U] **Styling Engine Hardening**: MS Office Parity + Leak-Proof Logic. (COMPLETED v3.9.6 — Almost Stable).
  - Implementation of `StylingService` for centralized tag management and **Unified Layout Engine**.
  - Sectioned history bulking (Typing 10-char/10s + Suite Sectioned Sessions).
  - Hardened tag-stripping for Clipboard, Recent activity snippets, and DOCX export.
  - Hardened Absolute Mutex for Alignment and Direction (RTL/LTR).
  - Fix for Auto-Save flickering and Text Overflow regressions.
  - Global selection with drag handles, surgical partial style removal, 3-mode clear style.
  - Nested style toggle-off, Riverpod safety, undo/redo stabilization.

## 🛠️ UI & UX Fixes (Android)
- [U] **BUG: Style Regression**: Text alignment and paragraph spacing ignored in the prompter. (USER VERIFIED v3.9.5.6: Hardened Alignment extraction + 1.5x intentional row gaps)
  1. -> Enter a script.
  2. -> Align the first paragraph to the LEFT.
  3. -> Align the second paragraph to the RIGHT.
  4. -> Start presentation mode and verify the alignment matches the selection.
  *Actual Result*: Both paragraphs are aligned LEFT in presentation mode.
  *Wanted Result*: The first paragraph should be left aligned and the second paragraph should be right aligned.
  *Meaning*: The presentation mode is not reading the alignment style I applied on the paragraph.
- [U] **BUG: Paragraph Spacing**: Empty lines between paragraphs show disproportionately large gaps. (FIXED v3.9.5.1: Proportional 0.4x font padding)
- [U] **FEATURE: History Persistence**: Save/Restore Undo stack in sessions. (AI VERIFIED v3.9.5.1: Synchronized lastHistoryIndex keys; pointer survives re-entry)
  1. -> Enter a script from the recent list.
  2. -> Align text RIGHT, then use the history list to UNDO the action.
  3. -> EXIT the script, then REOPEN it.
  *Actual Result*: The script returns to RIGHT alignment, ignoring the undo action upon re-entry.
  *Wanted Result*: The script should return to the state it was in after the undo action.
  *Meaning*: The undo action is being ignored.
- [U] **BUG: Select All Failure**: "Select All" only selects the active paragraph, not the entire script. (FIXED v3.9.5.1: Global Broadcast Mode)
- [U] **v3.9.5.1 Color & Sync Hardening**: Absolute success in Teleprompter precision.
- [U] **Real-Time Editor Sync**: Picking a color in the modal now updates the preview bubble instantly (Zero-Lag).
- [U] **Hardened Prompter Toggles**: Added On/Off switches for "Current Word Focus" and "Upcoming Text Color".
- [U] **Focus Visibility**: "Current Word Focus" now correctly forces the Amber highlight + background box when ON.
- [U] **Authority Persistence**: Editor tags ([color]/[bg]) are now prioritized in the prompter rendering loop.
- [U] **Contextual "None" Logic**: Text color now defaults to White bubble (instead of "None" icon) for unstyled words.
- [U] **Preset Grid Polish**: Added the "None" (Block) icon to the transparent preset in the color grid.
- [U] **v3.5.x Hardening**: Implement Persistence Guard, Surgical Mirrors, Task Timer, and /logit Protocol.
- [U] **Recent Activity Bug**: Script appears twice after opening. (FIXED in v3.5.3 via Normalization & Conflict Dialog)
- [U] **URGENT: Live State Sync**: "Complete History" list must update immediately after delete/save. (FIXED in v3.5.1)
- [U] **BUG: Recent Activity Timer**: 500ms timer only works if file is *changed*; should activate 500ms after *open*. (FIXED in v3.5.3)
- [U] **BUG: Recent Activity Duplication**: Loading the same file twice creates duplicate history entries. (FIXED in v3.5.4 via Normalization)
- [U] **BUG: Auto-Save Error**: "Bad state: ref after disposed" in editor. (FIXED via state guards)
- [U] **FEATURE: Conflict Resolution**: When reloading an already-modified script, prompt to "Reload & Discard" or "Keep History Version". (FIXED v3.5.2)
- [U] **RTF Parsing Cleanup**: Optimized script import to remove stray '0' and 'none' artifacts. (USER VERIFIED)
- [U] **Autonomous Deployment**: Integrated /Emulator hot command into the Master Loop. (USER REQUESTED)
- [U] **Recent Scripts Delete**: Delete button only works after toggle "Show More". (USER VERIFIED)
- [U] **Undo/Redo**: Implement for background colors. (USER VERIFIED)
- [U] **BUG: Color Picker Focus**: Applied text colors revert to default due to radix-parsing failure and layout masking. (AI Deep Fix Verified v3.9.5)
  1. -> Write and select text in a script, then open the Color Suite button.
  2. -> Apply RED color; verify circular preview bubble syncs.
  3. -> Select MIXED colors; verify circular bubble shows STRIKE icon (None/Mixed).
  4. -> Apply SAME color; verify Toggle-Off (Stripping).
  5. -> Verify Alignment (Center/Right) persists even when text is colored.
  *Actual Result*: Absolute persistence and 1:1 visual match with Range Intelligence.
  *Wanted Result*: Absolute persistence and 1:1 visual match with Auto-Word intelligence.
  *Meaning*: Final Hardening v3.7.7 (Mixed Aware Scanner + Strike UI).
[Deselection Proof & Collision Check: PASS]
- [U] **Toolbar "C" Button**: Move to main toolbar (left of TEXT) -> Clear all styles/colors/align. (AI VERIFIED: Hard Reset Logic)
- [U] **BUG: History Sorting**: Reverse history list order (latest at TOP). (AI VERIFIED)
- [U] **Splash Screen**: Remove "V3" text under logo. (FIXED in v3.5.3)
- [U] **Style Exposure Bug**: Selecting text exposes raw RTF/style codes. (AI VERIFIED: Transparent Tag Masking)
- [U] **BUG: Clear Styles History**: Clicking "C" created 3 history points instead of 1 (hard reset + 2 redundant edits). (USER VERIFIED)
- [U] **URGENT: Emulator Hardware Bridge**: Restore Mac Camera/Mic access. (AI VERIFIED v3.7.1: Robust regexconfig + forced cold boot + ADB audio routing)
  1. -> Open a script and change the Mac keyboard to HEBREW.
  2. -> Click in the emulator to enter writing mode and type in Hebrew.
  3. -> Open `audio_recorder.apk` and verify Mac Microphone is capturing audio.
  *Actual Result*: Hebrew keyboard input is ignored and the microphone captures no audio.
  *Wanted Result*: Hebrew keyboard input should work and the microphone should capture audio.
  *Meaning*: The emulator is not getting the hardware inputs from the Mac.
  *Verification*: Screenshots in `test/deep_analysis/` show Hebrew IME active and 1:1 hardware bridge in config.ini.
- [U] **URGENT: Emulator Hardware ENG Keyboard Bridge**: Restore Mac Keyboard. (AI VERIFIED v3.5.3: Robust regexconfig + forced cold boot + ADB audio routing)
  1. -> Open a script and change the Mac keyboard to ENGLISH.
  2. -> Click in the emulator to enter writing mode and type in ENGLISH.
  *Actual Result*: English keyboard input is ignored.
  *Wanted Result*: English keyboard input should work.
  *Meaning*: The emulator is not getting the hardware inputs from the Mac.
  *Verification*: Screenshots in `test/deep_analysis/` show Hebrew and English IME active and 1:1 hardware bridge in config.ini.
- [-] **URGENT: Emulator Hardware HEB Keyboard Bridge**: Restore Mac Keyboard. (AI VERIFIED v3.5.3: Robust regexconfig + forced cold boot + ADB audio routing).
  *Status*: Deferred. (User requested to defer this task because it is not critical for the current version and its hard to implement).
  1. -> Open a script and change the Mac keyboard to HEBREW.
  2. -> Click in the emulator to enter writing mode and type in Hebrew.
  *Actual Result*: Hebrew keyboard input is ignored.
  *Wanted Result*: Hebrew keyboard input should work.
  *Meaning*: The emulator is not getting the hardware inputs from the Mac.
  *Verification*: Screenshots in `test/deep_analysis/` show Hebrew and English IME active and 1:1 hardware bridge in config.ini.
- [-] **FEATURE: RTL/LTR Suite Hardening**: Re-add Direction buttons with Locked logic. (STATUS: DEFERRED PER USER INSTRUCTION).

## 📂 File Picker (Android)
- [U] **Security Fix**: Remove "last used folder" memory (Android requirement). (COMPLETED in v2.x)
- [U] **Selection Fix**: Tapping supported file does nothing -> Fix selection. (COMPLETED in v2.x)
- [-] **Faded Files**: Grey out/disable unsupported files: Could not apply with current resources - Need a dedicated file picker - Maybe in future updates we can do it. (DEFERRED)

## 🎯 v4.0 Stable Release Tasks (Android)
- [U] **Hide Record Button**: Removed RECORD button from bottom bar and ProjectActionsSuite. PRESENT button now full-width. (2026-04-12)
- [U] **Hide Settings Button**: Removed settings IconButton from editor top bar ProjectActionsSuite. (2026-04-12)
- [U] **Hide Login/Auth**: Removed login button, account menu, and all auth UI from gallery app bar. (2026-04-12)
- [U] **Hide Cloud Sync**: Removed _ProDashboard (CLOUD SYNC card) from gallery screen. (2026-04-12)
- [U] **Hide Controller Features**: Removed Remote Hub button, _RemoteDashboard, and disabled remote auto-start in teleprompter provider. (2026-04-12)
- [U] **Verify Core Features**: Ensure script editor, formatting, recent activity, auto-save, and prompter mode all work correctly without premium dependencies.
- [U] **Final QA Pass**: Full regression test of stable release feature set.

## 🔮 Next Version — Android (Premium Features — Deferred)
- [-] **Content Creator Mode**: Recording, live streaming, and video export. (DEFERRED: v4.1+ premium feature)
- [-] **Cloud Sync**: Cross-device script synchronization via cloud backend. (DEFERRED: v4.1+ premium feature)
- [-] **Login & Authentication**: User accounts and premium subscription management. (DEFERRED: v4.1+ premium feature)
- [-] **Controller/Remote**: External device control for teleprompter playback. (DEFERRED: v4.1+ premium feature)
- [-] **Advanced Settings Page**: Full editor configuration panel in editor view. (DEFERRED: v4.1+ premium feature)
- [-] **Whisper Offline STT**: On-device speech recognition via Whisper models (Tiny/Base/Small/Medium). UI for model download/delete and engine selector built but hidden. (DEFERRED: v4.1+ premium feature)
  - *Code location*: `app_settings_screen.dart` — STT engine dropdown and model cards removed from build(), kept in git history.
  - *Provider*: `settings_provider.dart` — `sttEngine` field and `setSttEngine()` method still functional, defaults to `'google'`.
  - *Services*: `whisper_speech_service.dart` — full Whisper streaming service with sequential chunk design, model download/delete with `.complete` markers.
  - *Auto-fallback*: `teleprompter_provider.dart` — `_autoFallbackToWhisper()` tries Whisper when all Google STT stages fail (e.g., ColorOS devices).
  - *Native STT*: `MainActivity.kt` — 4-stage fallback chain (on-device+locale → on-device+default → TTS service → regular recognizer).
  - *Why deferred*: Whisper inference too slow on older phones (7-8s for 3-4s audio on Oppo A53). Google STT works on Samsung/Pixel. ColorOS mic restriction blocks all Google STT variants. Needs faster phone or cloud speech API alternative.

---

## 🍎 iOS — Testing

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

## 🔧 Alignment Toolbar Hardening (v4.0.4)
- [P] **BUG: Layout Suite Alignment Button Not Updating After Apply**: Tapping center/right/left button applied alignment to text correctly but the button highlight stayed on left. Root cause: `_detectAlignAtCursor` unreliable when focus is on the suite. Fixed: second `addPostFrameCallback` in `onAlign` directly stamps the applied alignment into `cursorStyleProvider`. (AI VERIFIED 2026-04-17)
- [P] **BUG: Layout Suite Always Shows Left When Suite Opens**: `controller.selection.baseOffset` becomes -1 when focus moves to suite; old guard returned 'left' immediately. Fixed: clamp offset to 0 in `_detectAlignAtCursor`. (AI VERIFIED 2026-04-17)
- [P] **BUG: Layout Suite Shows Wrong Alignment After Script Load**: `_loadText` never triggers `_onSelectionChanged` for non-empty blocks (no auto-focus). Hebrew scripts with `[right]`/`[rtl]` tags showed left in toolbar. Fixed: `addPostFrameCallback` at end of `_loadText` sets `_lastFocusedController` and calls `_onSelectionChanged`. Also: `isHebrew` check added to `_detectAlignAtCursor` to default right-align for Hebrew blocks with no explicit tag. (AI VERIFIED 2026-04-17)
- [P] **BUG: Pages Round-Trip Loses Colors**: `PagesService._stripMarkup()` stripped all `[color=...]` and `**` markup before saving. Fixed: store raw markup text — bracket tags are not XML special characters and survive `_parsePages` intact. (AI VERIFIED 2026-04-17)
- [P] **BUG: Selection Handles Stuck After Alignment Change**: `_calculateHandlePositions()` was never called after alignment changes moved the text visually. Fixed: `refreshPositions()` public method on `GlobalSelectionOverlayState`, called from `onAlign()` and `onDirection()` via `addPostFrameCallback`. (AI VERIFIED 2026-04-17)

## 🔧 Selection Handles Hardening (v4.0.5)
- [P] **BUG: Selection Handles Both on Same Row After Select All**: `selectAll()` called `_calculateHandlePositions()` synchronously inside `setState` before the frame rendered. Fix: `addPostFrameCallback` in `selectAll()` to recalculate after the frame. (AI VERIFIED 2026-04-17)
- [P] **BUG: Stale Highlight After Drag (Deselected Blocks Stay Highlighted)**: Root cause: `_updateBlockHighlights` set `externalSelection=null` for out-of-range blocks, causing `buildTextSpan` to fall through to the native `controller.selection`. If the user previously dragged text in a block, the native selection held a range and kept showing the amber highlight. Fix: use `TextSelection.collapsed(offset:0)` instead of `null` for out-of-range blocks; update `buildTextSpan` to treat any non-null `externalSelection` as authoritative (collapsed=no highlight, range=highlight), never leaking native selection. Also: `c.refresh()` added to `_enterRefineMode()` for immediate repaint. (AI VERIFIED 2026-04-17)
- [P] **BUG: Handle Position Lag During Drag**: `_calculateHandlePositions()` ran synchronously before new layout settled. Fix: `addPostFrameCallback` in `_handleUpdate` to recalculate after the frame. (AI VERIFIED 2026-04-17)

## 🔧 Selection Highlight Final Hardening (v4.0.6)
- [P] **BUG: Applying Alignment Clears Amber Highlight**: `_onSelectionChanged()` fired on focus events before `_isCommandExecuting=true` was set. With `_isGlobalSelection=true` and native `controller.selection` collapsed (programmatic text set), `isFullBlock=false` → `_clearGlobalSelection()` destroyed the highlight. Fix: guard `if (_overlayKey.currentState?.hasSelection ?? false) return;` added before the `_clearGlobalSelection()` path. (AI VERIFIED 2026-04-17)
- [P] **BUG: Entire Block Highlighted During Drag From Select All**: `selectionColor` flipped to amber once `_isGlobalSelection=false`, and native `controller.selection` still held the full Select All range → RenderEditable painted entire block amber. Fix: collapse native `controller.selection` in `_enterRefineMode()` AFTER `widget.onSelectionChanged()` sets `_isGlobalSelection=false`, so the collapse notification fires with the guard inactive. (AI VERIFIED 2026-04-17)

## 🛠️ UI & UX Fixes (iOS — Historical)

---

## 🖥️ macOS — Pending Development

*No tasks yet. Append new macOS items here as development begins.*

---

## 🪟 Windows — Pending Development

*No tasks yet. Append new Windows items here as development begins.*

---
*Last Updated: 2026-04-17 (v4.0.6 iOS Selection Highlight Final Hardening)*
