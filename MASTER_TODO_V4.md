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

# MASTER TODO V4 — 4-Way Splitting Active
> **NOTICE**: The repository has been physically split into `Platform_Android`, `Platform_iOS`, `Platform_Windows`, and `Platform_macOS`. All future work MUST be executed inside the specific platform's directory to ensure zero contamination.

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
- [U] **ARCH: Multi-Platform Separation**: `lib/platform/` layer with abstract interfaces + factory pattern. Zero `Platform.isXxx` in feature code. (USER VERIFIED 2026-04-18)
- [U] **BUG: DOCX Corrupted on Reload**: `_saveScript()` was writing plain UTF-8 bytes for `.docx`. Fixed: routes through `DocxService.generate()`. (USER VERIFIED 2026-04-18)
- [U] **BUG: RTF Loads Empty**: Save wrote plain UTF-8; load stripped bytes > 0x7F killing Hebrew. Fixed: `RtfService.generate()` + UTF-8 fallback on load. (USER VERIFIED 2026-04-18)
- [U] **FEATURE: Pages Export**: `PagesService.generate()` — valid ZIP with `index.xml`. Save dialog shows `.pages` on iOS/macOS only. Round-trip import works. (USER VERIFIED 2026-04-18)
- [U] **BUG: Mic Button Stuck on Mic Icon**: Race condition — iOS async `notListening` from previous stop() overrode new session's `isListening=true`. Fixed: `_startingSession` guard in `TeleprompterNotifier`. (USER VERIFIED 2026-04-18)
- [U] **BUG: Hebrew Colors Show White in Presenter (Toggle OFF)**: `showUpcomingWordColor` toggle ON correctly overrides all markup colors; toggle OFF shows per-word colors. Reverted incorrect "always win" fix. (USER VERIFIED 2026-04-18)
- [U] **BUG: iOS Build Failure (STT Callbacks)**: Fixed syntax errors and bracket logic mapping in `TeleprompterNotifier` to properly construct STT callbacks, restoring CI builds. (USER VERIFIED v4.1.5)
- [U] **UX: iOS Keyboard Parity (Editor)**: Wrapped the editor Scaffold in a internal `GestureDetector` so tapping the background correctly dismisses the soft keyboard. (USER VERIFIED v4.1.5)
- [U] **UX: iOS Presentation Floating Button**: Pushed the "PRESENT" button upward intelligently using `MediaQuery.viewInsets.bottom` so it's always accessible above the active iOS keyboard. (USER VERIFIED v4.1.5)
- [U] **UX: iOS Presentation Settings Focus Guard**: Forced explicit `FocusManager.instance.primaryFocus?.unfocus()` when launching presentation mode or interacting with the A+/A- and Settings buttons, blocking the OS from randomly triggering the keyboard. (USER VERIFIED v4.1.5)

## 🖊️ Editor Hardening (v4.0.3)
- [U] **BUG: B/I/U Needs Two Clicks on Multi-Styled Text**: Forward scan `start+d` in `_isStyleActiveAt` caused false-positive "active" detection near opening tag of next styled block. First click was a no-op; second click applied correctly. Fixed: backward scan only. (USER VERIFIED 2026-04-18)
- [U] **BUG: Hebrew Alignment Shows Wrong State**: `_detectAlignAtCursor` searched for `[/right]` but editor writes `[/align=right]`. indexOf returned -1 always → alignment detection was sticky. Fixed: detect format and use correct close tag. (USER VERIFIED 2026-04-18)

## 🔧 Alignment Toolbar Hardening (v4.0.4)
- [U] **BUG: Layout Suite Alignment Button Not Updating After Apply**: Tapping center/right/left button applied alignment to text correctly but the button highlight stayed on left. Root cause: `_detectAlignAtCursor` unreliable when focus is on the suite. Fixed: second `addPostFrameCallback` in `onAlign` directly stamps the applied alignment into `cursorStyleProvider`. (USER VERIFIED 2026-04-18)
- [U] **BUG: Layout Suite Always Shows Left When Suite Opens**: `controller.selection.baseOffset` becomes -1 when focus moves to suite; old guard returned 'left' immediately. Fixed: clamp offset to 0 in `_detectAlignAtCursor`. (USER VERIFIED 2026-04-18)
- [U] **BUG: Layout Suite Shows Wrong Alignment After Script Load**: `_loadText` never triggers `_onSelectionChanged` for non-empty blocks (no auto-focus). Hebrew scripts with `[right]`/`[rtl]` tags showed left in toolbar. Fixed: `addPostFrameCallback` at end of `_loadText` sets `_lastFocusedController` and calls `_onSelectionChanged`. Also: `isHebrew` check added to `_detectAlignAtCursor` to default right-align for Hebrew blocks with no explicit tag. (USER VERIFIED 2026-04-18)
- [U] **BUG: Pages Round-Trip Loses Colors**: `PagesService._stripMarkup()` stripped all `[color=...]` and `**` markup before saving. Fixed: store raw markup text — bracket tags are not XML special characters and survive `_parsePages` intact. (USER VERIFIED 2026-04-18)
- [U] **BUG: Selection Handles Stuck After Alignment Change**: `_calculateHandlePositions()` was never called after alignment changes moved the text visually. Fixed: `refreshPositions()` public method on `GlobalSelectionOverlayState`, called from `onAlign()` and `onDirection()` via `addPostFrameCallback`. (USER VERIFIED 2026-04-18)

## 🔧 Selection Handles Hardening (v4.0.5)
- [U] **BUG: Selection Handles Both on Same Row After Select All**: `selectAll()` called `_calculateHandlePositions()` synchronously inside `setState` before the frame rendered. Fix: `addPostFrameCallback` in `selectAll()` to recalculate after the frame. (USER VERIFIED 2026-04-18)
- [U] **BUG: Stale Highlight After Drag (Deselected Blocks Stay Highlighted)**: Root cause: `_updateBlockHighlights` set `externalSelection=null` for out-of-range blocks, causing `buildTextSpan` to fall through to the native `controller.selection`. If the user previously dragged text in a block, the native selection held a range and kept showing the amber highlight. Fix: use `TextSelection.collapsed(offset:0)` instead of `null` for out-of-range blocks; update `buildTextSpan` to treat any non-null `externalSelection` as authoritative (collapsed=no highlight, range=highlight), never leaking native selection. Also: `c.refresh()` added to `_enterRefineMode()` for immediate repaint. (USER VERIFIED 2026-04-18)
- [U] **BUG: Handle Position Lag During Drag**: `_calculateHandlePositions()` ran synchronously before new layout settled. Fix: `addPostFrameCallback` in `_handleUpdate` to recalculate after the frame. (USER VERIFIED 2026-04-18)

## 🔧 Multi-Line Handle Drag Hardening (v4.0.7)
- [U] **BUG: Handles Cannot Drag to Second Visual Line of Wrapped Text**: Collapsing native `controller.selection` in `_enterRefineMode()` (v4.0.6 Bug 2 fix) corrupted RenderEditable's internal state, preventing `getPositionForPoint()` from correctly mapping y-coordinates on the second+ visual line. Fix: `selectionColor` always transparent; removed native selection collapse from `_enterRefineMode()`. All amber rendering exclusively via `MarkupController.buildTextSpan`. (USER VERIFIED 2026-04-18)

## 🔧 Selection Highlight Final Hardening (v4.0.6)
- [U] **BUG: Applying Alignment Clears Amber Highlight**: `_onSelectionChanged()` fired on focus events before `_isCommandExecuting=true` was set. With `_isGlobalSelection=true` and native `controller.selection` collapsed (programmatic text set), `isFullBlock=false` → `_clearGlobalSelection()` destroyed the highlight. Fix: guard `if (_overlayKey.currentState?.hasSelection ?? false) return;` added before the `_clearGlobalSelection()` path. (USER VERIFIED 2026-04-18)
- [U] **BUG: Entire Block Highlighted During Drag From Select All**: `selectionColor` flipped to amber once `_isGlobalSelection=false`, and native `controller.selection` still held the full Select All range → RenderEditable painted entire block amber. Fix: collapse native `controller.selection` in `_enterRefineMode()` AFTER `widget.onSelectionChanged()` sets `_isGlobalSelection=false`, so the collapse notification fires with the guard inactive. (USER VERIFIED 2026-04-18)

## 🔧 Handle Drag Coordinate Hardening (v4.0.8–v4.0.9)
- [U] **BUG: Handle Snaps to Line 1 When Finger Lands at Top of Hit Area**: `_handleUpdate` received raw `d.globalPosition` (finger touch) instead of the handle's caret position. Fixed: record `_panStartGlobal` and caret global position at pan-start; `onPanUpdate` adds delta to caret origin, not finger origin. (USER VERIFIED 2026-04-18)
- [U] **BUG: Style Selection Shrinks After B/I/U — Missing refresh()**: `externalSelection` is a plain Dart field; assigning it never calls `notifyListeners()`. After `wrapSelection` updated `externalSelection`, `buildTextSpan` was never reinvoked. Fixed: `c.refresh()` after every `c.externalSelection = ns` assignment. (USER VERIFIED 2026-04-18)
- [U] **BUG: _stackKey.currentContext null During onPanUpdate**: `onPanStart` converts caret to global coords once (layout guaranteed valid); `onPanUpdate` adds finger delta to stored global origin — no lookup needed. (USER VERIFIED 2026-04-18)

## 🔧 Multi-Line Drag + Style Selection Final Hardening (v4.1.0–v4.1.2)
- [U] **BUG: Handles at Line-Wrap Boundary Snap Back to Line 1**: `getLocalRectForCaret` with default `TextAffinity.upstream` placed wrap-boundary caret at end of line 1 instead of start of line 2. Fixed: `affinity: TextAffinity.downstream` in all `getLocalRectForCaret` calls in `_getOffsetForPosition`. (USER VERIFIED 2026-04-18)
- [U] **BUG: Multi-Line Drag Double-Converts Coordinates**: `_handleUpdate` called `editable.globalToLocal(globalPos)` then passed result to `getPositionForPoint()` which also calls `globalToLocal()` internally — double-converting always returned a line-1 position. Fixed: pass `globalPos` directly to `getPositionForPoint`. (USER VERIFIED 2026-04-18)
- [U] **BUG: B/I/U Selection Shrinks on Native iOS Long-Press**: v4.1.1 fix was gated on `hadOverlaySelection`; native long-press set `externalSelection=null`, gate evaluated false, fix skipped. iOS async platform reset of `c.selection` then shifted offsets by `open.length` per style application. Fixed: snapshot covers both overlay and native selection; `!isCollapsed` guard in `wrapSelection` / `applyInlineProperty` prevents collapsed sentinel `externalSelection` from being mistaken for a style target. (USER VERIFIED 2026-04-18)

## 🔧 Style Selection Synchronous Lock + Alignment Preservation (v4.1.3)
- [U] **BUG: B/I/U Selection Shrinks — All Visual-Offset Approaches Failed**: Root cause: visual-offset-conversion round-trip had edge cases. Definitive fix: read `c.selection` DIRECTLY after `wrapSelection`/`applyInlineProperty` returns — `controller.value=` sets it synchronously and iOS platform resets only arrive at event-loop boundaries. No visual-offset conversion needed. Applies to all four paths in `_applyStyleCmd` and `_applyInlineCmd`. (USER VERIFIED 2026-04-18)
- [U] **BUG: Alignment on Partial Selection Corrupts Amber Highlight**: `applyLayout` strips old alignment tag and rewraps with new one. Different tag lengths (e.g. `[center]`=8 vs `[left]`=6) shifted all raw offsets in `externalSelection` which was never updated. Fixed: capture visual offsets before alignment (invariant to tag changes since alignment tags render at zero width), convert back to raw offsets after, re-pin `externalSelection`. Applied to both `onDirection` and `onAlign`. (USER VERIFIED 2026-04-18)

## 🛠️ UI & UX Fixes (iOS — Historical)

---

## 🖥️ macOS — Pending Development

- [U] **Initialize Foundation**: `macos/` native layer exists and is integrated with `lib/platform/`.
- [-] **Verification**: Run macOS build on a Mac to verify `SttAppleAdapter` performance. (Moved to V5 Tracker)

---

## 🪟 Windows — Pending Development

- [U] **Initialize Platform Layer**: Generated `windows/` native layer via `flutter create`. (2026-04-18)
- [U] **Windows Branding**: Updated `BINARY_NAME` and `Runner.rc` metadata. (2026-04-18)
- [U] **Isolated Build Pipeline**: Created `.github/workflows/build-windows.yml` with dynamic hot-patching. (2026-04-18)
- [U] **Platform Separation**: Verified `build-ios.yml` ignores Windows folder changes. (2026-04-18)
- [U] **Trigger & Test**: Download the first `.exe` from GitHub Actions, place in `releases/`, and verify performance. Windows v4.1.12 final artifact was user verified after workflow run `25110648732`.
- [U] **Infrastructure Check**: Verify Windows STT/file infrastructure. Final Windows baseline uses WebView2/browser STT for external mic routing and verified import/export hygiene for Windows v4.1.12.

### 💤 Windows — Deferred (v4.1+ / v5.0)
- [-] **Whisper Offline STT (Backup Solution)**: Currently disabled for Windows build to prevent native plugin conflicts. To be revisited as a premium desktop feature. (Moved to V5 Tracker)

### 📽️ Presentation Mode — Pending Fixes
- [-] **Upcoming Text Highlight**: Add a toggle in settings similar to "Upcoming text color" that resets the highlight background of read text. (Moved to V5 Tracker)
- [-] **Spacing Synchronization**: Ensure line spacing, word spacing, and letter spacing values perfectly sync between the editor and presentation mode. Allow negative scales (down to -1.0) in presentation mode to match the editor's default limit constraints. (Moved to V5 Tracker)
- [ ] **Cross-Platform Presentation Resume Point**: Port the verified Windows v4.1.9 behavior to iOS, Android, and macOS so stopping STT pauses the current script position instead of resetting to the beginning. Starting STT must resume from the current confirmed/tapped word; only the existing Restart control is allowed to reset to word `0`. Method proven on Windows: remove automatic `resetPosition()` / scroll-to-top from presentation `initState`; make `startSession(script)` preserve `state.confirmedWordIndex` when the same script is reused and clamp it as the STT start index; add a provider method like `jumpToPosition(index, script: script)` that clears transient STT transcript/no-progress state, updates `confirmedWordIndex`, scrolls to the target word, and syncs STT locale for that position; wrap rendered presentation words with a tap handler that calls the jump method; document the future full bookmark/chapter system in `MASTER_TODO_V5.md` while keeping this v4 task limited to lightweight tap-to-resume parity across platforms. (Windows baseline USER VERIFIED 2026-04-27)
- [U] **Windows Debug/Search/Resume QA**: Verify the Windows debug output window can minimize and re-expand in debug mode, `Ctrl+Shift+F` opens script search in both editor mode and present mode, present-mode search jumps to the matching word/resume point, and mic STT can be stopped and started again inside the same presentation session without resetting or failing to reinitialize. (IMPLEMENTED 2026-04-28; USER VERIFIED in final Windows v4.1.12 testing 2026-04-29)
- [U] **Windows External Microphone Selection**: Add explicit support for an outer connected microphone instead of relying only on the Windows default input device. Implemented by keeping Windows on the WebView2/browser STT adapter, enumerating `navigator.mediaDevices` `audioinput` devices after mic permission, persisting `sttInputDeviceId` + `sttInputDeviceLabel`, adding a presenter settings dropdown with System Default fallback, forwarding live mic changes through `TeleprompterNotifier.setSttInputDevice(...)`, and reopening the browser audio capture stream without resetting `confirmedWordIndex`. Web Speech routing remains Chromium-owned, so the implementation logs and falls back to Windows system default if the saved USB/Bluetooth/interface device is unavailable. (REQUESTED 2026-04-28; IMPLEMENTED 2026-04-28; USER VERIFIED 2026-04-29)

---
*Last Updated: 2026-04-18 (v4.1.4 4-Way Splitting / Windows MVP Initialization)*

## 🤖 Android v4.1.0 — SEALED (2026-04-26)
- [U] **UX: Keyboard Parity (Editor)**: PRESENT button lifts above keyboard via `viewInsets.bottom`; keyboard auto-dismisses on PRESENT; tap-to-dismiss via outer `GestureDetector`; A−/A+/Settings buttons unfocus on tap. (USER VERIFIED 2026-04-26)
- [U] **BUG: Hebrew STT Internet-Required Error**: `SttAndroidAdapter` was not forwarding `onLanguageUnavailable` to `onNeedLanguagePack`. Fixed forwarding chain — UI now correctly shows internet-required message for Hebrew offline. (USER VERIFIED 2026-04-26)
- [U] **PERF: Whisper Removed from v4 Build**: `whisper_flutter_new` and `record` packages removed; `whisper_speech_service.dart` archived to `_v5_archive/`; all 39 provider references stripped. APK dropped from 193MB → 86MB. (USER VERIFIED 2026-04-26)
- [U] **PERF: ABI Filtering**: `abiFilters 'arm64-v8a', 'armeabi-v7a'` added to `build.gradle` — excludes x86_64 (emulator only), targeting ~45MB APK. (USER VERIFIED 2026-04-26)
- [U] **BUG: Select All Immediately Clears Itself**: `_onSelectionChanged` cleared global selection when active block had a collapsed cursor — which is exactly what `_selectAllBlocks()` sets to dismiss handles. Fixed: only clear on a PARTIAL selection (non-collapsed and non-full-block). (USER VERIFIED 2026-04-26)
- [U] **BUG: Global Delete Not Working**: `_selectAllBlocks()` was collapsing the active block's native selection (to dismiss handles), so the soft keyboard saw no selection and deleted nothing. `GhostSelectionControls` already hides handles — collapse was unnecessary. Fixed: set full-block native selection; cascade delete detects "block cleared while global active" and calls `_deleteGlobalSelection()`. (USER VERIFIED 2026-04-26)
- [U] **BUG: Overlay Handles Position Stale After Style**: `_resyncGlobalSelection()` updated `externalSelection` but never told the overlay to recalculate handle positions. Fixed: `addPostFrameCallback` calls `overlay.selectAll()` after layout settles. (USER VERIFIED 2026-04-26)
- [U] **BUG: Native Highlight Persists After Handle Drag**: When entering refine mode, `isGlobalSelected=false` flipped `selectionColor` from transparent to amber, revealing the full-block native selection. Fixed: collapse native selections in `_enterRefineMode()` before handing control to `externalSelection`. (USER VERIFIED 2026-04-26)

## 🍎 iOS v4.1.6 — Selection Delete Parity (2026-04-26)
- [P] **BUG: Select All Delete Not Working (iOS)**: Same root cause as Android — native selection from double-tap persisted, so backspace only deleted the tapped word. Fixed: `_selectAllBlocks()` now sets full-block native selection + `_isCommandExecuting` guard; cascade delete via listener; `_deleteGlobalSelection()` clears all blocks. (PENDING USER VERIFICATION)
- [P] **BUG: Overlay Handles Stale After Style (iOS)**: `_resyncGlobalSelection()` now schedules `overlay.selectAll()` in a postFrameCallback to recalculate handle positions after text-length changes. (PENDING USER VERIFICATION)
---

## Windows v4.1.12 FINAL SEALED (2026-04-29)

- [U] **Windows v4 Complete**: Windows v4 is sealed at `4.1.12+12` with
  workflow title `Build Windows EXE (v4.1.12)`. Final backup:
  `backups/final_windows_v4/20260429_103357`.
- [U] **STT Resume Contract**: Stop/start preserves the current reading point;
  only Restart resets to word `0`.
- [U] **Bookmarks Baseline**: Editor and present mode share bookmarks, show
  visible markers, support multiple anchors, expose add/remove controls, and
  allow previous/next bookmark jumps while STT is active.
- [U] **Search Baseline**: Editor and presenter search jump by visible text, not
  hidden markup offsets.
- [U] **Presenter Scroll Baseline**: Active STT controls row-progress follow;
  stopped STT allows browsing and resume-point selection; bookmark/search jumps
  are immediate.
- [U] **External Mic Baseline**: Windows presenter settings enumerate WebView2
  audio input devices, persist the selected device id/label, and fall back to
  system default.
- [U] **Typography/Spacing Baseline**: Editor and presenter share one font-size
  metadata value, and spacing ranges persist consistently between modes.
- [U] **Structure/Export Baseline**: Symbols, quotes, punctuation, and
  intentional blank lines are preserved; RTF/DOCX export converts internal
  markup to document styling instead of leaking app-private tags.

### Cross-Platform V4 Migration Targets From Windows

- [ ] **Port Windows STT resume contract** to iOS, Android, and macOS.
- [ ] **Port Windows bookmark UX** to iOS, Android, and macOS with
  platform-specific persistence and accessibility. Planned target MVP docs now
  exist for each platform.
- [ ] **Port visible-text search jump behavior** to all platforms.
- [ ] **Port active-STT scroll lock and stopped browsing behavior** to all
  platforms. Planned target Scrolling MVP docs now exist for each platform.
- [ ] **Port one-font-size source-of-truth and spacing synchronization** to all
  platforms.
  - [P] iOS one-font-size source-of-truth implemented locally on 2026-05-02:
    editor and presenter controls now share the same raw font-size metadata
    value. Awaiting user/device verification before marking `[U]`.
  - [P] iOS spacing synchronization implemented locally on 2026-05-02:
    editor and presenter now share line, word, and letter spacing ranges and
    persist spacing through script metadata. Awaiting user/device verification.
- [ ] **Port markup-safe export and symbol/blank-line preservation checks** to
  all platforms.
  - [P] iOS loaded-file symbol/quote/blank-line preservation implemented
    locally on 2026-05-02: import/save/tokenization paths preserve display-only
    punctuation and intentional blank-line structure. Awaiting user/device
    verification.
  - [P] iOS markup-safe export implemented locally on 2026-05-02: DOCX/RTF
    convert internal markup to document styling, and Pages exports visible text
    without raw app-private tags. Awaiting user/device verification.
- [ ] **Define platform-specific external mic behavior** for iOS, Android, and
  macOS. If a platform cannot select an input device in-app, document the OS
  routing limitation in that platform's STT MVP; when it can, implement a
  native selector without copying Windows-specific mechanisms.
  - [P] iOS external microphone selection implemented locally on 2026-05-02:
    presenter settings list `AVAudioSession.availableInputs`, persist
    `sttInputDeviceId` + `sttInputDeviceLabel`, apply `setPreferredInput(...)`
    before Apple STT start, and fall back to System Default when the route is
    missing. Awaiting iOS device verification.

### Refactor Gate Before New V5 Features

- [ ] **Split oversized editor/presenter files behavior-preservingly** before
  large new feature work. Current files above 1000 lines:
  `Platform_Windows/lib/features/script/widgets/script_editor_screen.dart`
  (2885), `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart`
  (2528), `Platform_iOS/.../script_editor_screen.dart` (2135),
  `Platform_iOS/.../teleprompter_screen.dart` (1356),
  `Platform_Android/.../script_editor_screen.dart` (1842),
  `Platform_Android/.../teleprompter_screen.dart` (1341),
  `Platform_Android/.../v3.9.5.1_script_editor_screen.dart` (1290),
  `Platform_macOS/.../script_editor_screen.dart` (2011), and
  `Platform_macOS/.../teleprompter_screen.dart` (1338). Split by MVP ownership
  only after reading the relevant platform docs; do not mix splitting with new
  behavior.

### Windows v4.1.12 FINAL USER VERIFIED - Handoff to iOS (2026-04-29)

- [U] **Windows v4 Final User Verification**: User confirmed Windows version 4
  is complete after testing the final `v4.1.12` artifact. Latest verified
  Windows behavior commit: `160d137` (`Prioritize nearby Windows STT phrases`).
  Workflow `Build Windows EXE (v4.1.12)` run `25110648732` passed.
- [U] **Windows File Split Gate Complete**: Windows has already completed the
  behavior-preserving V5-prep screen split. Every Dart file under
  `Platform_Windows/lib` is below 800 lines. Largest current files:
  `teleprompter_screen.build.dart` (720), `script_provider.dart` (717),
  `settings_provider.dart` (700), `word_aligner.dart` (660),
  `teleprompter_provider.dart` (641), and `script_editor_screen.dart` (579).
  The older pre-split 2885/2528 line counts above are preserved as historical
  context only and no longer describe Windows.
- [U] **Windows Final STT Skip Contract**: Default STT may recover locally up to
  5 words for missed recognizer output. Longer skip behavior is opt-in through
  `Allow visible text skip`, must be bounded to the rendered viewport, and must
  remain fallback-only after nearby 3+ word phrase priority fails.
- [U] **Windows Final Migration Source**: The Windows baseline to port to iOS,
  Android, and macOS includes STT pause/resume, direct Restart reset,
  cross-mode bookmarks, visible-text search, active-STT bookmark jumps,
  active-STT scroll lock, stopped browsing/resume selection, one font-size
  metadata source, synchronized spacing, external mic selection/fallback,
  preserved symbols/blank lines, and markup-safe export.
- [U] **Windows Reference Protocol for Future Ports**: Before implementing any
  Windows-parity item in iOS, Android, or macOS, inspect the verified Windows
  implementation and its matching `_agent/mvp/Platform_Windows/*.md` contract.
  Use Windows as the behavior reference and pattern source, especially for
  details like `Allow visible text skip` defaulting to off, local 5-word STT
  recovery staying always available, and visible-skip fallback rules. Do not
  copy Windows-specific platform mechanisms blindly; translate the behavior into
  the target platform's native services and document any unavoidable difference.
- [ ] **Next Active Platform - iOS**: Continue development in
  `Platform_iOS/` only. Before implementation, read the matching
  `_agent/mvp/Platform_iOS/*.md` contracts and port the Windows behavior
  surgically without copying Windows-specific WebView2/STT implementation
  details blindly.

### iOS Prep Status (2026-04-29)

- [U] **iOS Large File Split Gate**: `Platform_iOS` editor/presenter split is
  complete as a behavior-preserving refactor. Every Dart file under
  `Platform_iOS/lib` is below 800 lines. The old oversized
  `script_editor_screen.dart` and `teleprompter_screen.dart` are now shell files
  with MVP-owned `part` files documented in `_agent/mvp/Platform_iOS/`.
- [P] **iOS Multi-Block Cut/Paste Verification**: Re-test Select All -> Cut ->
  Paste across two differently styled paragraph blocks after the clipboard
  snapshot fix. Expected result: Cut removes both blocks, Paste restores both
  blocks with raw-markup styling intact, regardless of which block was
  originally double-tapped. Debug mode should show stored/restored block count.
- [ ] **iOS Windows-Parity Feature Gap List**: Implement after the split, in
  iOS-native terms: STT stop/resume without reset, default 5-word local
  recovery, opt-in visible viewport skip with nearby phrase priority,
  active-STT scroll lock/row-progress follow, stopped browsing resume
  selection, cross-mode bookmarks, active-STT bookmark jumps, visible-text
  search, one font-size metadata authority, synced spacing, preservation of
  symbols/quotes/blank lines, markup-safe export, and external microphone
  routing policy.
- [P] **iOS STT Stop/Resume Without Reset**: Ported the verified Windows
  pause/resume contract into iOS. `startSession()` now resumes the same active
  script from current `confirmedWordIndex`; `stopSession()` stops recognizers
  without resetting position; quick stop/start is serialized; and presentation
  entry no longer calls Restart implicitly. Awaiting user IPA verification.
- [P] **iOS Default 5-Word Local Recovery**: `WordAligner.align(...)` now
  accepts optional `maxSkipTargetIndex`; with no argument it uses a strict
  5-word default local recovery window and refuses paragraph/section skips.
  When the value is supplied (Item 3 future work), the aligner runs the
  visible-skip path with nearby phrase priority and capped sequence jump.
  Provider call site is unchanged so the new default is active immediately.
  Awaiting user IPA verification.
- [P] **iOS QA Follow-Up - Resume/Skip/Bookmark Toolbar**: After user testing,
  repaired same-session STT resume after editor round-trip by comparing stable
  script/session identity instead of Dart object identity; added a re-entry
  Resume/Restart prompt; exposed the missing present-mode `Allow visible text
  skip` switch; changed present bookmark markers to floating UI so they do not
  consume text-flow space; and split the present control bar into two rows to
  prevent bookmark-button overflow. Awaiting IPA/device verification.
- [P] **iOS Presenter Search Toolbar / Control Fade Follow-Up**: Added compact
  present-mode search-result toolbar so one query can move previous/next across
  matches without reopening search, kept the search-new-text and close actions
  inside that toolbar, moved present settings to the left edge of the lower
  toolbar so the mic button is centered again, and strengthened the bottom fade
  behind the two-row controls so script text cannot hide buttons. Awaiting
  IPA/device verification.
- [P] **iOS Selection Dismissal Regression Follow-Up**: After QA found that
  selected editor text could remain stuck after tapping elsewhere and could
  confuse later Cut/Copy, added an explicit user-navigation dismiss path that
  clears global/overlay/native selection plus the temporary Select All recovery
  snapshot while preserving the real `_blockClipboard` for Paste recovery.
  Awaiting IPA/device verification.
- [P] **iOS Selection Handles / Bookmark Coordinate Follow-Up**: After QA found
  that drag-handle selections did not update the effective clipboard and that
  handles drifted during editor scrolling, selection handle drags now publish
  the live overlay-selected raw slices and editor scroll refreshes overlay
  handle positions. Presenter bookmark anchors now use paragraph direction for
  marker side, presenter-created bookmarks save editor block/offset coordinates,
  and returning from present mode force-reloads editor bookmarks. Awaiting
  IPA/device verification.
- [ ] **Windows Follow-Up From iOS QA**: Port the new Resume/Restart re-entry
  choice and compact multi-result search navigation UX to Windows in a future
  Windows-only pass. Details are appended in
  `Missing features from Windows development to implement all platforms.md`.

### iOS Windows-Parity Local Implementation Status (2026-05-02)

- [P] **iOS Active-STT Bookmark Jumps**: Bookmark previous/next is wired through
  the presenter/provider jump path so it can move position without treating mic
  stop/start as reset. Awaiting IPA/device verification, especially while STT
  is actively listening.
- [P] **iOS One Font-Size Metadata Authority**: Editor and presenter controls
  now read/write the same raw settings/script metadata font-size value.
  Presenter visual enlargement remains render-only and must not become a saved
  second number. Awaiting user IPA verification.
- [P] **iOS Synced Spacing Ranges**: Editor Layout Suite and present settings
  now share line `0.5..3.0`, word `-5.0..20.0`, and letter `-2.0..5.0`
  ranges; line spacing displays as default-relative `0.0` at saved `1.2`.
  Awaiting user IPA verification.
- [P] **iOS Loaded-File Structure Preservation**: Import/save/tokenization paths
  now preserve loaded-file punctuation-only signs, quotes, section markers, and
  intentional blank-line structure instead of trimming or collapsing it.
  Awaiting user IPA verification.
- [P] **iOS Markup-Safe Export**: Added an iOS markup export parser. DOCX/RTF
  convert app-private tags to document styling; Pages exports visible text
  without leaking raw tags. Awaiting user IPA verification.
- [P] **iOS External Microphone Selection**: iOS presenter settings now list
  native `AVAudioSession.availableInputs`, persist the chosen route, and apply
  `setPreferredInput(...)` before Apple STT start. System Default remains the
  fallback. Awaiting iOS device verification.
- [P] **iOS Visible-Text Search With Raw-Offset Mapping**: Ported the Windows
  search baseline into iOS. Editor search opens from the action bar and
  `Ctrl/Meta+Shift+F`, searches stripped visible text, maps the match back to
  raw markup offsets via `MarkupController.visualToRawOffset(...)`, and selects
  the real visible characters without landing inside hidden tags. Presenter
  search opens from the control bar and hardware-key shortcut, searches visible
  phrase text, and jumps through the provider position path so resume point and
  scroll target stay synchronized. Awaiting user IPA verification.
- [P] **iOS Opt-In Visible Viewport Skip**: Added `sttVisibleSkipEnabled`
  setting (default off) with persistence and setter. Provider stores
  `_visibleWordStart`/`_visibleWordEnd` and exposes `setVisibleWordWindow`.
  `_handleSttResult` passes `_visibleWordEnd` as `maxSkipTargetIndex` only
  when the toggle is on AND a visible window is reported. Presenter
  `_syncVisibleWordWindow` walks `_wordKeys` against the viewport, throttled
  to 150 ms, scheduled from build. Awaiting user IPA verification.
- [P] **iOS Active-STT Scroll Lock & Row-Progress Follow**: Added
  `TeleprompterState.isStarting` (set true at `startSession()` entry,
  cleared on first status callback / stop / fatal error). Presenter
  `SingleChildScrollView` uses `NeverScrollableScrollPhysics` while
  `isListening || isStarting`. `_handleStoppedBrowsingScroll` is a no-op in
  that window. `_scrollToWordIndex` adds `rowProgress * lineAdvance` from
  `_visualRowProgress` for smooth row-internal glide. Awaiting user IPA
  verification.
- [P] **iOS Stopped Browsing & Resume-Point Selection**: Added
  `_userBrowsingWhileStopped`, `_handleStoppedBrowsingScroll` (drag-end
  triggers `_syncResumePointToReadingLine`), and
  `TeleprompterNotifier.jumpToPosition(int, {Script?})` with
  `_syncLocaleForPosition` helper that doesn't violate Invariant 12. Stop
  is now pause-and-browse; the next mic start resumes from the synced
  point. Restart remains the only path to word 0. Awaiting user IPA
  verification.
- [P] **iOS Cross-Mode Bookmarks**: Ported the Windows bookmark baseline into
  iOS. Added shared script-scoped bookmark persistence, editor add/remove/
  previous/next controls, presenter add/remove/previous/next controls, visible
  `»` markers in editor and present mode, marker deletion, and editor-to-
  presenter session/title handoff so both modes load the same bookmark scope.
  Awaiting user IPA verification.
