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
