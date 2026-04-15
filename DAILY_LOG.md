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
