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
- **Commits**: pending
