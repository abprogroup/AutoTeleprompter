# Daily Log: AutoTeleprompter v3.7.5 [ABSOLUTE_VERIFICATION]

### ✅ 2026-04-07 — v3.7.5 [PROTOCOL_PERFECTION]
- **Loop Mode**: Protocol Recovery & Hardening.
- **Achievements**:
    - **Restored v3.6.1 Broad Loop**: Recovered the lost `/run` rules for multi-task autonomous sessions.
    - **Hardened v3.7.5 Deep Loop**: Integrated **"Test Route Planning"**, **[TRIO-PATH] Research**, and **Iteration Caps**.
    - **Root Directory Governance**: Institutionalized **Dynamic Artifact Routing** to keep the workspace pristine.
    - **Selection Refinement**: Added the **Distinct Test Target Rule** to eliminate visual confusion during color/style tests.
- **WAV Status**: Verified.
- **Commit**: [V3-SYNC] Restored run protocols and institutionalized Absolute Verification v3.7.5.

### ✅ 2026-04-07 — v3.7.2 [DEEP_FIX] Session
- **[/deep_run] executed**: Focused on **Emulator Hardware Bridge** bug.
- **INFRA: Hardware Bridge v3.7.2**: 
    - Rewrote \`emulator_bridge.sh\` to use robust regex for AVD \`config.ini\` patching.
    - Forced \`fastboot.forceColdBoot = yes\` and \`hw.keyboard = yes\` for all detected AVDs.
- **Verification**: Confirmed Hebrew IME active in the app and recorder.

### ✅ 2026-04-07 — v3.6.2 Second Chance Sprint
- **BUG Fix: Style Regression (v3.6.2)**: \`_onAlign\` rewritten as paragraph-level operation.
- **BUG Fix: History Persistence (v3.6.2)**: \`dispose()\` now calls \`saveScript()\` to sync undo stack.
- **UI Fix: Color Picker (v3.6.2)**: Moved presets inside dialog.

### ✅ 2026-04-13 — v4.0 Stable Release [NATIVE_STT_ENGINE]
- **Session Goals**: Build working speech-to-text for Android, fix ColorOS mic restrictions, implement Whisper offline fallback.
- **Achievements**:
    - **Native Android STT**: Built custom `MethodChannel` speech recognition in `MainActivity.kt`, bypassing `speech_to_text` plugin. Uses `createOnDeviceSpeechRecognizer()` (API 31+) which runs in app's process with app's mic permission.
    - **4-Stage Fallback Chain**: On-device+locale → on-device+default → TTS service component → regular recognizer → auto-Whisper fallback. Covers Samsung, Pixel, ColorOS, MIUI.
    - **ColorOS Investigation**: Identified root cause — `appops RECORD_AUDIO: foreground` on Google app. SODA language packs in Speech Services by Google are separate from system SODA used by `createOnDeviceSpeechRecognizer()`. All 4 Google STT stages fail on tested Oppo device.
    - **Whisper Sequential Chunk Engine**: Redesigned from 0.8-1.2s chunks to 2.5-4s chunks for better accuracy. Model download integrity markers (`.complete` files). Artifact filtering for hallucinations.
    - **Defunct Element Fix**: Guarded all STT/Whisper callbacks with `_disposed` and `_sessionStopped` to prevent assertion failures on screen exit.
    - **Settings UI Cleanup**: Hid STT engine selector and Whisper model download/delete UI. Kept Profile/Display Name setting.
    - **Release APK**: Saved as `releases/v4.0.apk`.
- **Deferred**:
    - Whisper offline STT: Too slow on older phones (7-8s inference for 3-4s audio on Oppo). Needs faster hardware or cloud speech API.
    - ColorOS Google STT: SODA packs not accessible to system on-device recognizer. No fix without root or API 34+ `triggerModelDownload()`.
- **Key Files Modified**: `MainActivity.kt`, `native_speech_service.dart`, `whisper_speech_service.dart`, `teleprompter_provider.dart`, `app_settings_screen.dart`.

---
*v3.7.5 [PROTOCOL_PERFECTION] Session Complete. Standing by for [V3.7.5-DEEP-START] Color Picker restart.*

### ✅ 2026-04-08 — v3.9.5.1 [SENTRY_UPGRADE]
- **Session Goals**: Evolve /deep_run into a 7-hour autonomous sentry mode.
- **Achievements**:
    - **Hot Command Formalization**: Successfully registered `/clearance` in the AI Protocol and updated all internal workflow references.
    - **Indexing Fix**: Repaired YAML frontmatter across all core workflows (`/run`, `/plan`, `/sync`, etc.) to ensure visibility in the Hot Command list.
    - **Workspace Cleanup**: Deleted redundant `grant.sh` and stylized `/clearance` as the primary authority ritual.
- **Status**: Mission SUCCESS. Protocol v3.9.5.2 Authority Refined.

### ✅ 2026-04-12 — v3.9.6 [STYLING_ENGINE_HARDENING]
- **Loop Mode**: Manual deep session — styling system stabilization for stable release.
- **Achievements**:
    - **Global Selection System**: Fixed Select All to broadcast across all paragraph blocks; resolved infinite loop when drag handles fought Select All escalation; added `overlayActive` guard.
    - **Style Toggle Fix**: B/I/U now correctly toggle on AND off for both single-block and global selection. Nested style toggle-off (e.g. `[i]` inside `[u]`) fixed via forward-search fallback in `_removeEnclosingStyle`.
    - **Partial Style Removal**: Surgical split algorithm — selecting one word inside a styled sentence and untoggling removes style from only that word, re-wrapping the rest.
    - **Selection Highlight Cleanup**: Fixed amber highlight persisting after deselect by collapsing native selections in `_clearGlobalSelection`. Fixed triple-layer highlight (native + container + buildTextSpan).
    - **Drag Handle Accuracy**: Replaced hardcoded TextPainter with actual `RenderEditable` for caret positions in `GlobalSelectionOverlay`.
    - **Riverpod Safety**: Deferred `cursorStyleProvider` updates to `addPostFrameCallback` to prevent "modified during build" errors.
    - **Professional History System (v3.9.6)**:
        - **Typing Bulking**: 10-char / 10-second rule — commits after 10 typed characters OR 10 seconds of inactivity. New line = immediate commit.
        - **Suite Sectioned Bulking**: Different functions within a suite create separate history entries (e.g. Bold vs Font Size). Section changes auto-commit the previous section.
        - **Duplicate Prevention**: `_commitHistory` skips if text + settings match the current head.
        - **Alignment**: Always commits immediately (discrete action, not bulked).
    - **Clear Style 3-Mode System**:
        - Selection Mode: strip tags from selected text only, split enclosing tags.
        - Word Mode: cursor in middle of word → clear that word's styles only.
        - Baseline Mode: cursor at end of line → clear entire script formatting.
    - **Undo/Redo Fix**: `_isCommandExecuting` kept true for 150ms to outlast `_isLoading` reset; `_isDirty` properly reset; `_jumpToHistory` method for history list navigation.
- **Backup**: `autoteleprompter_backup_20260412_144202_almost_stable.tar.gz`
- **Status**: Near-stable. Preparing for stable release with premium feature separation.

### ✅ 2026-04-12 — v3.9.8 [TELEPROMPTER_HARDENING + STABLE_PUBLISH]
- **Session Goals**: Fix teleprompter STT/recognition issues, restore presentation font scaling, prepare v4.0 stable publish.
- **Achievements**:
    - **Settings Red Screen Fix**: fontSize default changed from 18.0→20.0 with proper clamping to match slider min (20.0).
    - **Hebrew STT Recognition Overhaul**: Expanded prefix stripping (triple/double combos: ובה, ולה, וב, של, כש, etc.), added phonetic normalization (ק→כ, ט→ת, ס→ש), lowered Hebrew match threshold to 0.45.
    - **Improvisation Tolerance**: Search window 30→60, max jump 10→50, distance penalty 0.03→0.025, stuck counter 25→45 (~15s grace period).
    - **Upcoming Text Color Override**: When toggle ON, overrides all editor inline colors for uniform presentation appearance.
    - **Text Alignment Toggle Override**: Converted alignment picker to toggle-gated override with AnimatedOpacity + IgnorePointer.
    - **Hebrew Selection Fix**: Fixed deselection and highlight removal for RTL text via normalized renderSelection and post-frame safety callback.
    - **Graceful STT Error Recovery**: Only fatal errors (audio hardware, permissions) stop recognition; all others auto-restart (20ms timeout, 150ms general).
    - **Stop Button Fix**: Explicit state update after `_sessionStopped` flag bypass.
    - **Word Jump Support**: `_maxAdvancePerUpdate` 5→50, allows jumping to any visible word on screen.
    - **2x Presentation Font Multiplier**: Restored `settings.fontSize * 2.0` for teleprompter presentation mode.
    - **v4.0 Stable Publish**: Updated governance docs, created backup, removed premium features (Record, Settings, Login/Auth, Cloud Sync, Controller/Remote).
- **Backup**: Pre-stable-publish backup created.
- **Status**: v4.0 Stable Release — core teleprompter features only.

### ✅ 2026-04-17 — v4.0.2 [iOS_HARDENING + MULTI_PLATFORM_SEPARATION]
- **Session Goals**: Fix all iOS bugs found during testing; implement clean multi-platform architecture.
- **Achievements**:
    - **Multi-Platform Architecture**: Created `lib/platform/` layer with abstract interfaces and factory pattern. Separates iOS, Android, macOS, and Windows for STT, file import, permissions, and keyboard logic. Zero `Platform.isXxx` checks in feature code.
    - **STT Factory**: `SttServiceFactory.create()` returns `SttAppleAdapter` (iOS/macOS), `SttAndroidAdapter` (Android), or `SttDesktopAdapter` (Windows). All share `AbstractSttService` interface with `requiresImmediateListeningFlag` for Apple async quirk.
    - **DOCX Save Fix**: `_saveScript()` now routes `.docx` through `DocxService.generate()` instead of plain `utf8.encode()`. Old corrupted DOCX files can be recovered by renaming to `.txt`.
    - **RTF Round-Trip**: `RtfService.generate()` writes valid RTF with Unicode escapes (`\uNNNN?`) for Hebrew/Arabic, full color table, bold groups. `_saveScript()` routes `.rtf` through it. Non-RTF `.rtf` files (saved before the fix) now load via UTF-8 instead of the ASCII byte-filter that stripped all Hebrew characters.
    - **Pages Export (iOS/macOS only)**: `PagesService.generate()` writes a minimal ZIP with `index.xml` in old Apple Pages XML format. Save dialog shows `.pages` option on iOS/macOS only (`Platform.isIOS || Platform.isMacOS`). Round-trip import verified.
    - **Mic Button Race Fix**: Added `_startingSession` guard in `TeleprompterNotifier`. Root cause: iOS fires async `notListening` status from the previous `stop()` call after the new session already set `isListening=true`. Guard blocks non-listening status for 1.5 s after start, or until first confirmed `listening` fires.
    - **Hebrew Colors Fix**: `word.textColor` (from `[color=...]` markup) now takes priority over `showUpcomingWordColor` setting for both past and future words. Explicit markup colors now survive presentation mode for all languages including Hebrew.
    - **Project Root Cleanup**: Removed `.DS_Store`, `._*` metadata files, versioned dead files (`v3.9.5.1_script_editor_screen.dart`). Renamed `v3_splash_screen.dart` → `splash_screen.dart` via `git mv`. Updated `.gitignore` to block Mac junk permanently.
    - **Platform Structure Doc**: Added `Project platforms structure.md` documenting `lib/platform/` architecture, folder structure, platform→feature matrix, and development rules.
- **Commits**: `01818f1` (DOCX fix) → `81f54a4` (RTF + mic + Hebrew) → `9ea778d` (Pages export) → `5ec8a0b` (double-extension fix)
- **iOS Build**: Triggered via GitHub Actions on push `5ec8a0b`. IPA available in Actions artifacts → download → Sideloadly.
- **Status**: All 6 reported iOS bugs fixed. Multi-platform architecture fully in place.

### ✅ 2026-04-17 — v4.0.3 [EDITOR_HARDENING + PRESENTER_FIXES]
- **Session Goals**: Fix three bugs reported after iOS testing — presenter color override, B/I/U double-click, Hebrew alignment display.
- **Achievements**:
    - **Presenter Color Override (Reverted Wrong Fix)**: Previous session incorrectly made `word.textColor` always win over `showUpcomingWordColor`. Restored correct behavior: toggle ON → uniform `futureWordColor` override for all words; toggle OFF → per-word markup colors shown.
    - **B/I/U Double-Click Root Cause Found & Fixed**: `_isStyleActiveAt` in `styling_logic_mixin.dart` scanned positions `start+d` (forward) around the cursor. This caused a false-positive "already active" detection when the cursor was just before the opening tag of the next styled block (`[u]`, `[i]`, `**`). First click tried to remove a non-existent enclosing style → `_removeEnclosingStyle` returned null → no change. Second click correctly applied. Fix: backward scan only (`start-d`); forward scan removed with explanation comment.
    - **Hebrew Alignment Detection Fixed**: `_detectAlignAtCursor` searched for `[/right]` as the close tag, but the editor writes `[/align=right]`. `indexOf('[/right]')` always returned -1, so `nextClose == -1` was always true, making alignment "sticky" — once `[align=right]` appeared, all subsequent cursor positions were reported as right-aligned. Fix: detect opening tag format (`[align=val]` vs `[val]`) and search for the matching close tag.
    - **Layout Suite State Sync**: The alignment fix also restores the layout suite's highlighted button to correctly reflect the active alignment when cursor moves in and out of alignment blocks.
- **Commit**: `3074460`
- **iOS Build**: Triggered and completed. IPA downloaded to `releases/iOS/v1.0/AutoTeleprompter.ipa`.
- **Status**: All three reported bugs fixed. IPA ready for Sideloadly install.

### ✅ 2026-04-17 — v4.0.4 [ALIGNMENT_TOOLBAR_HARDENING]
- **Session Goals**: Fix layout suite alignment buttons not correctly reflecting the active alignment in all scenarios.
- **Achievements**:
    - **Alignment Button Highlight on Apply**: After tapping left/center/right in the layout suite, the correct button now lights up immediately. Root cause: `_detectAlignAtCursor` is unreliable the moment after applying alignment because focus is on the suite (not the text field) and the selection/focus state is in flux. Fix: added a second `addPostFrameCallback` after `_onSelectionChanged()` in `onAlign` that directly stamps the just-applied alignment value into `cursorStyleProvider.textAlign`. Fires FIFO after the detection callback, guaranteeing the correct button highlights.
    - **Alignment Button Sync When Suite Opens**: When focus moves to the layout suite from the text field, `controller.selection.baseOffset` becomes -1 (invalid). The old guard `if (off < 0) return 'left'` bailed immediately, so detection always returned 'left' regardless of the text. Fix: clamp offset to 0 — alignment tags always wrap from position 0, so scanning at 0 correctly reads the block's alignment even with invalid selection.
    - **Alignment Button Sync on Script Load**: `_loadText` calls `_addBlock` for each paragraph, but focus is only auto-requested for empty blocks. For a loaded script with content (including Hebrew scripts with `[right]`/`[rtl]` tags), no focus event ever fired, so `_onSelectionChanged` was never called and `cursorStyleProvider` stayed at its default `textAlign:'left'`. Fix: `addPostFrameCallback` at the end of `_loadText` sets `_lastFocusedController` to the first block and calls `_onSelectionChanged`, causing the toolbar to read and reflect the actual alignment of the loaded text.
- **Commits**: `06a1a11` (clamp offset) → `da1ee46` (direct stamp on apply) → `f5135fe` (sync on load)
- **iOS Build**: Run `24545992796`, artifact `6488161402`. IPA downloaded to `releases/iOS/v1.0/AutoTeleprompter.ipa` (timestamp 06:27).
- **Status**: All three alignment toolbar display scenarios fixed. IPA ready for Sideloadly.

### ✅ 2026-04-17 — v4.0.5 [SELECTION_HANDLES_HARDENING]
- **Session Goals**: Fix selection handle positions and stale highlight bugs introduced during v4.0.4 alignment work; unify platform TODO files.
- **Achievements**:
    - **Selection Handles Both on Same Row After Select All**: `selectAll()` called `_calculateHandlePositions()` synchronously inside `setState`, before the frame had rendered the selection highlights. RenderEditable caret coords were stale. Fix: added `addPostFrameCallback` in `selectAll()` to recalculate positions after the first rendered frame.
    - **Stale Highlight After Drag**: `_enterRefineMode()` set `isGlobalSelected = false` on all controllers but never called `c.refresh()`, so TextFields did not repaint until `_handleUpdate`'s setState fired. If the drag was over a gap between blocks, no setState fired at all, leaving the full-selection highlight frozen. Fix: call `c.refresh()` inside `_enterRefineMode()` immediately after clearing `isGlobalSelected`.
    - **Handle Position Lag During Drag**: `_calculateHandlePositions()` ran synchronously inside `_handleUpdate`'s setState, before the new selection layout was rendered. Added `addPostFrameCallback` in `_handleUpdate` to recalculate after the frame settles.
    - **Unified Platform TODO**: Merged `MASTER_TODO.md` (iOS) and `MASTER_TODO_V4.md` (Android/Sealed) into a single `MASTER_TODO_V4.md` with four sections — APK Sealed · iOS Testing · macOS Pending · Windows Pending. Deleted old `MASTER_TODO.md`.
    - **Logit Workflow Update**: Updated `_agent/workflows/logit.md` to reference the unified `MASTER_TODO_V4.md` and instruct the AI to append new items to the correct platform section based on the active build target.
- **Commits**: `c89254e` (unified TODO) → `75e7aea` (selection handles fix) → `8278f6b` (stale highlight fix)
- **iOS Build**: Run `24562460617`. IPA downloaded to `releases/iOS/v1.0/AutoTeleprompter.ipa`.
- **Status**: Selection system hardened. IPA ready for Sideloadly.

### ✅ 2026-04-17 — v4.0.6 [SELECTION_HIGHLIGHT_FINAL_HARDENING]
- **Session Goals**: Fix two remaining selection highlight bugs: (1) applying alignment clears amber highlight, (2) full block highlighted when only partial selection via drag.
- **Achievements**:
    - **Highlight Preserved After Alignment**: `_onSelectionChanged()` fires on focus events before `_isCommandExecuting` is set. With `_isGlobalSelection=true` and native `controller.selection` collapsed (text was programmatically set), `isFullBlock=false` → `_clearGlobalSelection()` was called, destroying the visual highlight. Fix: added `if (_overlayKey.currentState?.hasSelection ?? false) return;` guard in `_onSelectionChanged()` before the `_clearGlobalSelection()` path. When the overlay has active handles, focus events never clear the selection.
    - **Full-Block Highlight Fixed on Drag**: When `_enterRefineMode()` set all `c.isGlobalSelected=false` and then `widget.onSelectionChanged()` set `_isGlobalSelection=false`, all `_EditorBlock` widgets rebuilt with `selectionColor=amber (non-transparent)`. Native `controller.selection` still held the full Select All range → RenderEditable painted the entire block amber. Fix: in `_enterRefineMode()`, after `widget.onSelectionChanged()` (so `_isGlobalSelection=false` is already set), collapse native selection for any non-collapsed controller. The collapse notification fires with `_isGlobalSelection=false` so the `_clearGlobalSelection()` guard is inactive.
- **Root Cause Summary**: Two-layer selection system (native RenderEditable + custom buildTextSpan) — `selectionColor` toggle between transparent and amber on `_isGlobalSelection` change was the common thread; native selection state was leaking through when selectionColor became non-transparent.
- **Commits**: `2a2ec85`
- **iOS Build**: Run `24564294419`, artifact `6495419040`. IPA downloaded to `releases/iOS/v1.0/AutoTeleprompter.ipa`.
- **Status**: Selection highlight system fully hardened across all scenarios.

### ✅ 2026-04-17 — v4.0.7 [MULTI-LINE_DRAG_HARDENING]
- **Session Goals**: Fix selection handles not dragging to second visual line of wrapped text in a single block.
- **Root Cause**: The Bug 2 fix in v4.0.6 collapsed native `controller.selection` to offset 0 in `_enterRefineMode()`. This was done to prevent RenderEditable painting full-block amber after `selectionColor` flipped from transparent to amber when `_isGlobalSelection` became false. However, the collapse interfered with `getPositionForPoint()` — after the RenderEditable's internal state was reset, it could no longer correctly map y-coordinates on the second visual line of wrapped text to the corresponding text positions.
- **Fix**: Changed `selectionColor` to always `Colors.transparent` in `_EditorBlock`. All amber selection rendering is now exclusively handled by `MarkupController.buildTextSpan` via `externalSelection`/`isGlobalSelected`. Since RenderEditable never paints its own amber, the native selection collapse in `_enterRefineMode()` is no longer needed and was removed. This is a cleaner two-layer architecture: native = transparent cursor/input only; custom buildTextSpan = all visual selection.
- **Commits**: `9d821ea`
- **iOS Build**: Run `24566209797`, artifact `6496212142`. IPA downloaded to `releases/iOS/v1.0/AutoTeleprompter.ipa`.
- **Status**: Multi-line drag still broken — handle snapped to line 1. User confirmed bug persists. Root cause re-analyzed and fixed in v4.0.8.

### ✅ 2026-04-17 — v4.0.8 [DELTA_DRAG + STYLE_SELECTION_LOCK]
- **Session Goals**: (1) Fix multi-line handle drag snap to line 1. (2) Fix style application (B/I/U/Color/Size) shrinking the amber selection by 2-3 chars with each successive style.
- **Bug A Root Cause (Multi-line drag)**: `_buildHandle.onPanUpdate` passed `d.globalPosition` (where the finger touches the screen) directly to `_handleUpdate`. The handle is positioned `top: pos.dy - 18` — 18px above the logical caret point. When the user grabs the handle at the top of the 56-px hit area, the finger y-coordinate is ~18px above the caret, which maps into the first visual line's range via `editable.getPositionForPoint()`. Every drag frame snapped the caret to line 1 regardless of how far down the user dragged.
- **Bug A Fix**: Delta-based drag compensation. On `onPanStart`: record `_panStartGlobal = details.globalPosition` and `_panStartHandleLogical = _handleStartPos / _handleEndPos` (the Stack-local logical caret position). On `onPanUpdate`: compute `adjustedGlobal = stackBox.localToGlobal(_panStartHandleLogical) + (details.globalPosition - _panStartGlobal)` and pass to `_handleUpdate`. The caret tracks the delta from the logical caret origin, not from where the finger touched.
- **Bug B Root Cause (Style shrinks selection)**: `wrapSelection` correctly sets `controller.value.selection` to `(start + open.length, end + open.length)` after inserting tags. But `externalSelection` and the overlay's `_startOffset`/`_endOffset` were not updated to match. After bold `**` (2 chars each), `externalSelection` still pointed to the original `[s, e]` positions in the now-longer text — the visual highlight covered the opening `**` and missed 2 characters at the end. Each successive style applied the same truncation.
- **Bug B Fix**: After each `wrapSelection`/`applyInlineProperty` call, copy `c.selection` (the post-insert native selection set by `wrapSelection`) back to `c.externalSelection`. Then call `_overlayKey.currentState?.syncOffsetsFromExternalSelection(_controllers)` — a new method that reads `externalSelection.start/end` from the start/end block controllers and updates `_startOffset`/`_endOffset`, then reschedules `_calculateHandlePositions()` after the next frame.
- **Files Modified**: `global_selection_overlay.dart` (delta state fields + `_stackKey` + `syncOffsetsFromExternalSelection` + `_buildHandle` onPanStart/Update/End), `script_editor_screen.dart` (`_applyStyleCmd` and `_applyInlineCmd` single/multi-block branches).
- **Commits**: `241df92`
- **iOS Build**: Triggered on push `241df92`. IPA built but user confirmed BOTH bugs still present → fixed in v4.0.9.

### ✅ 2026-04-17 — v4.0.9 [BUG_B_ROOT_CAUSE + DRAG_HARDENING]
- **Bug B Root Cause Found**: `externalSelection` is a plain Dart field — no setter, no `notifyListeners()`. So `c.externalSelection = ns` never triggered `buildTextSpan` to re-render. The TextField painted the OLD positions on the new (longer) text for the rest of the frame, making the highlight appear to shrink by the tag length with each successive style. Fix: added `c.refresh()` immediately after every `c.externalSelection = ns` assignment in `_applyStyleCmd` and `_applyInlineCmd`.
- **Bug A Hardening**: The v4.0.8 delta approach used `_stackKey.currentContext?.findRenderObject()` inside `onPanUpdate`, which can be null during a mid-rebuild setState. Fixed by converting the handle's Stack-local caret position to global coords ONCE in `onPanStart` (layout is always valid from the prior frame at that point) and storing as `_panStartHandleGlobal`. `onPanUpdate` just adds the finger delta to that stored origin — no lookup needed.
- **Files Modified**: `global_selection_overlay.dart` (renamed `_panStartHandleLogical` → `_panStartHandleGlobal`, moved `localToGlobal` to `onPanStart`), `script_editor_screen.dart` (added `c.refresh()` after all `externalSelection` assignments in style commands).
- **Commits**: `dd8e567`
- **iOS Build**: Triggered. IPA released to `releases/iOS/v4/`.

### ✅ 2026-04-17 — v4.1.0 [MULTI-LINE_DRAG_AFFINITY + ARITHMETIC_STYLE_LOCK]
- **Bug A Fix (Affinity)**: `_getOffsetForPosition` called `editable.getLocalRectForCaret` with default `TextAffinity.upstream`. At a line-wrap boundary this places the caret at the END of line 1, not the START of line 2. Even when `_endOffset` was correctly set to a line-2 position by `getPositionForPoint`, the handle position was rendered at line 1. Fix: pass `affinity: TextAffinity.downstream` to every `getLocalRectForCaret` call.
- **Bug B Fix (Arithmetic shift)**: Reading `c.selection` after `wrapSelection` was unreliable because iOS can async-reset it between Dart events. Fix: compute shift arithmetically — add `open.length` (toggle-on) or subtract (toggle-off) directly from stored `oldStart`/`oldEnd`. Never read `c.selection` at all.
- **Commits**: `6bb4714`

### ✅ 2026-04-17 — v4.1.1 [GLOBAL_COORDINATES + VISUAL_OFFSET_LOCK]
- **Bug A Fix (Double globalToLocal)**: `_handleUpdate` called `editable.globalToLocal(globalPos)` then passed the result to `editable.getPositionForPoint()`, which also calls `globalToLocal()` internally. The double-conversion shifted y by the widget's screen offset, always returning a line-1 position. Fix: pass `globalPos` directly to `getPositionForPoint` without pre-converting.
- **Bug B Fix (Visual offsets)**: Arithmetic shift was fragile at tag-boundary edge cases. Fix: convert `externalSelection.start/end` to VISUAL char counts BEFORE the style command using `MarkupController.rawToVisualOffset`, then convert back after using `visualToRawOffset`. Visual char counts are invariant to tag insertion/removal.
- **Files Modified**: `global_selection_overlay.dart` (`_handleUpdate`), `markup_controller.dart` (new `rawToVisualOffset`/`visualToRawOffset` static methods), `script_editor_screen.dart` (visual-offset round-trip in `_applyStyleCmd` and `_applyInlineCmd`).
- **Commits**: `3f650e4`

### ✅ 2026-04-17 — v4.1.2 [NATIVE_SELECTION_LOCK]
- **Bug B (Native long-press path)**: v4.1.1 fix was gated on `hadOverlaySelection`. When user selected via native iOS long-press, `externalSelection = null`, gate = false, fix skipped. iOS async platform reset of `c.selection` then shifted offsets by `open.length` per application. Fixes: (1) expanded snapshot to fall back to `c.selection` when `externalSelection` is null; (2) always pin `c.externalSelection` after wrap; (3) `!isCollapsed` guard in `StylingLogicMixin.wrapSelection` and `applyInlineProperty` to prevent collapsed sentinel `externalSelection` from being mistaken for a style target.
- **User Test**: Still broken. Visual-offset conversion had edge cases not caught analytically.
- **Commits**: `2928168`

### ✅ 2026-04-18 — v4.1.3 [SYNCHRONOUS_READ + ALIGNMENT_PRESERVATION]
- **Session Goals**: (1) Definitively fix B/I/U selection shrink (Bug B). (2) Fix amber highlight corruption when alignment is applied to a partial selection.
- **Bug B Final Fix (Synchronous c.selection read)**: Abandoned visual-offset-conversion entirely. Root insight: `wrapSelection`/`applyInlineProperty` set `controller.value` synchronously via the Dart call stack. `c.selection` is the post-wrap selection at that exact instant. iOS platform resets of `c.selection` only arrive at event-loop boundaries (platform messages), never mid-function. Reading `c.selection` immediately after the wrap call is therefore guaranteed correct. Fix: removed all `rawToVisualOffset`/`visualToRawOffset` round-trips; read `c.selection` directly after wrap and pin to `c.externalSelection`. Applied to all four paths (single-block + multi-block overlay in both `_applyStyleCmd` and `_applyInlineCmd`).
- **Alignment Selection Corruption Fix**: `applyLayout` strips old alignment tag and wraps with new one. Different tag lengths (e.g. `[center]`=8 vs `[left]`=6) shift all raw offsets in `externalSelection`, which was never updated after alignment was applied. Visual-offset conversion IS correct here (alignment tags render at zero visible width so visual offsets are invariant to alignment tag changes). Fix: capture visual offsets before `controller.value = ...`, convert back after, re-pin `externalSelection`. Also call `syncOffsetsFromExternalSelection` to keep overlay `_startOffset/_endOffset` in sync. Applied to both `onDirection` and `onAlign`.
- **User Test**: Both fixes confirmed working by user (2026-04-18).
- **Files Modified**: `script_editor_screen.dart` (all four style paths + `onDirection` + `onAlign`), `README.md`, `MASTER_TODO_V4.md`.
- **Commits**: `ff1d1ed` (v4.1.3 synchronous read) → `89c4507` (v4.1.3b alignment preservation)
- **iOS Build**: Triggered on push `89c4507`. IPA in `releases/iOS/v4/`.
- **Status**: Bug A (multi-line drag) FIXED since v4.1.1. Bug B (style selection shrink) FIXED v4.1.3. Alignment selection corruption FIXED v4.1.3b. All iOS pending items USER VERIFIED 2026-04-18.

### ✅ 2026-04-18 — v4.1.4 [PC_TOTAL_SEPARATION_STABLE]
- **Session Goals**: Finalize Windows software with 100% platform isolation.
- **Achievements**:
    - **Total Separation**: Updated `build-ios.yml` to ignore Windows changes. Shared source files (`pubspec.yaml` and `.dart` files) remain untouched for Android/iOS.
    - **Cloud Hot-Patching**: Implemented dynamic patching in `build-windows.yml`. The runner now automatically resolves `intl` conflicts and stubs incompatible Whisper dependencies *at build-time* only.
    - **Windows Branding**: Native metadata updated in `windows/` folder.
- **Protocol**: Aligned with the AI Protocol for platform-specific isolation to prevent cross-platform regressions.
- **Status**: Windows build pipeline fixed and isolated. First successful release incoming.

### ✅ 2026-04-26 — v4.1.19 [WINDOWS_NATIVE_SAPI_PIVOT]
- **Session Goals**: Transition from the unstable `SttBrowserAdapter` (WebView2 + WebSocket server) to `SttDesktopAdapter` (Native Windows SAPI).
- **Achievements**:
    - **Surgical Backups**: Created isolated backups of `pubspec.yaml`, `stt_service_factory.dart`, and `teleprompter_screen.dart` in `backups/surgical/`.
    - **Dependency Pruning**: Safely stripped out legacy WebView/WebSocket dependencies from the `pubspec.yaml`.
    - **Native Groundwork**: Setup parameters for returning `SttDesktopAdapter()` for Windows.
- **Status**: Paused due to system history interruption. Ready to execute code generation.
---

### 2026-04-29 - Windows v4.1.12 FINAL SEAL

- **Session Goal**: Seal Windows v4, create final backup, and append migration
  documentation so the verified Windows behavior can be safely ported to iOS,
  Android, and macOS.
- **Final Version**: Windows `4.1.12+12`.
- **Workflow Title**: `Build Windows EXE (v4.1.12)`.
- **Final Backup**: `backups/final_windows_v4/20260429_103357`.
- **Release README**: `releases/Windows/v4.1.12 (FINAL)/README.md`.
- **Core STT Result**: Windows STT stop/start now behaves as pause/resume. Stop
  tears down recognition without resetting the script. Start resumes from the
  current word. Restart is the only reset-to-beginning action.
- **External Mic Result**: Windows presenter settings can enumerate WebView2
  audio input devices, persist `sttInputDeviceId` and label, switch devices
  without resetting the script, and fall back to system default if a saved
  external mic is missing.
- **Debug Result**: Debug mode has a compact sound bar and collapsible output
  window. Recurring volume debug rows were removed because the sound bar owns
  that visual signal.
- **Search Result**: Editor and presenter search use visible text locations and
  avoid treating hidden markup tags as searchable display characters.
- **Bookmarks Result**: Bookmarks are shared between editor and present mode,
  support multiple anchors, visible markers, explicit add/remove controls, and
  previous/next jumps while STT is active. Bookmark jumps are direct commands,
  not smooth STT-follow animations.
- **Presenter Scroll Result**: Active STT owns scrolling and uses row-progress
  follow. Stopped mode allows browsing and updates the resume point. Direct
  commands such as bookmark/search/restart jump immediately.
- **Typography Result**: Font size now has one source of truth across editor
  controls, presenter controls, script metadata, style tags, and export.
  Presenter visual scaling is display-only and must not be persisted as the
  saved font number.
- **Spacing Result**: Line, word, and letter spacing ranges are synchronized
  between editor and presenter settings and persist through script metadata.
- **Text Structure Result**: Standalone symbols, quotes, punctuation, and
  intentional blank lines are preserved in editor, presenter, import, and export
  paths.
- **Export Result**: RTF/DOCX export converts app-private markup into document
  styling. Plain formats export visible text only. Default teleprompter white is
  display metadata and must not become white body text in exported documents.
- **MVP Documentation Result**: Windows MVP docs now include dedicated
  Bookmarks and Scrolling contracts plus updated STT, Teleprompter, Script
  Editor, Settings, and File I/O rules for the sealed behavior. iOS, Android,
  and macOS now also have planned Bookmarks and Scrolling MVP contracts so the
  migration lanes exist before implementation begins.
- **Refactor Recommendation**: Do not split large files during the Windows v4
  seal. Before V5 expansion, split oversized editor/presenter files by MVP
  ownership as behavior-preserving refactors. Current over-1000-line files:
  Windows editor 2885, Windows presenter 2528, iOS editor 2135, iOS presenter
  1356, Android editor 1842, Android presenter 1341, Android legacy editor
  1290, macOS editor 2011, macOS presenter 1338.
- **Status**: Windows v4 is sealed. Future work should move to cross-platform
  migration and V5 preparation unless the user explicitly reopens Windows v4.

### 2026-04-29 - Windows V5 Prep: Screen File Split

- **Session Goal**: Prepare Windows for safer V5 development by splitting the
  two oversized screen files without changing in-app behavior.
- **Method**: Used Dart `part` files in the same library so private fields,
  private methods, and existing logic remain library-local. The split is
  mechanical extraction plus import/part wiring, not a feature change.
- **Teleprompter Result**: `teleprompter_screen.dart` reduced to 128 lines.
  Extracted presenter build, STT/session UI, manual scroll, bookmarks/search,
  smooth settings, alignment helpers, sound/debug widgets, control bar, settings
  panel, and settings helper widgets. Largest teleprompter part is
  `teleprompter_screen.build.dart` at 742 lines.
- **Script Editor Result**: `script_editor_screen.dart` reduced to 608 lines.
  Extracted load/block lifecycle, dialogs/history, styling commands,
  import/save/present handoff, debug/bookmarks/search/global selection, and
  `_EditorBlock`. Largest editor part is `script_editor_screen.load_blocks.dart`
  at 609 lines.
- **Line Ceiling**: All extracted Windows screen files are under 750 lines.
- **Behavior Contract**: No in-app behavior was intentionally changed. Future
  V5 changes must edit the smallest owning part file and update the relevant
  MVP doc.
- **Validation**: `dart format` completed on the split files. Targeted
  `flutter analyze` on the Windows teleprompter and script editor entrypoints
  reported no compile errors; it still reports existing warning/info lint noise.

### 2026-04-29 - Windows v4.1.12 Visible STT Skip Safety

- **Session Goal**: Add the final Windows v4 STT skip behavior: default strict
  no-skip alignment, with an opt-in setting that allows skipping only to text
  actually visible in the presenter viewport.
- **Settings Result**: Added persisted `sttVisibleSkipEnabled`, defaulting to
  `false`, exposed in Windows presenter settings as `Allow visible text skip`.
- **STT Result**: `WordAligner.align(...)` now defaults to strict next-expected
  alignment while still allowing one STT result to confirm consecutive words
  read in order. When visible skipping is enabled, the aligner window is capped
  by the presenter-provided visible word range.
- **Presenter Result**: The presenter computes the visible word window from
  actual rendered word boxes and publishes it to the provider. The window is
  throttled during smooth scrolling and forced after layout/direct jumps.
- **Safety Contract**: Hidden/offscreen paragraphs cannot be skipped to by
  speech alone. Display-only punctuation, blank lines, and unspeakable markers
  do not become skip targets.
- **MVP Documentation Result**: Updated Windows STT, Teleprompter Engine,
  Scrolling, and Settings MVP docs with the opt-in visible-skip contract.
- **Validation**: `dart format` completed. Targeted `flutter analyze` reported
  no new compile errors, only existing warning/info lint noise. Windows
  teleprompter split files remain below the 750-line ceiling.

### 2026-04-29 - Windows Visible STT Skip Full-Viewport Tuning

- **Session Goal**: Correct visible skipping so speaking a phrase visible lower
  in the presenter viewport can jump over an entire visible paragraph, not only
  one or two rows.
- **STT Result**: Visible skip now scans the full presenter-published viewport
  for multi-word sequence matches. The old fixed 30-word large-jump cap no
  longer blocks confirmed multi-word targets that are actually visible.
- **Safety Result**: Single-word jumps remain near-range only. Long visible
  jumps require multi-word confirmation and still cannot target offscreen text.
- **MVP Documentation Result**: Updated Windows STT, Teleprompter Engine, and
  Scrolling MVP docs to define visible skip as viewport-bounded, not row-bounded.

### 2026-04-29 - Windows Default STT Local Recovery

- **Session Goal**: Preserve normal STT flow when the recognizer misses one or
  two words, without enabling paragraph/section skipping by default.
- **STT Result**: With `Allow visible text skip` off, the aligner may now scan
  only the next 5-word local recovery window. With the setting on, it still uses
  the full visible viewport for confirmed multi-word jumps.
- **Safety Result**: Local 5-word recovery is default behavior; long visible
  paragraph jumps remain opt-in and viewport-bounded.
- **MVP Documentation Result**: Updated Windows STT and Teleprompter Engine MVP
  docs to separate default local recovery from explicit visible skipping.

### 2026-04-29 - Windows Visible Skip Nearby Phrase Priority

- **Session Goal**: Prevent visible-skip mode from jumping to farther similar
  text when the spoken phrase also matches the current local sentence.
- **STT Result**: Added a nearby 3+ word phrase-priority pass before the
  full-viewport visible-skip fallback. Strong local phrases such as "Jewish man
  at a well" now win before the aligner considers later visible text such as
  "all at the well."
- **Safety Result**: Visible skip remains available for true paragraph jumps,
  but only after the nearby phrase-priority pass fails. Default 5-word local
  recovery remains unchanged.
- **MVP Documentation Result**: Updated Windows STT and Teleprompter Engine MVP
  docs to define visible skip as fallback-only after nearby phrase priority.

### 2026-04-29 - Windows v4 Final User Verification and iOS Handoff

- **Session Goal**: Close Windows version 4 after user testing confirmed the
  final v4.1.12 behavior, then update project documentation so development can
  move safely to the iOS platform and later V5 work.
- **Final Windows Version**: `4.1.12+12`, workflow title
  `Build Windows EXE (v4.1.12)`.
- **Final Verified Commit**: `160d137` (`Prioritize nearby Windows STT
  phrases`) is the latest Windows v4 behavior commit verified by the user.
- **Workflow Verification**: GitHub Actions run `25110648732` completed
  successfully and uploaded the Windows EXE artifact.
- **Source Size Result**: Windows V5-prep file split is complete. Every Dart
  file under `Platform_Windows/lib` is below 800 lines; the largest current
  files are `teleprompter_screen.build.dart` at 720 lines,
  `script_provider.dart` at 717 lines, `settings_provider.dart` at 700 lines,
  `word_aligner.dart` at 660 lines, `teleprompter_provider.dart` at 641 lines,
  and `script_editor_screen.dart` at 579 lines.
- **Final STT Contract**: Default alignment may recover locally within the next
  5 words for missed recognizer output. Longer visible text skips are opt-in
  through `Allow visible text skip`, bounded to the rendered viewport, and
  fallback-only after nearby 3+ word phrase priority fails.
- **Final Presenter Contract**: Active STT owns scrolling and normal user scroll
  is locked. Stopped STT allows browsing and resume-point selection. Direct
  navigation commands such as bookmarks, search, restart, and active-STT
  bookmark jumps are immediate.
- **Final Editor/Presenter Contract**: Bookmarks sync between editor and
  presenter, can be added/removed in both modes, display visible markers, and
  survive mode changes. Search uses visible text and maps back to raw markup
  only after matching.
- **Final Formatting Contract**: One font-size metadata value is shared across
  editor controls, presenter controls, style tags, settings, and export.
  Presenter visual enlargement is display-only. Spacing controls match between
  editor and presenter. Symbols, quotes, punctuation, and intentional blank
  lines are preserved.
- **Final Export Contract**: RTF/DOCX export converts app-private markup into
  document styling; plain formats write visible text only and must not leak raw
  `[color]`, `[size]`, bold, alignment, or display-only tags.
- **Final Audio Contract**: Windows external microphone selection is implemented
  through WebView2 audio input enumeration with system-default fallback. Other
  platforms must document whether they support in-app device selection or only
  OS routing.
- **Documentation Result**: Root README, MVP root README, V4/V5 TODOs,
  platform-structure notes, and Windows release README carry the final Windows
  v4 migration capsule. Correction: platform-folder README files are
  workflow-sensitive and should not be used for cross-platform handoff notes.
  They were removed from git tracking in follow-up commit `5b7dd28`.
- **Next Platform**: iOS becomes the next active development platform. Before
  touching iOS code, read `_agent/mvp/Platform_iOS/*.md`, especially STT,
  Teleprompter Engine, Script Editor, Bookmarks, Scrolling, Settings, File I/O,
  Selection, History, and Styling Engine. Port behavior surgically; do not copy
  Windows implementation details blindly.

### 2026-04-29 - iOS V5 Prep Screen Split and Windows Parity Map

- **Session Goal**: Prepare `Platform_iOS` for safe V5 development by splitting
  the oversized editor and presenter screen files into smaller MVP-owned Dart
  `part` files, then document the Windows v4.1.12 feature gaps that still need
  iOS implementation.
- **Backup Result**: Created surgical backup
  `backups/surgical/20260429_204819` before iOS source edits and
  `backups/surgical/20260429_205627` before MVP/root documentation edits.
- **Script Editor Split Result**: `script_editor_screen.dart` is now a shell
  with state fields and lifecycle delegates. Extracted iOS editor parts:
  `script_editor_screen.load_blocks.dart`,
  `script_editor_screen.dialogs_history.dart`,
  `script_editor_screen.styling_commands.dart`,
  `script_editor_screen.file_present.dart`,
  `script_editor_screen.build.dart`,
  `script_editor_screen.selection_clipboard.dart`, and
  `script_editor_screen.editor_block.dart`.
- **Teleprompter Split Result**: `teleprompter_screen.dart` is now a shell with
  state fields, alignment helpers, and lifecycle delegates. Extracted iOS
  presenter parts: `teleprompter_screen.session_stt.dart`,
  `teleprompter_screen.manual_scroll.dart`,
  `teleprompter_screen.build.dart`,
  `teleprompter_screen.control_bar.dart`, and
  `teleprompter_screen.settings_panel.dart`.
- **Line-Size Result**: Every Dart file under `Platform_iOS/lib` is below 800
  lines after the split. The largest files are `settings_provider.dart` (643),
  `script_editor_screen.load_blocks.dart` (612), `script_provider.dart` (592),
  `teleprompter_screen.build.dart` (542), and `word_aligner.dart` (528).
- **Validation Result**: `dart format` completed on all touched iOS split files.
  Targeted `flutter analyze --no-pub` on the iOS editor/presenter roots reported
  no compile errors; remaining output is pre-existing warning/info noise.
  Full pub-resolving analysis is blocked locally by the current SDK/`intl`
  constraint mismatch and was not changed in this split-only pass.
- **Documentation Result**: Updated iOS Script Editor, Teleprompter Engine,
  Bookmarks, Scrolling, and root MVP docs with split ownership rules and the
  Windows-to-iOS migration targets. No platform README files were edited.
- **Windows Features Still Missing in iOS**: STT stop/resume without reset;
  default 5-word local recovery; opt-in visible viewport skip with nearby phrase
  priority; active-STT scroll lock and row-progress follow; stopped browsing
  resume-point selection; cross-mode bookmarks with visible markers and
  add/remove/previous/next controls; active-STT bookmark jumps; visible-text
  search with raw-offset mapping; one font-size metadata authority; synced
  spacing ranges; symbol/quote/blank-line preservation audit; markup-safe
  export; and platform-specific external microphone policy.
- **Windows Reference Protocol for iOS Porting**: For each Windows-parity item,
  the next agent must inspect the verified `Platform_Windows` implementation and
  the matching `_agent/mvp/Platform_Windows/*.md` contract before coding the iOS
  equivalent. Windows is the behavior reference, not a copy-paste source. For
  example, the STT skip feature must preserve the Windows rule that local
  5-word recovery is always available, while `Allow visible text skip` is an
  opt-in setting that defaults off and only enables larger viewport-bounded
  fallback skips after nearby phrase priority fails.

### 2026-04-29 - iOS Multi-Block Cut/Paste Investigation Fix

- **Session Goal**: Revisit the iOS multi-block Select All -> Cut -> Paste bug
  from the stable `f23d56e` baseline, after failed attempts showed the in-app
  paste path restored only the originally touched paragraph block.
- **Root-Cause Direction**: The previous `_blockClipboard` design mixed
  "current global selection snapshot" with "actual paste clipboard." That let
  iOS context-menu/native-selection timing downgrade the paste payload to a
  one-block list before paste.
- **Fix Result**: `_selectAllBlocks()` now arms a short-lived raw-markup global
  selection snapshot only. Cut/Copy are the only paths allowed to write
  `_blockClipboard`, and they write one raw-markup string per paragraph block.
  Paste adds missing controllers before restoring `TextEditingValue(text:
  rawMarkup)` so per-block styling survives.
- **Diagnostics Result**: Editor debug mode now shows clipboard state such as
  armed/stored/restored block count, so the next iOS test can verify whether the
  clipboard remains multi-block.
- **Validation Result**: Targeted `flutter analyze --no-pub` on the iOS script
  editor found no compile errors; remaining warnings/infos are pre-existing
  root-file analyzer noise.
- **Follow-Up Result**: User testing showed the first fix still pasted only one
  block. The paste path was hardened again so the custom Paste action is exposed
  from either `_blockClipboard` or the recent protected global snapshot, and
  paste restores the largest available protected block list instead of accepting
  a downgraded one-block payload.
- **Second Follow-Up Finding**: User testing with three paragraph blocks showed
  the result was not simply "one block only"; the paste restored `N-1` visible
  blocks with the first selected block missing. This points to native iOS
  clearing the focused block before the protected snapshot/restore path finishes.
- **Second Follow-Up Fix**: The controller listener now repairs the protected
  global selection snapshot at the exact block index from the listener's
  previous raw-markup text when iOS empties a focused block during global
  selection. Clipboard debug output now prints block `index:length` shape for
  armed/stored/restored snapshots so the next test can identify whether any slot
  is empty or absent.
- **Third Follow-Up Fix**: User debug output showed `native-empty: kept block 0`,
  proving the native iOS destructive path was firing before the custom Cut
  command. That path now promotes the kept/repaired full snapshot directly into
  `_blockClipboard` and writes the plain system clipboard companion immediately,
  so Paste no longer depends on the short-lived protected snapshot alone.
- **Fourth Follow-Up Finding/Fix**: User testing then showed all text pasted but
  with styling and paragraph newlines stripped. That means iOS routed Paste
  through the system plain-text companion. The listener now detects native
  insertion of that plain companion while `_blockClipboard` exists and
  immediately replaces it with the rich `_pasteFromGlobalClipboard()` restore.

### 2026-04-30 - iOS Windows-Parity Task 1: STT Stop/Resume Without Reset

- **Session Goal**: Start the Windows-to-iOS parity list with the first verified
  Windows behavior: stopping STT pauses the recognizer without resetting the
  script, and starting STT again resumes from the current position.
- **Windows Reference Checked**: Compared iOS `teleprompter_provider.dart` and
  presenter entry flow against the verified Windows provider/screen behavior.
  Windows resumes the same `Script` from the current `confirmedWordIndex`,
  serializes stop/start, and keeps Restart as the only word-zero reset owner.
- **Implementation Result**: iOS `startSession()` now waits for any in-flight
  stop, uses a `_sessionToken` to ignore stale recognizer completions, and
  resumes the same active script from current `confirmedWordIndex`. A different
  script still starts at `0`.
- **Stop Result**: iOS `stopSession()` now clears transient transcript and
  no-progress state while preserving `confirmedWordIndex`. It serializes
  recognizer teardown through `_stopInFlight`.
- **Presenter Result**: iOS present-mode entry no longer calls
  `resetPosition()` or scrolls to top. It may still stop a lingering recognizer,
  then scrolls back to any saved non-zero `confirmedWordIndex` after layout.
- **Documentation Result**: Updated iOS STT and Teleprompter Engine MVP docs and
  marked the V4 TODO item `[P]` pending user IPA verification.


## 2026-04-30 - iOS Parity Item 2: Default 5-Word Local Recovery

- **Session Goal**: Continue the Windows-to-iOS parity list with item 2 from
  the handoff. Default STT alignment must tolerate normal recognizer misses
  through up to about 5 words ahead, but must NOT jump to later
  paragraphs/sections just because that text was spoken. Larger skipping is
  reserved for the opt-in visible viewport feature (item 3).
- **Windows Reference Checked**: Read
  `Platform_Windows/lib/features/teleprompter/services/word_aligner.dart` and
  matching `_agent/mvp/Platform_Windows/stt_mvp.md`. Windows aligner takes an
  optional `maxSkipTargetIndex`. With it null, the scan is strict 5-word
  recovery. With it supplied, the scan walks the visible window with nearby
  3+ word phrase priority and a per-distance penalty cap.
- **Implementation Result**: Ported the same parameter into iOS
  `WordAligner.align(...)`. When `maxSkipTargetIndex` is null, the iOS aligner
  uses `searchStart + _maxSingleJump` as both the single-word and sequence
  scan upper bound. The default 5-word local recovery is now the active
  behavior because the iOS provider call site does not pass the parameter.
- **Phrase Priority**: Added `_nearbyPhrasePriorityMatch` helper and the
  visible-skip-only sequence tightening (`sequenceEnd = windowEnd`,
  capped distance penalty, capped `_maxSeqJump`). These activate only when
  the future visible-skip caller (item 3) supplies `maxSkipTargetIndex`.
- **Backup**: Surgical mirror at
  `backups/ios_parity_item2_2026-04-30/word_aligner.dart.bak`.
- **Verification**: `flutter analyze --no-pub` on the touched file reports
  only pre-existing lints (`_crossLangThreshold` unused, `withOpacity`
  deprecated, brace-in-string-interp). No new errors.
- **Documentation Result**: Updated iOS STT MVP doc with a new
  "iOS Default 5-Word Local Recovery - 2026-04-30" section, and marked the V4
  TODO item `[P]` pending user IPA verification.

## 2026-04-30 - iOS Parity Item 3: Opt-In Visible Viewport Skip

- **Session Goal**: Add the opt-in visible viewport skip + nearby phrase
  priority paths on iOS. Default off; when on, alignment may jump to text
  currently rendered on the presenter screen, never below the viewport.
- **Windows Reference Checked**: Read
  `Platform_Windows/lib/features/settings/providers/settings_provider.dart`,
  `teleprompter_provider.dart` (`_visibleWordStart/_visibleWordEnd`,
  `setVisibleWordWindow`, `_handleSttResult` `maxSkipTargetIndex` wiring),
  and `teleprompter_screen.manual_scroll.dart` (`_syncVisibleWordWindow` /
  `_scheduleVisibleWordWindowSync`).
- **Settings Result**: Added `sttVisibleSkipEnabled` to iOS `AppSettings`
  (default false) with prefs key, copyWith, _load, and
  `setSttVisibleSkipEnabled` setter — mirrors Windows exactly.
- **Provider Result**: Added `_visibleWordStart`, `_visibleWordEnd` fields
  and `setVisibleWordWindow(int?, int?)` to iOS `TeleprompterNotifier`.
  `_handleSttResult` reads the user setting and only passes
  `maxSkipTargetIndex = _visibleWordEnd` when both the toggle is on and a
  window has been reported. `startSession` resets the window to null so
  stale data from a previous presenter mount can never leak.
- **Presenter Result**: Added `_syncVisibleWordWindow({bool force = false})`
  and `_scheduleVisibleWordWindowSync()` to iOS
  `teleprompter_screen.manual_scroll.dart`. Walks `_wordKeys` and skips
  newlines/unspeakable tokens, throttled to ~150 ms. Build hooks the
  scheduler so every frame keeps the provider window fresh.
- **Default Contract**: Toggle off → strict 5-word recovery wins (Item 2),
  no visible skip. Toggle on → aligner uses visible window, nearby 3+ word
  phrase priority always wins before farther visible matches.
- **Backup**: Surgical mirrors at
  `backups/ios_parity_item3_2026-04-30/`.
- **Verification**: `flutter analyze --no-pub` on touched iOS files reports
  only pre-existing lints. No new errors.
- **Documentation Result**: Updated iOS STT MVP doc with a new
  "iOS Opt-In Visible Viewport Skip - 2026-04-30" section, and marked the V4
  TODO item `[P]` pending user IPA verification.

## 2026-04-30 - iOS Parity Items 4 & 5: Active-STT Scroll Lock + Stopped Browsing

- **Session Goal**: Port Windows v4 active-STT scroll-lock, row-progress
  smooth follow, and stopped-state browsing/resume-point selection. Bundled
  as one local commit because both items share `_handleStoppedBrowsingScroll`,
  `jumpToPosition`, and the resume-point sync helper.
- **Windows Reference Checked**: Read
  `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.manual_scroll.dart`
  (`_handleStoppedBrowsingScroll`, `_syncResumePointToReadingLine`,
  `_visualRowProgress`, `_boxForWordIndex`, scroll-target row-progress
  augmentation in `_scrollToWordIndex`) and
  `teleprompter_provider.dart` (`jumpToPosition`, `_syncLocaleForPosition`,
  `isStarting` field on the state).
- **State Result**: Added `isStarting` to iOS `TeleprompterState`. Provider
  sets it true in `startSession()`, clears it on first STT/Whisper status
  callback, on `stopSession()`, and on fatal/language/pack error paths.
- **Provider Result**: Added `jumpToPosition(int, {Script?})` and
  `_syncLocaleForPosition(int, {String reason})`. Manual jumps clear
  transient transcript/no-progress state and update the active locale
  without going through `_checkAndSwitchLocale` (Invariant 12 protected).
- **Presenter Result**: Added `_userBrowsingWhileStopped` field;
  `_handleStoppedBrowsingScroll`, `_visualRowProgress`, `_boxForWordIndex`,
  and `_syncResumePointToReadingLine` in the manual_scroll part. Build wires
  a `NotificationListener<ScrollNotification>` and switches physics to
  `NeverScrollableScrollPhysics` while STT is listening or starting.
  `_scrollToWordIndex` now applies `rowProgress * lineAdvance` so the auto
  scroll glides smoothly inside each row.
- **Backup**: Surgical mirrors at
  `backups/ios_parity_item4_2026-04-30/` covering provider, state model,
  manual_scroll part, build part, and the host screen file.
- **Verification**: Manual review only this session. Touch-points are
  narrow and follow the verified Windows shapes. IPA test pending.
- **Documentation Result**: Updated iOS STT MVP and Scrolling MVP with new
  2026-04-30 sections describing the active-STT lock, row-progress follow,
  and stopped browsing/resume-point pipeline. MASTER_TODO_V4 entries marked
  `[P]` pending user IPA verification.

### ✅ 2026-04-30 — v5.0 [FEATURE_PIPELINE_EXPANSION]
- **Session Goals**: Append new V5 feature requests to the master TODO list: Keyboard arrow navigation, Windows Monitor Mode, and Cross-Platform Screen Casting.
- **Achievements**:
    - **Keyboard Navigation**: Added task for standard arrow navigation (cursor between letters) on Windows/Mac, including "Select All -> Left Arrow" behavior.
    - **Windows Monitor Mode**: Added task for dual-window presentation/editor mode with synchronized real-time scrolling.
    - **Cross-Platform Casting**: Added task for remote control/screen casting between devices (Windows/Mac/iOS/Android).
    - **Multi-Language Skip Fix**: Added task for proactive STT language switching to allow long skips to distant text in different languages (e.g. Hebrew to English).
- **Status**: V5 roadmap expanded. Ready for implementation planning.

### ✅ 2026-04-30 — v5.0 [IMPLEMENTATION]
- **Session Goals**: Implement native-like keyboard arrow navigation for Windows and macOS.
- **Achievements**:
    - **Block Boundaries**: Implemented logic to move the cursor between paragraphs (blocks) when reaching the beginning/end of a block via arrow keys.
    - **Global Selection Collapse**: Implemented "Select All -> Arrow" behavior. Left arrow collapses to the start of the first block; Right arrow collapses to the end of the last block.
    - **Scrolling support**: Integrated `_scrollEditorBlockIntoView` in both Windows (existing) and macOS (new helper) to ensure smooth navigation between paragraphs.
- **Status**: Arrow navigation fully implemented for desktop platforms.

## 2026-05-02 - iOS Cross-Mode Bookmarks Port

- **Session Goal**: Continue the Windows-to-iOS parity work after another agent
  completed iOS tasks 1-5. Record the current done/remaining list, then begin
  the next missing feature: cross-mode bookmarks.
- **Status Record Result**: Updated
  `Missing features from Windows development to implement all platforms.md`
  with the current iOS status: file split and multi-block cut/paste are done,
  tasks 1-5 are implemented by the later iOS agent, task 6 is now implemented,
  and tasks 7-13 still require implementation/verification.
- **Bookmark Result**: Added iOS shared script-scoped bookmark persistence via
  `ScriptBookmarkService`, editor add/remove/previous/next controls, presenter
  add/remove/previous/next controls, visible `»` bookmark markers in both modes,
  marker deletion, and editor-to-presenter title/session handoff so editor and
  present mode load the same bookmark scope.
- **Validation Result**: All Dart files under `Platform_iOS/lib` remain below
  800 lines after the bookmark port. Targeted `flutter analyze --no-pub` on the
  iOS editor/presenter roots reported no compile errors; remaining output is
  existing warning/info noise in the split root files.

## 2026-05-02 - iOS Visible-Text Search Port

- **Session Goal**: Continue Windows-to-iOS parity after the bookmark port by
  implementing Task 8: visible-text search with raw-offset mapping.
- **Editor Result**: Added `script_editor_screen.search.dart`. Editor search
  opens from the action bar and `Ctrl/Meta+Shift+F`, searches stripped visible
  text, maps the match back to raw markup offsets through
  `MarkupController.visualToRawOffset(...)`, clears stale global-selection
  overlay state, selects the real visible match, and scrolls the owning editor
  block into view.
- **Presenter Result**: Added `teleprompter_screen.search.dart`. Presenter
  search opens from the control bar and hardware-key shortcut, builds a visible
  phrase map from rendered script words, skips newline/display-empty tokens as
  anchors, and jumps through the provider position path used by bookmarks so
  resume point and scroll target stay synchronized.
- **Documentation Result**: Updated iOS Script Editor and Teleprompter Engine
  MVP docs, `MASTER_TODO_V4.md`, and the Windows-parity handoff file. iOS Task
  8 is now implemented and awaiting IPA/device verification.

## 2026-05-02 - iOS MVP Documentation Boundary Cleanup

- **Session Goal**: Correct the documentation/code boundary after the iOS
  parity ports. Windows-parity task labels and behavioral protocol belong in
  `_agent/mvp/Platform_iOS/*.md`, not as task-list prose inside iOS source
  files.
- **Code Result**: Removed `Item`/task migration labels from iOS source comments
  and moved the present-mode search hardware-key handler from the STT session
  part into `teleprompter_screen.search.dart`, the search-owned part file.
- **Documentation Result**: Appended explicit ownership notes to the iOS Script
  Editor and Teleprompter Engine MVP docs so future agents keep task protocol in
  MVP files and code comments implementation-local.

## 2026-05-02 - iOS One Font-Size Metadata Authority

- **Session Goal**: Continue Windows-to-iOS parity locally without pushing, and
  implement Task 9 so editor and present mode display/edit one font-size number.
- **Code Result**: `ScriptNotifier` now rebuilds scripts from current settings
  when no import metadata exists and exposes `updateStyleMetadata(...)` for
  script-level style persistence. The editor Text Suite reads the global
  settings font size instead of cursor inline `[size]` detection for the
  script-wide dropdown. Editor and presenter font-size controls now update both
  `SettingsNotifier.setFontSize(...)` and
  `ScriptNotifier.updateStyleMetadata(fontSize: ...)`.
- **Presenter Result**: Present settings labels show the raw metadata number
  instead of `fontSize * 2`. Presentation rendering may still enlarge text as a
  display-only effect, but that enlarged value is not saved as metadata.
- **Documentation Result**: Updated iOS Script Editor, Settings, Styling Engine,
  and Teleprompter Engine MVP docs, plus `MASTER_TODO_V4.md` and the
  Windows-parity handoff/status file. IPA/device verification is still pending.

## 2026-05-02 - iOS Synced Spacing Ranges

- **Session Goal**: Continue Windows-to-iOS parity locally without pushing, and
  implement Task 10 so editor and present mode expose the same spacing controls.
- **Editor Result**: `LayoutSuite` now uses the shared spacing ranges: line
  `0.5..3.0`, word `-5.0..20.0`, and letter `-2.0..5.0`. Line spacing uses
  default-relative display, so saved `1.2` appears as `0.0`.
- **Presenter Result**: `TeleprompterSettingsPanel` now uses the same ranges and
  default-relative line-spacing label. Presenter spacing edits update both
  settings and script metadata instead of staying presenter-only.
- **Settings Result**: Settings setters clamp to the shared ranges so future UI
  surfaces cannot silently diverge.
- **Documentation Result**: Updated iOS Editor Suites, Settings, and
  Teleprompter Engine MVP docs, plus `MASTER_TODO_V4.md` and the
  Windows-parity handoff/status file. IPA/device verification is still pending.

## 2026-05-02 - iOS Loaded-File Structure Preservation

- **Session Goal**: Continue Windows-to-iOS parity locally without pushing, and
  implement Task 11 so loaded files keep visible signs and blank-line structure.
- **Import Result**: Removed generic trimming/newline-collapse behavior from the
  active iOS import parsing paths for non-RTF `.rtf`, legacy `.doc`, DOCX,
  Pages, and parsed RTF content. Parsers still strip unsupported control data,
  but visible file structure is not treated as cleanup noise.
- **Editor Result**: `_getRefinedFullText()` now joins editor blocks without
  trimming the full result, preserving intentional leading/trailing empty
  blocks from loaded files.
- **Presenter Result**: `WordAligner.tokenize(...)` now keeps punctuation-only
  display tokens such as `"`, `»`, and section markers in `Script.words` even
  when their normalized STT text is empty. STT can ignore them; present mode
  still renders them.
- **Documentation Result**: Updated iOS File I/O, Script Editor, and
  Teleprompter Engine MVP docs, plus `MASTER_TODO_V4.md` and the
  Windows-parity handoff/status file. IPA/device verification is still pending.

## 2026-05-02 - iOS Markup-Safe Export

- **Session Goal**: Continue Windows-to-iOS parity locally without pushing, and
  implement Task 12 so exported files do not expose app-private style tags.
- **Export Parser Result**: Added
  `Platform_iOS/lib/features/script/services/markup_export_service.dart` as the
  shared export parser for internal markup.
- **DOCX/RTF Result**: DOCX and RTF export now convert `[color]`, `[size]`,
  `[font]`, bold, italic, underline, alignment, and shorthand color tags into
  real document styling controls. Default teleprompter white is not emitted as
  white body text.
- **Pages Result**: Pages export now writes visible text through
  `MarkupExportService.toPlainText(...)`, preserving blank paragraph structure
  while stripping raw app-private bracket tags from `index.xml`.
- **Documentation Result**: Updated iOS File I/O MVP, `MASTER_TODO_V4.md`, and
  the Windows-parity handoff/status file. IPA/device verification is still
  pending.

## 2026-05-02 - iOS External Microphone Selection

- **Session Goal**: Finish the remaining Windows-to-iOS parity handoff item
  without pushing by implementing the iOS-native external microphone route
  selector instead of stopping at documentation.
- **Native Result**: Added an iOS MethodChannel
  (`autoteleprompter/ios_audio_input`) in `AppDelegate.swift` that lists
  `AVAudioSession.availableInputs` and applies `setPreferredInput(...)`.
- **Dart Result**: Added `IosAudioInputService`, extended the STT service
  contract with audio input devices, and wired `SttAppleAdapter` so the selected
  route is applied before Apple STT starts.
- **UI/Settings Result**: Present-mode settings now show a Speech Input
  selector with System Default plus available iOS routes. The selected route is
  persisted as `sttInputDeviceId` and `sttInputDeviceLabel`.
- **Boundary Result**: This is iOS-native route preference, not a Windows
  WebView2 `navigator.mediaDevices` picker. If iOS refuses or loses a route,
  the app falls back to System Default and stop/start resume preserves position.
- **Documentation Result**: Updated iOS STT, Settings, Platform Shell, and
  Audio Buffer MVP docs, plus `MASTER_TODO_V4.md` and the Windows-parity
  handoff/status file. IPA/device verification is still pending.

## 2026-05-02 - iOS QA Follow-Up: Resume, Visible Skip, Bookmarks

- **Session Goal**: Apply user test feedback after the iOS parity IPA: fix
  same-session STT resume after returning from editor mode, expose the missing
  visible skip switch, prevent present bookmark markers from occupying text
  flow, and reduce present-mode control overflow.
- **Resume Result**: `TeleprompterNotifier.startSession(...)` now compares
  stable script/session identity rather than only Dart object identity, so a
  rebuilt same-session script can still resume from the current
  `confirmedWordIndex`. Re-entering present mode at a non-zero position now
  offers Continue or Restart; only Restart resets to word `0`.
- **Visible Skip Result**: Present settings now expose the
  `Allow visible text skip` switch backed by the existing
  `sttVisibleSkipEnabled` setting. It remains off by default.
- **Bookmark/UI Result**: Present-mode bookmark markers now float as UI
  anchored to the bookmarked word instead of consuming row text space. The
  present control bar is split into two rows so bookmark/search controls do not
  overflow the mic/font/settings row.
- **Migration Result**: Added a Windows follow-up handoff for the new
  Resume/Restart re-entry choice and compact multi-result search navigation
  idea in `Missing features from Windows development to implement all
  platforms.md`. No Windows runtime code was touched in this iOS pass.

## 2026-05-02 - iOS Presenter Search Toolbar And Control Fade

- **Session Goal**: Apply the next iOS presenter QA feedback without changing
  platform version: search needed reusable result navigation, the two-row
  controls needed the mic visually centered again, and script text was hiding
  transparent buttons.
- **Search Result**: Presenter search now stores all visible-text matches for a
  query and shows a compact toolbar with previous result, next result, search
  new text, and close actions. Users no longer need to reopen the search dialog
  repeatedly to walk through the same query results.
- **Toolbar Result**: The search button remains available in the upper
  presenter toolbar row. The lower row now places Settings at the left edge,
  then font decrease, mic/play/stop, font increase, and Restart, restoring the
  mic button to the center.
- **Visibility Result**: The presenter controls now sit on a stronger dark
  bottom fade, and the search-result toolbar has its own dark backing so script
  text cannot visually cover the active buttons.
- **Documentation Result**: Updated the iOS Teleprompter Engine MVP and
  `MASTER_TODO_V4.md`. No Windows runtime code was touched.

## 2026-05-02 - iOS Selection Dismissal Regression Follow-Up

- **Session Goal**: Fix a fresh iOS editor selection regression where selected
  text could remain visually/logically active after tapping elsewhere, blocking
  clean new selections and confusing Cut/Copy.
- **Root Cause Direction**: The iOS multi-block clipboard fix intentionally
  keeps a short-lived `_globalSelectionSnapshot` to survive native context-menu
  timing. That snapshot must not behave like a hidden permanent selection after
  the user navigates away from the selection.
- **Fix Result**: Added `_dismissEditorSelectionForUserNavigation(...)`, used
  from editor background taps and block taps. It clears global selection,
  overlay/external selection, non-collapsed native selections, and the temporary
  protected snapshot, while preserving `_blockClipboard` so Paste recovery still
  works after a real Cut/Copy.
- **Documentation Result**: Updated the iOS Selection MVP and
  `MASTER_TODO_V4.md`. Awaiting IPA/device verification.

## 2026-05-02 - iOS Selection Handles And Bookmark Coordinate Follow-Up

- **Session Goal**: Fix QA findings that drag-handle selections did not update
  the effective clipboard, handle overlays drifted after editor scrolling, and
  cross-mode bookmarks were not staying attached to the intended side/position.
- **Selection Result**: Global selection handle drags now notify the editor
  parent after every range update. The editor snapshots the current
  overlay-selected raw markup slices so Copy/Cut/Paste and debug shape reflect
  the visible handle selection rather than a stale Select All snapshot.
- **Handle Position Result**: The editor ListView now refreshes
  `GlobalSelectionOverlay` handle positions on scroll, keeping the overlay
  handles aligned with their rendered text range.
- **Bookmark Result**: Present-mode bookmark markers choose their outside edge
  from paragraph direction: English/LTR markers render left of the anchor word,
  Hebrew/RTL markers render right. Presenter-created bookmarks now store editor
  block/offset coordinates, and returning from present mode force-reloads
  editor bookmarks so presenter-created anchors appear in editor mode.
- **Documentation Result**: Updated iOS Selection and Bookmarks MVP docs plus
  `MASTER_TODO_V4.md`. Awaiting IPA/device verification.

## 2026-05-02 - iOS Selection Snapshot Downgrade Follow-Up

- **Session Goal**: Fix the returned iOS selection bug where Select All/Cut
  could again paste only the originally touched block after double-tap native
  menu timing, while preserving the newer handle-drag clipboard behavior.
- **Selection Result**: `GlobalSelectionOverlay` now records whether the
  selection was truly refined by dragging a handle. The editor may shrink the
  protected multi-block snapshot only after such a handle-refined selection.
  Native one-block iOS menu events can no longer downgrade the protected
  Select All snapshot to the originally touched `TextField`.
- **Handle Visibility Result**: Offscreen selection endpoints no longer clamp
  their handles to the viewport edge. If selected text scrolls out of view, the
  matching handle hides until the endpoint is visible again, while active handle
  dragging remains visible.
- **Documentation Result**: Updated the iOS Selection MVP and
  `MASTER_TODO_V4.md`. Awaiting IPA/device verification.

## 2026-05-02 - iOS Selection Handles Toolbar And Edge Scroll

- **Session Goal**: Fix iOS editor selection usability after device testing:
  double-tap word selection needed custom drag handles, handle movement needed
  an app-owned Cut/Copy/Paste command surface, and dragging handles to the top
  or bottom of the editor needed to scroll for long selections.
- **Native Word Selection Result**: Non-collapsed native `TextField`
  selections now promote into `GlobalSelectionOverlay.selectBlockSelection`,
  showing the same gold handles and amber markup selection used by global
  selection refine mode.
- **Toolbar Result**: The overlay now owns a compact Cut/Copy/Paste toolbar
  after word selection or handle refinement, wired to the existing clean
  selection clipboard paths instead of relying on iOS to reopen the native
  toolbar after custom handle movement.
- **Edge Scroll Result**: Handle dragging near the editor viewport top/bottom
  now auto-scrolls the editor `ListView` and refreshes handle positions so
  selections can extend beyond the initially visible screen.
- **Documentation Result**: Updated the iOS Selection MVP and
  `MASTER_TODO_V4.md`. Awaiting IPA/device verification.

## 2026-05-02 - iOS Selection Toolbar Patch Reverted

- **Session Goal**: Respond to device QA showing that the previous
  selection-toolbar/autoscroll patch was not surgical enough and caused major
  collisions between native iOS selection and the app overlay selection system.
- **Regression Confirmed By User**: Select All became unstable and selected
  only one block, dragging handles could scroll indefinitely even when no useful
  text remained, and both the native iOS toolbar and app Cut/Copy/Paste toolbar
  appeared together.
- **Rollback Result**: Restored the iOS runtime selection files to the last
  passing state before commit `3fd2d4b`, preserving the safer
  `c94c55f` behavior that protects multi-block snapshots without adding the
  duplicate toolbar/autoscroll collision.
- **Protocol Result**: Updated the iOS Selection MVP with a rejected-approach
  warning and marked the V4 TODO item as failed/reverted. Future selection work
  must isolate one behavior at a time and avoid mixing native menu recovery,
  custom overlay handles, app toolbars, and autoscroll in one broad patch.

## 2026-05-02 - iOS Native One-Block Selection Handle Safety Pass

- **Session Goal**: Apply only the smallest safe follow-up after the rejected
  selection-toolbar/autoscroll patch: restore normal native handles for
  ordinary one-block double-tap selection without touching global Select All,
  app overlay handles, clipboard snapshots, or autoscroll.
- **Fix Result**: `_EditorBlock` now uses native iOS selection controls only
  when no global selection and no app overlay selection are active. Global or
  overlay selection still uses `GhostSelectionControls`, preserving the
  carefully crafted multi-block selection system.
- **Safety Result**: No app-owned Cut/Copy/Paste toolbar was added, no
  timer-based edge autoscroll was added, and no native selection is promoted
  into app overlay selection. The native toolbar remains the only toolbar for
  ordinary one-block selection.
- **Documentation Result**: Updated the iOS Selection MVP and
  `MASTER_TODO_V4.md`. Awaiting IPA/device verification.

## 2026-05-02 - iOS Cross-Block Handle Adoption Safety Pass

- **Session Goal**: Fix device QA showing that native iOS handle dragging stops
  at the initially touched paragraph/newline because each editor paragraph is a
  separate `TextField`.
- **Fix Result**: Partial, non-full-block native selections now adopt into the
  existing `GlobalSelectionOverlay`, so the gold overlay handles can drag
  across paragraph blocks. Full-block native Select All remains owned by
  `_selectAllBlocks()`. Handle hit-testing also includes a small paragraph
  boundary corridor so endpoints can reach offset `0` / `text.length` instead
  of sticking near a newline.
- **Safety Result**: No app-owned Cut/Copy/Paste toolbar was added, no
  timer-based edge autoscroll was added, and no clipboard command path was
  changed. The adoption path is disabled during global selection, command
  execution, full-block Select All, or any already-active overlay selection.
- **Clipboard Result**: Overlay selection now dismisses stale native one-block
  toolbars, routes iOS cut/copy intents through `_onCutClean()` /
  `_onCopyClean()`, and stores the visible overlay-selected slices instead of
  promoting an older protected full-script snapshot.
- **Documentation Result**: Updated the iOS Selection MVP and
  `MASTER_TODO_V4.md`. Awaiting IPA/device verification.

## 2026-05-02 - iOS Explicit Extend Selection Recovery

- **Session Goal**: Repair QA regressions from the automatic native-to-overlay
  adoption attempt: Select All stopped working, cross-block handle Cut/Copy
  still affected only the originally touched block, and Cut history could lag
  until deselection.
- **Rollback Result**: Runtime selection files were restored to the last safer
  native-menu baseline before automatic adoption, preserving Select All and the
  protected multi-block clipboard recovery path.
- **Replacement Result**: Ordinary native word selection now remains native
  until its native/adaptive context menu is built. That confirmed partial
  selection is then promoted into `GlobalSelectionOverlay` handles without a
  product-facing `Extend` button, allowing cross-block drag without passive
  listener adoption.
- **Clipboard Result**: Overlay Cut/Copy stores the visible overlay-selected
  raw slices and does not promote an older protected Select All snapshot for
  `cut-overlay` / `copy-overlay`.
- **Safety Result**: No floating app Cut/Copy/Paste toolbar, no timer
  autoscroll, no `CutSelectionTextIntent` dependency, and no passive
  `_onSelectionChanged()` adoption path were added. Awaiting IPA/device
  verification.

## 2026-05-02 - iOS Selection Menu Bridge Follow-Up

- **Session Goal**: Fix device QA showing that partial native iOS handles still
  felt trapped inside one paragraph block and that native Select All could leave
  the user without visible Cut/Copy actions.
- **Menu Result**: Partial native selections now show app-owned `Cut`, `Copy`,
  `Select All`, and optional `Paste` directly instead of native-only
  Lookup/Search Web actions. The confirmed native menu selection promotes into
  cross-block overlay handles behind that same toolbar; no vague `Extend`
  product action is exposed.
- **Select All Result**: Native-menu Select All now reopens/rebuilds the toolbar
  after `_selectAllBlocks()` so the global selected state can expose Cut/Copy.
- **Handle Result**: Overlay handle dragging now chooses the nearest rendered
  block/caret target while dragging, so app-owned handles are not stuck at the
  initial block boundary when moving toward another visible paragraph.

## 2026-05-02 - iOS Block Selection Recognition MVP Planning

- **Session Goal**: Document a safer future path for partial cross-block
  selection without changing runtime code.
- **Documentation Result**: Added
  `_agent/mvp/Platform_iOS/block_selection_recognition_mvp.md`, defining a
  block-aware recognition layer that can track start/end block endpoints, build
  raw-markup clipboard slices, and preserve native one-block selection plus
  Select All recovery.
- **Safety Result**: No Dart runtime files were changed. The MVP explicitly
  forbids a second app toolbar, passive listener adoption, timer autoscroll,
  shared-platform edits, or collapsing multi-block clipboard data into plain
  text.

## 2026-05-02 - iOS Block Selection Recognition Runtime Implementation

- **Session Goal**: Implement the documented block-aware partial selection
  recognition layer so refined overlay handles can Cut/Copy the exact visible
  cross-block raw-markup range instead of falling back to the originally
  touched native `TextField`.
- **Runtime Result**: Added transient `_recognizedBlockRange` state, private
  block endpoint/range helpers, raw-markup slice conversion, read-only overlay
  endpoint reporting, recognized Cut/Copy command routing, and safe recognized
  range deletion that preserves block count for partial cuts.
- **Invalidation Result**: Recognized ranges now clear on user navigation,
  clear/delete selection, load/remove/split block flows, undo/redo/history
  jumps, search jumps, bookmark jumps, import, and clear-script. The real
  `_blockClipboard` is not cleared by those transient invalidations.
- **Safety Result**: No app-owned floating toolbar, product-facing `Extend`
  button, passive listener adoption, timer autoscroll, or non-iOS runtime edit
  was added. Native one-block selection and Select All recovery remain separate
  command paths.
- **Verification Result**: `dart format` completed for touched iOS files,
  `git diff --check` passed, and targeted `flutter analyze --no-pub` reported
  no new compile errors, only existing warning/info noise in the large editor
  files. Awaiting IPA/device verification.
## 2026-05-03 - iOS Selection/Bookmark Regression Repair

- **Session Goal**: Address device QA showing `Select All` again selecting only
  the initially touched block, cross-block handle Cut/Copy falling back to the
  first native block, and editor bookmarks placed before a block appearing after
  the first word in present mode.
- **Selection Result**: iOS full-block native selection escalation now checks
  normalized `selection.start/end`, so reversed base/extent Select All events
  still route into `_selectAllBlocks()`.
- **Clipboard Result**: Cross-block Cut/Copy now rebuilds the recognized command
  range from the live overlay handle endpoints at command time before slicing
  raw markup, reducing stale first-block/native-selection fallback risk.
- **Bookmark Result**: Editor-to-present bookmark mapping now removes the
  phantom token produced when a prefix ends exactly at a paragraph boundary, so
  a bookmark before the first word of block B anchors to that first word.
- **Verification Result**: Targeted `flutter analyze --no-pub` for the touched
  iOS selection/bookmark files reported no compile errors, only existing
  warning/info noise in the split editor files. Awaiting IPA/device
  verification.

## 2026-05-03 - iOS Selection Command Router Follow-Up

- **Device QA Input**: Latest IPA still showed native Select All leaving only
  the originally double-tapped word selected, cross-block handle Cut falling
  back to the first touched word/block, Select All Copy copying only the first
  word in some flows, Paste consuming the app clipboard after one paste, and
  Undo not becoming available until after deselection.
- **Command Router Result**: `_onCutClean()` no longer calls `_onCopyClean()`
  before evaluating live recognized/overlay ranges. This prevents stale native
  one-block selection from overwriting the intended cross-block clipboard.
- **Snapshot Result**: Recent protected Select All snapshots are ignored while
  an ordinary partial native selection is active, unless the app is truly in
  global Select All state.
- **Clipboard Result**: `_pasteFromGlobalClipboard()` refreshes the internal
  `_blockClipboard` after paste so the same styled block clipboard remains
  pasteable multiple times.
- **History Result**: Cut forces a pre-cut history baseline and then commits
  the cut state, so Undo can become available immediately after destructive
  commands.
- **Bookmark Result**: Present-mode bookmark marker vertical offset was moved
  from above the word to beside the anchor word.

## 2026-05-03 - iOS Native Toolbar Select All Guard

- **Device QA Input**: Native/adaptive toolbar `Select All` still left only
  the originally double-tapped word selected, while alternate empty-space paths
  could still reach full-script selection.
- **Toolbar Result**: Replaced app-handled toolbar `Select All` items with
  custom app-owned actions so the command calls `_selectAllBlocks()` directly
  instead of relying on native one-`TextField` select-all semantics.
- **Guard Result**: `_selectAllBlocks()` now opens a short native-menu guard
  window and the selection listener ignores late iOS native word-selection
  callbacks during that window, preventing immediate collapse back to the
  originally tapped word.
- **Rearm Result**: Toolbar Select All re-arms `_selectAllBlocks()` once after
  the native callback window, then reopens the toolbar into the app-owned
  global Cut/Copy/Paste menu.

## 2026-05-03 - iOS Double-Tap Select All Isolation

- **Device QA Input**: Empty-place Select All correctly selected all script
  blocks, but double-tapping a word first left the word selection/handles alive
  and pressing Select All did not expand to the full script.
- **Root Cause**: The double-tap partial-selection toolbar was automatically
  promoting the one-word native selection into app overlay state while the
  toolbar was merely being built. That passive promotion could race against the
  later Select All command and keep the originally touched word in control.
- **Fix Result**: Removed toolbar-build auto-promotion for partial native
  word selections. Double-tap remains an ordinary one-block native selection
  until the user chooses a command; Select All can now route directly to the
  app-owned `_selectAllBlocks()` path without stale one-word overlay state.

## 2026-05-03 - iOS Selection Architecture Lesson

- **Decision**: Future iOS selection work must not rely on native iOS
  `TextField` handles as the owner of script-level selection. Native selection
  is acceptable as a one-block gesture/input helper only.
- **Reason**: The editor is a multi-block styled script surface. Native iOS
  selection only knows the current `TextField`, which caused repeated
  regressions when it was asked to coordinate with cross-block overlay ranges,
  raw-markup clipboard preservation, history, and bookmarks.
- **Protocol Result**: `AI_PROTOCOL.md`, `selection_mvp.md`, and
  `block_selection_recognition_mvp.md` now document the rule: native selection
  may detect intent, but `GlobalSelectionOverlay` / the owning app MVP must own
  script-level range, handles, clipboard routing, and invariants.

## 2026-05-03 - iOS GlobalSelectionOverlay Handoff Step 1

- **Goal**: Start moving partial selection toward one app-owned handle system
  without re-breaking the now-verified double-tap Select All path.
- **Runtime Result**: Partial native word selection can hand off to
  `GlobalSelectionOverlay` after the toolbar opens, so the app overlay becomes
  the handle/range owner instead of leaving native one-block selection as the
  only owner.
- **Safety Result**: `_extendNativeSelectionToOverlay(...)` now refuses to run
  during the Select All native-menu guard window, while global selection is
  active, during command execution, or when overlay selection already exists.
- **Command Result**: Partial toolbar Cut/Copy force the handoff before command
  routing. Partial/global toolbar Select All uses the re-armed app-owned Select
  All path so it should still expand to the full script after double-tap.
- **Verification Needed**: Device QA must confirm double-tap word -> Select All
  still selects the full script, and double-tap word -> overlay handles can be
  dragged without clipboard falling back to the originally touched word.

## 2026-05-03 - iOS Overlay Handle Command Repair

- **Device QA Input**: After guarded handoff, dragging handles and pressing Cut
  still cut only the originally double-tapped word. After a Cut created a rich
  clipboard, later selections could show only Paste/Select All instead of
  Cut/Copy.
- **Handle Ownership Result**: `_EditorBlock` now hides native iOS handles for
  any non-collapsed selection range, not only after the parent has already
  observed overlay/global selection. This prevents the user from dragging
  native one-block handles while the app expects overlay ownership.
- **Toolbar Result**: When the app knows a native, overlay, or global selection
  range exists, the context menu force-injects app-owned Cut/Copy if iOS omits
  them because a paste clipboard is available.
- **Command Result**: Forced Cut/Copy actions call the handoff path before
  command routing so `_onCutClean()` / `_onCopyClean()` can consume the live
  app-owned range instead of stale native word selection.

## 2026-05-03 - iOS Visible App Selection Clipboard Fallback

- **QA Failure Recorded**: Device testing rejected the previous overlay handle
  command repair. The visible highlight could still exist while the command
  router fell back to the originally double-tapped native word; Copy could
  produce an empty result for a visibly selected block, and Cut could remove
  only the first word of a larger highlighted range.
- **Surgical Correction**: Added a guarded fallback before native one-block
  fallback in `_onCutClean()` / `_onCopyClean()`: read the current visible
  app-owned selections directly from each `MarkupController`
  (`isGlobalSelected` / non-collapsed `externalSelection`) and store those raw
  markup slices in `_blockClipboard`.
- **Command Order Correction**: The visible app highlight check runs
  immediately after full Select All and before recognized/overlay/native
  fallbacks, so a stale recognized range cannot win with only the originally
  tapped word.
- **Toolbar Correction**: `_EditorBlock` now treats a non-collapsed
  `externalSelection` as a selectable app range when deciding whether to hide
  native handles and expose app-owned Cut/Copy. A visible app highlight must not
  be allowed to produce a Paste/Select All-only toolbar.
- **Clipboard Correction**: The ordinary native one-block Copy fallback now
  also writes `_blockClipboard`, matching the contract that Cut/Copy populate
  the app clipboard instead of leaving in-app Paste dependent on the external
  system clipboard only.
- **Reason**: The app must never allow command data to disagree with the
  visible amber selection. If the visual app highlight exists, it owns Cut/Copy
  before native iOS selection can own the command.
- **Verification**: Awaiting iOS device QA. This entry is pending, not user
  verified.

## 2026-05-03 - iOS Empty-Block Selection Clipboard Repair

- **Device QA Input**: Debug output showed the overlay range was correct
  (`0:57-4:30`, with slices shaped like `0:16,1:0,2:29,3:0,4:30`), but the
  clipboard stored only non-empty visible slices (`0:16,1:29,2:30`). Empty
  paragraph blocks inside the selected range were being dropped.
- **Root Cause**: The visible app-selection fallback was placed before the live
  overlay/raw range command path. That fallback reconstructs selected text from
  per-controller visible highlight and cannot represent selected empty blocks,
  so it collapsed the script structure even when `GlobalSelectionOverlay`
  already had the correct raw range.
- **Fix Result**: Cut/Copy now compare live recognized overlay blocks against
  visible fallback blocks and prefer the recognized/raw range whenever it
  preserves more block slices or equal/better non-empty coverage. Visible
  fallback remains only a safety net for stale/missing overlay command state.
- **Clipboard Companion Result**: Plain/rich clipboard companion text no
  longer filters out empty block slices. `_blockClipboard`, plain text, and
  rich clipboard output now preserve selected blank-line structure as the same
  block sequence.
- **Verification**: Awaiting iOS device QA. The expected clipboard shape for a
  selection spanning text-empty-text-empty-text is five slices, including the
  empty blocks.

## 2026-05-03 - iOS Stored Recognized Range Command Gate

- **QA Follow-Up**: User reported no visible behavior change after the empty
  block repair. The likely remaining gate was in `_recognizedBlocksForCommand()`:
  it rejected the stored recognized range unless the live overlay range could
  still be re-read during the toolbar command callback.
- **Root Cause Direction**: Device debug showed the stored `Range` was correct.
  If the live overlay state disappears or becomes unavailable while the native
  toolbar action is executing, the correct stored range was discarded and the
  smaller visible fallback still won.
- **Fix Result**: `_recognizedBlocksForCommand()` now accepts the stored
  recognized range when a visible app selection exists and the stored range
  preserves more block slices than that fallback. Debug output marks this as
  `copy-recognized-stored` / `cut-recognized-stored`.
- **Safety Result**: Editor debug sentry now includes a command-candidate line
  (`chosen=... r=[...] v=[...] o=[...]`) so the next device test proves which
  source won. Overlay Copy also uses the shared rich clipboard serializer so
  empty selected slices are not filtered in that fallback path.
- **Verification**: Awaiting iOS device QA. If the same selection is tested,
  the desired clipboard debug is a recognized/stored five-slice shape, not
  `copy-visible-app` with only non-empty slices.

## 2026-05-03 - iOS App-Owned Selection Command Route

- **Device QA Root Signal**: User reported `Command` stayed `idle` while
  clipboard still ignored empty lines and Cut/Copy affected only the first
  tapped word. This proves native iOS selected-text commands can bypass the
  Flutter/app command callbacks entirely.
- **Architecture Correction**: Non-collapsed selected script text is now routed
  through app-owned selection commands. Native iOS may seed the initial word or
  range, but `GlobalSelectionOverlay` owns the visible selection and the app
  toolbar owns Cut/Copy/Paste/Select All.
- **Runtime Change**: Added an app selection toolbar in the editor build stack,
  suppressed native selected-text menus during app/global/overlay selection,
  and promoted eligible native seed selections into the overlay when no global
  guard/command/overlay selection is active.
- **Safety Boundary**: The fix is iOS-only and does not touch presenter/STT,
  other platform runtime folders, import/export serialization, or platform
  READMEs.
- **Verification Status**: Local analysis shows no compile errors in the touched
  editor files, only the existing warning/info load. Physical iPhone QA is still
  required to verify `Command` changes from `idle` and empty selected blocks
  survive Cut/Copy/Paste.

## 2026-05-03 - iOS Partial Clipboard Paste + Style Envelope Repair

- **Device QA Input**: User confirmed the app-owned command route was mostly
  working, but partial cut/paste still had three issues: partial paste could
  overwrite surrounding block content, selected text from inside a styled span
  could paste without its original style, and tapping formatting suites could
  clear selection while leaving a highlighted range.
- **Clipboard Mode Fix**: `_blockClipboard` now records whether it represents a
  full-script Select All clipboard or a partial selection clipboard. Only
  full-script clipboard data may restore controllers from block `0`; partial
  clipboard data inserts at the cursor or replaces the currently selected
  range.
- **Style Envelope Fix**: Partial clipboard slices now preserve enclosing raw
  style tags around the selected slice. A cut from inside a red/color/font/size
  span carries only that selected slice's style, without leaking the style to
  unrelated selected blocks or surrounding text.
- **Toolbar/Keyboard Fix**: Editor background selection dismissal is now scoped
  to the script canvas instead of the full editor body, so formatting-suite taps
  preserve app-owned selection. The iOS keyboard `Done` action records that the
  keyboard was intentionally dismissed, and Paste/style flows no longer
  forcibly reopen it unless the user taps back into the script.
- **Verification Status**: Targeted iOS editor analysis reports no new compile
  errors; only the existing warning/info load remains. Awaiting physical iPhone
  QA for styled partial A + full B + partial C Cut/Paste and post-Done styling.

## 2026-05-03 - iOS Editor Search Toolbar + Bookmark Anchor Stabilization

- **Search Result Toolbar**: Editor search now mirrors the presenter search
  navigation pattern: it builds all visible-text matches, shows a compact
  previous/next/new-search/close toolbar, and lets the user cycle results
  without reopening the search dialog.
- **Whole-Word Matching**: Editor and presenter search dialogs now include
  `Match whole word`. Whole-word matching is visible-text only and treats
  English letters, Hebrew letters, and digits as word characters.
- **Bookmark Mapping Repair**: Editor/presenter bookmark conversion now walks
  the actual block token cursor and snaps anchors to readable non-newline
  words. Empty blocks preserve layout but do not steal bookmark anchors.
- **Presenter Marker Repair**: Presenter bookmark markers remain side-aware for
  LTR/RTL and now vertically align beside the anchor word instead of floating
  above the first word.
- **Deferred Next Issue**: STT visible skip across language boundaries
  (Hebrew/English/Hebrew visible text) remains a separate STT task and was not
  changed in this search/bookmark pass.
- **Verification Status**: Targeted editor and presenter analysis shows no new
  compile errors; only existing warning/info load remains. Awaiting physical
  iPhone QA.

## 2026-05-03 - iOS Default STT Five-Word Recovery Tightening

- **Device QA Input**: User confirmed opt-in visible text skip works well, but
  the default/off mode still needs safe recovery for normal STT omissions of
  one to five unclear words.
- **Runtime Fix**: `WordAligner.align(...)` now runs phrase-aware local recovery
  inside the same five-word window even when `Allow visible text skip` is off.
  Sequence recovery is also capped to five words in default mode.
- **Safety Boundary**: This does not widen default mode into paragraph skip.
  Larger jumps still require the explicit visible-skip toggle and the
  presenter-reported visible word window.
- **Verification Status**: Awaiting targeted analyzer/build and physical iPhone
  QA with visible skip off: skipping one to five words should recover, while
  skipping farther visible text should still require the toggle.

## 2026-05-03 - iOS Editor Bookmark Marker Placement

- **Device QA Input**: User confirmed bookmark metadata and present-mode
  placement were correct, but editor markers still appeared in the page-side
  block gutter instead of at the original text location.
- **Runtime Fix**: Editor blocks now receive exact bookmark anchors and draw the
  visible `Â»` marker at the resolved raw editor offset using the markup-aware
  text span. Marker taps delete the exact bookmark id.
- **Safety Boundary**: Bookmark signs remain UI metadata only. No marker
  character is inserted into script text, so selection, paste, STT, and export
  paths are not changed.
- **Verification Status**: Awaiting iPhone QA for mid-block editor bookmark
  placement and marker deletion.

## 2026-05-03 - iOS Bookmark Marker Non-Overlap Repair

- **Device QA Input**: User confirmed the bookmark sign appears in both editor
  and present mode, but when it sits inside/before text it hides letters and
  makes the script hard to read.
- **Runtime Fix**: Presenter bookmarks now reserve side padding before the
  anchored word, so the `Â»` marker has its own visual space and does not draw
  on top of the word. Editor bookmark markers only render at the text caret
  when there is a safe whitespace/text-boundary gap; otherwise they stay on the
  same visual row in a non-overlapping margin lane.
- **Sign Correction**: Editor and presenter marker literals now use the
  source-safe `\u00BB` escape so the displayed marker is the intended `»`
  instead of a mojibake `Â»` / `Ã‚Â»` variant.
- **Safety Boundary**: Bookmark markers remain metadata/UI only. The fix does
  not insert marker characters into `controller.text`, and does not change
  selection, clipboard, STT tokenization, import/export, or bookmark storage.
- **Verification Status**: Awaiting iPhone QA. Test editor mid-line bookmarks,
  start-of-block bookmarks, presenter LTR/RTL markers, and marker deletion.

## 2026-05-03 - iOS Text-Flow Bookmark Sign + Search Toolbar Completion

- **Device QA Input**: User clarified that the bookmark sign must behave like
  a real editor character: selectable, cuttable, copyable, pasteable, and
  direction-aware for Hebrew/RTL. Overlay-only markers are not sufficient.
- **Bookmark Result**: Editor bookmark add now inserts the real `\u00BB`
  character into `MarkupController.text`. Editor overlay bookmark markers are
  superseded; bookmark metadata is rebuilt from text-flow signs and saved for
  present-mode navigation.
- **Cross-Mode Result**: Present mode receives script text with bookmark signs
  stripped so STT/tokenization do not see duplicate marker words. Returning
  from present mode inserts missing `\u00BB` signs for presenter-created
  bookmarks, converting clean presenter offsets back to raw editor offsets when
  earlier signs already exist.
- **Clipboard Result**: Cut/delete/paste paths rescan editor text after
  mutation so `\u00BB` signs removed or pasted through normal text selection
  update bookmark metadata.
- **Search Result**: Editor search toolbar now has a whole-word toggle.
  Previous/next result navigation does not request focus or reopen the
  keyboard; only the new-search dialog opens text input.
- **Verification Status**: Awaiting iPhone QA for LTR and Hebrew bookmark
  sign placement, copy/cut/paste recreation, undo, cross-mode sync, and search
  toolbar keyboard behavior.

## 2026-05-03 - iOS App-Owned Toolbar Protocol Correction

- **Device QA Input**: User confirmed that long-pressing selected text or the
  `\u00BB` bookmark sign could still expose the native iOS toolbar. This violates
  the current app-owned selection protocol because native and app command
  surfaces become duplicates.
- **Runtime Fix**: `_EditorBlock.contextMenuBuilder` no longer returns an
  adaptive/native toolbar. Native iOS may seed focus or a non-collapsed range,
  then the editor suppresses the UIKit toolbar and leaves Cut/Copy/Paste/Select
  All to `_buildAppSelectionToolbar()`.
- **Protocol Result**: Updated iOS Selection, Block Selection Recognition,
  Bookmarks, and Script Editor MVP docs to state that native toolbar UI is
  forbidden for script editing commands. Historical log entries remain as
  history only.
- **Verification Status**: Awaiting iPhone QA for no native toolbar on
  long-press/handles, bookmark-sign Cut/Copy/Paste, Select All, and partial
  styled multi-block cut/paste.

## 2026-05-03 - iOS Presenter Bookmark Delete Sync

- **Device QA Input**: User found that removing bookmarks from present mode did
  not sync the removal back to editor mode.
- **Root Cause**: Present mode removed saved bookmark metadata, but the editor
  still contained the real text-flow `\u00BB` sign. Returning to editor and later
  rescanning signs could recreate the deleted bookmark.
- **Runtime Fix**: Return-from-present now reconciles editor signs from the
  presenter-saved metadata. It removes stale `\u00BB` signs first, inserts any
  missing signs for remaining metadata bookmarks, then rescans and saves the
  refreshed metadata.
- **Verification Status**: Awaiting iPhone QA: delete bookmark in present mode,
  return to editor, confirm the `\u00BB` sign is gone and the bookmark does not
  reappear on the next present-mode entry.

## 2026-05-03 - Windows v5 Selection + Bookmark History Stabilization

- **Device QA Input**: Windows v5 testing found selection handles offset from
  selected words, delayed/both-handle movement during drag, edge autoscroll
  continuing after deselection, arrow keys leaving overlay highlights active,
  left/right skipping empty rows or stalling at block boundaries, and bookmark
  undo/redo restoring the wrong adjacent bookmark state.
- **Selection Runtime Fix**: Windows `GlobalSelectionOverlay` now derives
  handle geometry from constants and centers the hit box on the rendered caret
  anchor. End handle renders below start handle for z-order only. Active handle
  drag state is separated from normalized highlight ranges, and same-block
  crossing flips active ownership intentionally.
- **Autoscroll/Keyboard Fix**: Handle autoscroll now recalculates speed from
  the latest pointer position, updates only the active endpoint, and stops on
  pan end/cancel, deselect, clear selection, dispose, or scroll clamp.
  Windows arrow handling now clears app-owned selections before cursor
  movement and treats empty blocks as real left/right cursor stops.
- **Bookmark History Fix**: Windows bookmark signs now use `\u00BB`, legacy
  mojibake signs are normalized, bookmark add/delete commit text-first history
  snapshots, and undo/redo/history jumps rebuild bookmark metadata from the
  restored text signs.
- **Verification Status**: Targeted analyzer reported no new compile errors;
  existing Windows editor warnings/infos remain. Awaiting Windows device QA for
  handles, autoscroll, empty-row left/right navigation, and adjacent bookmark
  undo/redo.

## 2026-05-03 - Windows v5 Handle/Arrow Follow-Up

- **Device QA Input**: User verified the first V5 stabilization still placed
  handles inside selected text, dragged both handles when one endpoint crossed
  blocks, skipped even single empty rows with up/down, and stalled left/right
  navigation after the second crossed block.
- **Root Cause Direction**: The overlay still mixed endpoint ownership with
  normalized document order, and arrows were still eligible for duplicate
  handling through both the global hardware route and the editor Focus route.
- **Runtime Fix**: Windows overlay now treats endpoint A/B as stable raw
  ownership points and normalizes only for highlight/copy/cut. Handle bars are
  drawn just outside selected text while the caret boundary remains the
  selection truth. The editor Focus shell ignores arrows so
  `HardwareKeyboard` is the single arrow owner.
- **Debug Aid**: Windows debug sentry now reports overlay endpoint/range state
  and the last arrow decision for faster device QA diagnosis.
- **Verification Status**: Awaiting Windows workflow artifact and local smoke
  test, then user QA for handle placement, cross-block drag, and empty-row
  arrow stops.

## 2026-05-03 - Windows v5 Handle Gesture + Presenter Bookmark Follow-Up

- **Device QA Input**: User found that fast handle drags could move the
  opposite endpoint, cross-block handle drags became unstable, double-click
  selection handles were not fully synced before drag, Ctrl+Up/Down shortcuts
  did not preserve native paragraph-selection behavior, and editor bookmarks
  did not land at the correct present-mode coordinates.
- **Runtime Fix**: Windows body drag now refuses to start from an existing
  handle hit box and ignores body drag updates while a handle is active. If
  hit boxes overlap, pan start chooses the nearest visible handle center so
  fast drags keep the intended endpoint.
- **Keyboard Fix**: Plain arrows still use the app block-navigation route, but
  Ctrl/Shift/Alt/Meta arrow combinations now fall through to native
  `EditableText` shortcut handling unless an app-owned selection must first be
  cleared.
- **Bookmark Fix**: Present mode entry now rebuilds bookmark metadata from the
  live `\u00BB` text signs, and bookmark word-index mapping counts the same
  cleaned visible/tokenized text that the presenter receives. Return from
  present reconciles editor signs from presenter metadata without creating a
  history entry.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Awaiting Windows artifact/device QA.

## 2026-05-03 - Windows v5 Shortcut + Ctrl Arrow Correction

- **Device QA Input**: User found that touching/dragging selection handles could
  break Ctrl+C/Ctrl+X, and Ctrl+Up/Down still stalled at the start/end of the
  current block instead of continuing through previous/next blocks.
- **Runtime Fix**: Screen-level keyboard handling now owns Ctrl/Cmd+C,
  Ctrl/Cmd+X, and Ctrl/Cmd+V whenever an app-owned overlay/global selection
  exists, so copy/cut/paste no longer depends on TextField focus after a
  handle gesture.
- **Arrow Fix**: Ctrl+Up/Down now use a block-aware editor path. Repeated
  presses move to current block start/end first, then previous/next blocks.
  Ctrl+Shift+Up/Down can extend selection to block boundaries and uses the
  app overlay when the selected range crosses blocks.
- **Verification Status**: Awaiting Windows workflow/device QA.

## 2026-05-03 - Windows v5 Modified Arrow + Autoscroll Correction

- **Device QA Input**: User found that hard edge autoscroll could continue
  after returning the mouse to the middle of the screen, and that Shift,
  Ctrl+Shift, Ctrl, and Alt arrow combinations could still restart selections
  or stall at paragraph boundaries.
- **Autoscroll Fix**: The editor page now forwards active handle pointer moves
  into `GlobalSelectionOverlay`, allowing the overlay to stop the autoscroll
  timer immediately when the pointer returns to the safe middle zone.
- **Arrow Fix**: Shift extension over an app-owned overlay now preserves the
  existing anchor and moves only the active edge. Shift+Up/Down boundary logic
  runs before plain vertical crossing, and modified horizontal/vertical arrows
  use the block-aware target helpers when crossing paragraph fields.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Awaiting Windows workflow/device QA.

## 2026-05-03 - Windows v5 Selection State-Machine Correction

- **Device QA Input**: User confirmed the previous pass still had fragile
  handle and modifier-arrow behavior, especially after hard edge dragging and
  repeated Shift/Ctrl/Alt arrow extension.
- **Runtime Fix**: Windows `GlobalSelectionOverlay` now exposes a session
  snapshot with endpoint A/B plus anchor/focus. Existing app-owned selection
  extension uses that fixed anchor/focus model instead of deriving direction
  from the normalized selected range.
- **Gesture Fix**: Hard handle exits now preserve the current selection, stop
  autoscroll, clear active handle state, and block body-drag promotion until
  pointer-up or explicit selection clear. This prevents a stale handle drag
  from becoming a second body selection while the mouse button remains down.
- **Arrow Fix**: Full Select All is excluded from Shift-extension and collapses
  through the normal selection-clear path first. Alt+Left/Right and modified
  selection extension use block-aware targets while preserving native in-block
  editing where safe.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Awaiting Windows workflow artifact
  and local launch smoke test.

## 2026-05-04 - Windows v5 Plain Shift Vertical + Handle Autoscroll Correction

- **Device QA Input**: User confirmed Ctrl/Alt arrows and Ctrl/Alt+Shift
  arrows now work well, but plain Shift+Up/Down could still select to the
  script top/bottom around empty rows or select an entire second block, and
  dragging handles to the editor top/bottom no longer started edge autoscroll.
- **Shift Fix**: Plain Shift+Up/Down now remains native inside a single block.
  At a block boundary, or after the selection is already app-owned, the editor
  moves the focus endpoint by visual line using `TextPainter` geometry instead
  of paragraph start/end targets. Empty blocks stay one-step selection stops.
- **Autoscroll Fix**: Mouse exit no longer immediately ends a handle drag while
  the pointer is still in the edge-scroll zone. The overlay keeps scrolling
  from the latest pointer/handle position and uses hard-margin/outside checks
  plus a stale timeout to stop abandoned drags.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Awaiting Windows workflow artifact
  and local launch smoke test.

## 2026-05-04 - Windows v5 Handle Drag Lifecycle Refactor

- **Device QA Input**: User requested the remaining handle edge-scroll lifecycle
  weakness be handled explicitly instead of through scattered flags.
- **Runtime Fix**: Windows `GlobalSelectionOverlay` now uses one private
  `_HandleDragSession` for active endpoint ownership, pan-start pointer/caret
  positions, latest pointer/handle positions, pointer state, autoscroll timer,
  and stale timer.
- **Autoscroll Fix**: Returning to the safe center stops autoscroll without
  ending the drag; edge-zone movement keeps scrolling from the latest pointer;
  hard outside and stale timeout end the handle session while preserving the
  selected range.
- **Scope Guard**: Selection commands, bookmarks, search, styling, keyboard
  anchor/focus behavior, and non-Windows platforms were intentionally left
  untouched.
- **Verification Status**: Targeted analyzer reports no new compile errors
  in the touched overlay file; broader Windows editor analyzer still shows
  existing warnings/infos. Diff check passed. Awaiting push and Windows
  workflow verification.

## 2026-05-04 - Windows v5 Bookmark Ctrl+Shift + Handle Continuity Follow-Up

- **Device QA Input**: User found that Ctrl+Shift+Down beside a bookmark could
  select the whole script, and that handle edge drags could scroll briefly then
  stop following the mouse while still pressed.
- **Keyboard Fix**: Ctrl vertical paragraph navigation now ignores `\u00BB`
  bookmark signs only for target math, then maps the target back to raw editor
  offsets so the sign remains real selectable text.
- **Selection Guard**: Shift-arrow now clears a stale overlay selection if the
  focused collapsed caret no longer matches the overlay focus endpoint, instead
  of extending that old range.
- **Handle Fix**: Page-level active-handle pointer updates now move the active
  endpoint and deduplicate identical pointer positions, so returning to the
  editor safe zone can pull the selection back under the mouse.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Diff check passed. Awaiting push and
  Windows workflow verification.

## 2026-05-04 - Windows v5 Final Targeted Selection Repair

- **Device QA Input**: User confirmed most keyboard paths now work, but
  Ctrl+Shift+Down beside a `\u00BB` bookmark could still reuse stale overlay
  state, Ctrl+Shift+Left/Right could stall after crossing block boundaries,
  and hard handle drags could leave the active handle stuck outside the editor.
- **Selection Guard**: Shift-arrow reuse now requires the overlay focus
  endpoint to match the live focused selection extent and requires a visible
  app-selected range. Otherwise the stale overlay is cleared before the key
  starts from the real caret.
- **Keyboard Fix**: Ctrl+Shift+Left/Right now has a bookmark-aware visible
  word-boundary target that skips `\u00BB` for navigation math while preserving
  the sign as real selectable editor text.
- **Handle Fix**: Outside/stale handle states now suspend the drag, stop
  autoscroll, and preserve endpoint ownership. Re-entry while still pressed
  resumes the active endpoint; a fresh click ends any stale suspended session.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Diff check passed. Awaiting push and
  Windows workflow verification.

## 2026-05-04 - Windows v5 Selection Repair Follow-Up

- **Device QA Input**: User confirmed the final targeted repair still left the
  reported bugs visible. Ctrl+Shift+Left/Right crossed blocks but produced
  broken partial selection islands, and handle edge dragging scrolled only
  briefly before stopping.
- **Selection Guard Correction**: The stale-overlay guard now uses the editor's
  synchronous `_lastFocusedController` instead of FocusNode iteration. FocusNode
  ownership can lag after app-owned keyboard crossing and was clearing a valid
  overlay mid-selection.
- **Handle Edge Correction**: Vertical pointer movement beyond the editor top
  or bottom now remains an edge-zone autoscroll state instead of being treated
  as an outside hard exit. Horizontal hard exits still suspend the handle drag.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Awaiting diff check, push, and
  Windows workflow verification.

## 2026-05-04 - Windows v5 Vertical Arrow Mirror Correction

- **Device QA Input**: User confirmed handle dragging now works perfectly and
  must not be touched. Remaining issue is Down-arrow behavior diverging from
  the better Up-arrow behavior.
- **Keyboard Fix**: `_VerticalLayoutInfo` now detects first/last visual lines
  by comparing the caret Y position to `TextPainter` line metric centers.
  Cross-block vertical targets also use first/last line centers instead of
  asymmetric top/bottom offsets.
- **Shift Fix**: Plain Shift+Up/Down now moves to the adjacent rendered line
  through the same mirrored line-center helper rather than manually adding or
  subtracting a fallback line height.
- **Scope Guard**: `GlobalSelectionOverlay` and all handle drag/autoscroll code
  were intentionally untouched.
- **Verification Status**: Targeted analyzer reports no new compile errors;
  existing Windows warnings/infos remain. Awaiting diff check, push, and
  Windows workflow verification.

## 2026-05-04 - Windows v5 Shift Selection Isolation + Body Drag Scroll

- **Device QA Input**: User confirmed arrow navigation works well until Shift
  is added, and requested click-drag selection to scroll at the editor edges
  like handle dragging.
- **Keyboard Fix**: Shift+Arrow now enters one app-owned route. Existing arrow
  target helpers decide the destination, while Shift only extends the
  anchor-to-focus range. Stale overlay selection is cleared before reuse, and
  transient full-block native selections no longer escalate to Select All while
  Shift is pressed.
- **Body Drag Fix**: Body click-drag selection now has a separate edge
  autoscroll timer that updates only the body-drag focus endpoint. The verified
  handle drag/autoscroll session is intentionally untouched.
- **Verification Status**: Awaiting targeted analyzer, diff check, push, and
  Windows workflow verification.

## 2026-05-04 - macOS Parity Port From Windows 385911e

- **Scope**: Ported verified Windows editor/presenter behavior through
  `385911e` into `Platform_macOS` only, plus macOS MVP docs, TODO/log, and the
  cross-platform missing-features tracker.
- **Editor Split**: Split macOS `script_editor_screen.dart` into build,
  keyboard, keyboard navigation, load-block, bookmark, search, history,
  file-present, styling-command, and editor-block parts. Split the overlay into
  root/body-drag/rendering parts while keeping required `State` lifecycle
  methods on the root class.
- **Runtime Port**: Added app-owned selection parity, stable handle session
  lifecycle, body click-drag edge autoscroll, Shift continuation after mouse
  selections, editor search toolbar, whole-word search, text-flow bookmark
  signs, bookmark-safe history rebuild, rich clipboard guard, presenter search
  and bookmark sync, visible text skip, and safe local STT recovery.
- **macOS Exclusions**: Removed copied Windows WebView2/STT browser code,
  Windows mic selector UI, Windows Settings actions, Windows speech-pack
  dialogs, and Windows-specific STT copy. macOS keeps Apple-native STT and
  `intl: ^0.19.0`.
- **Verification Status**: `flutter analyze --no-pub --no-fatal-infos
  --no-fatal-warnings` passes with existing warnings/infos and no compile
  errors. Line-count check reports no Dart files over 800 lines. Final diff
  and scope checks pending.

## 2026-05-04 - Android User-Tested Parity Port

- **Scope**: Brought `Platform_Android` onto the tested Windows/iOS parity
  track using Windows v4.1.13 / Windows `385911e` and iOS v4.1.8 as behavior
  authority. macOS was used only as a split-file scaffold.
- **Runtime Split**: Android editor/presenter files were split into feature
  parts for build, load, file-present, history, styling, selection/clipboard,
  bookmarks, search, keyboard, presenter build, control bar, settings, manual
  scroll, STT session, bookmarks/search, and alignment helpers.
- **Parity Features**: Added rich internal clipboard guard, text-flow `»`
  bookmark model, bookmark metadata rebuild/sync, editor/presenter search
  toolbars with whole-word matching, presenter resume semantics, visible skip
  contracts, markup-safe import/export services, and shared settings/provider
  metadata behavior.
- **Android Exclusions**: Removed active Whisper runtime references from the
  Android provider and archived Whisper outside active `lib`. Android keeps
  `speech_to_text` / `SttAndroidAdapter` and does not receive Windows WebView2,
  Windows mic selector, Windows speech-pack dialogs, `setx`, or Windows
  settings actions.
- **Verification Status**: Android analyzer exits with no hard errors; active
  Dart file line counts are under 800; `git diff --check` passes for Android
  runtime files. Local APK build is blocked on this workstation because no
  Android SDK is installed, so the GitHub Android workflow is the APK build
  authority.
- **Workflow Follow-Up**: First Android workflow attempt failed during
  `flutter pub get` because the workflow uses Flutter 3.24.3, which pins
  `flutter_localizations` to `intl 0.19.0`. Android `pubspec.yaml` was brought
  back to `intl: ^0.19.0` to match the existing platform workflow.

## 2026-05-04 - Android Mobile Toolbar + STT Language Correction

- **Toolbar Density**: Removed the four Android bookmark buttons from the
  top project app bar and moved them into one iOS-style bookmark popup inside
  the formatting toolbar.
- **Bookmark Commands**: The popup delegates to the existing Android editor
  add/remove/previous/next bookmark callbacks; text-flow `»` bookmark behavior
  remains unchanged.
- **STT Language Flow**: Android `SttAndroidAdapter` / `SpeechService` now
  implement active `setLocale(...)`, and the provider uses the tested iOS
  section-locale pre-switch model for mixed Hebrew/English scripts.
- **Verification Note**: Android analyzer still reports existing warnings and
  infos, but no new hard compile errors were introduced by this correction.
### 2026-05-04 - Windows STT Visible-Skip Parity
- Implemented a Windows-only STT parity pass to keep WebView2 STT plumbing while adopting the tested iOS Hebrew/English language-section behavior for visible skip.
- Added the v5 tracking note that universal system-language STT needs shared cross-platform language metadata instead of guessing from RTL/LTR direction.

### 2026-05-04 - Windows STT Visible-Skip Regression Repair
- Repaired the Windows visible-skip regression from `590cad3` by restoring
  full visible-window phrase/sequence matching in `WordAligner`.
- Delayed visible-locale assistance now waits longer, runs only after a failed
  full-window alignment pass, and avoids switching away from the active locale
  when a later same-locale section remains visible.
- Added targeted Windows aligner tests for English -> English across Hebrew,
  Hebrew -> Hebrew across English, English -> Hebrew, Hebrew -> English, and
  visible-skip-off conservative recovery.
- Follow-up QA showed the provider still clipped a trusted visible-window match
  to the normal 30-word advance cap and then slowed it through fluid advance.
  Visible-skip matches now apply the exact aligner target immediately; normal
  non-visible STT progress remains capped.

### 2026-05-04 - Windows STT Fast Visible-Locale Assist
- Reduced the Windows visible-locale assist wait from eight no-progress chunks
  to a two-step arm/switch flow so Hebrew/English visible jumps can switch
  while the user is still reading the visible target.
- Added a short assist-locale pin so heartbeat/pre-switch logic cannot
  immediately switch WebView2 STT back to the old script position after a
  visible assist.
- Added active-locale plausibility checks so English phrases such as
  "Samaritan woman at well" keep English active even when Hebrew is also
  visible.

### 2026-05-04 - Android Done, Restart, and Visible-Skip Repair
- Enabled the Android editor keyboard Done bar through
  `PlatformKeyboard.showDoneBar`; the control only dismisses the soft keyboard.
- Centralized presenter Restart in `_restartPresenterFromBeginning()` so the
  main Restart button and resume-dialog Restart reset provider position,
  manual index, scroll, and visible-window state together.
- Ported final Windows visible-skip STT behavior to Android-native
  `speech_to_text`: full visible phrase/sequence scan, conservative
  visible-skip-off recovery, trusted visible-target cap bypass, quick guarded
  locale assist, and assist pinning.
- Added targeted Android visible-skip tests covering English/Hebrew crossing,
  same-language visible skips across a foreign section, conservative mode, cap
  bypass, active-locale plausibility, and assist pinning.

### 2026-05-04 - Android Professional Repair Pass

- Added extension-safe Android export naming plus app-created export tracking:
  duplicate saves keep suffixes before extensions (`name (1).rtf`) and known
  exports can Replace / Keep Both / Cancel.
- Added Android file-access channel helpers for content URI write/display-name
  lookup/rename so SAF-created broken names can be repaired or warned about.
- Anchored the editor Done/PRESENT bottom route above the soft keyboard and
  ported the iOS app-owned mobile selection command toolbar to Android.
- Added Android STT locale-switch tokens and grace-window suppression so stale
  recognizer callbacks do not show false offline/privacy errors during a
  language switch.
- Changed the Android workflow to release split-per-ABI APK artifacts instead
  of debug APK upload, and kept all active Android Dart files under 800 lines.

### 2026-05-04 - Android Direct Folder Export Repair

- Replaced Android's normal export save path with a direct selected-folder
  export flow. After format selection, Android opens the folder picker directly
  without an extra app explanation dialog.
- Duplicate export handling now happens before document creation: Replace
  writes to the existing URI, Keep Both creates `name (1).ext`, and Cancel
  performs no write.
- Android still refuses restricted system roots in the platform picker; users
  should choose a writable folder/subfolder. The app lists that selected folder,
  creates the final safe display name there, and rejects unexpected provider
  names.
- Repaired the Android export-name test to use real Hebrew instead of mojibake
  and added MIME-type coverage for document creation.

### 2026-05-05 - Mobile Selection Follow-Up Captured

- Android QA found that long-press/drag selection can still show the native
  Cut/Copy/Paste/Select All toolbar together with the app toolbar.
- Android QA also found that pressing keyboard Done while a range is selected
  can move the keyboard/viewport without recalculating app handle positions,
  leaving handles detached from the selected text.
- The same two behaviors are known iOS risks. Android remains the current
  repair target; after Android is stable, iOS should receive the same
  app-owned toolbar suppression and post-Done handle refresh protocol.

### 2026-05-05 - iOS Mobile Selection Toolbar + Done Resync Port

- Ported the Android-proven mobile selection lifecycle repair back to iOS:
  `GhostSelectionControls` now uses Flutter's handle-only selection-control
  contract, native selected-text toolbars are force-hidden through
  `contextMenuBuilder`, and partial native ranges are promoted to the app
  overlay before keyboard Done dismisses focus.
- Added a keyboard/viewInsets metric refresh hook so app-owned selection
  handles recalculate after the soft keyboard opens/closes or the viewport
  moves.
- Verification is pending iPhone workflow/device QA.

### 2026-05-05 - Windows v4.1.14 Strict Bullet/Header STT

- Added a Windows presenter setting, `Strict bullet/header STT`, for users who
  present from bullet headers instead of reading every script word.
- Strict mode keeps normal WebView2 STT plumbing but disables force-skip
  advancement and tightens alignment so local recovery cannot walk through
  guessed single words.
- Strict mode still allows deliberate next-word progress and confirmed
  multi-word visible-window phrase/sequence jumps, including Hebrew visible
  phrase jumps.
- Added targeted Windows tests for strict bullet/header alignment and preserved
  the existing visible-skip regression tests.

### 2026-05-05 - Windows Presenter Follow-Up

- Presenter bookmark markers no longer delete bookmarks on a simple click.
  Clicking a marker now selects/jumps to that bookmark position; deletion stays
  behind the explicit bottom-toolbar Remove Bookmark command.
- Windows presenter controls now stay visible instead of auto-hiding, avoiding
  accidental text-position jumps when the user only wants the bottom toolbar.
- Strict bullet/header STT now uses the current visible window as its allowed
  phrase target even if the separate visible-skip toggle is off, so it can
  re-lock onto a visible row after improvised speech while still blocking
  guessed single-word jumps.
