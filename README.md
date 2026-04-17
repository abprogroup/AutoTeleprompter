# AutoTeleprompter v4.0.3
# (Core Teleprompter Engine — iOS · Android · macOS · Windows)

A high-performance, professional teleprompter engine for iOS, Android, macOS, and Windows, featuring a hardened autonomous development loop. Hardened at **v4.0.3**.

## 🚀 Key Improvements (v4.0.3 — 2026-04-17)
- **Upcoming Text Color Toggle**: Restored correct override logic — when toggle is ON, uniform `futureWordColor` is applied to all words, overriding any inline markup colors from the editor.
- **B/I/U Single-Click Fix**: Removed false-positive forward scan in `_isStyleActiveAt` that treated the opening tag of the next styled block as "active," requiring two clicks to toggle on.
- **Hebrew Alignment Detection**: Fixed `_detectAlignAtCursor` to use `[/align=val]` close tag (new format) vs `[/val]` (old format) — alignment status now reflects the correct state in the toolbar.

## 🚀 Key Improvements (v4.0.2 — 2026-04-17)
- **Multi-Platform Architecture**: Clean `lib/platform/` separation layer — iOS, Android, macOS, Windows. Zero platform checks in feature code.
- **RTF Round-Trip**: Full save + load fidelity including Hebrew/Arabic Unicode characters.
- **Pages Export**: Save as Apple Pages format (`.pages`) on iOS and macOS.
- **Mic Button Fix**: Reliable start/stop state on iOS — race condition between async status callbacks resolved.
- **Hebrew Colors in Presenter**: Inline markup colors now always survive presentation mode, regardless of "Upcoming Text Color" setting.
- **DOCX Round-Trip**: Proper ZIP-based DOCX archive generation — no more corrupted files on reload.

## 🛠️ Hardened Agentic Intelligence (v3.7.5)
The project includes a state-of-the-art autonomous development engine designed for precision, safety, and absolute visual proof.

### 🛡️ Agentic Safety Protocols
- **Persistence Guard**: Managed `caffeinate` bridge ensures the system stays awake during autonomous sessions.
- **Surgical Backups**: Mandatory path-mirroring before any file modification via the **`/backup`** command.
- **Task Timer**: Hard 30-minute safety limit per atomic task to prevent run-away processes.
- **Auditor Layer (/logit)**: Mandatory universal documentation synchronization (via terminal `cat`) for every development cycle.
- **Versioning Governance**: Only the USER can authorize major stable version transitions (v4.0, v5.0). AI advances sub-versions (v3.7.5) for incremental tracking.
- **Cleanup Policy**: User-verified [U] items are permanently preserved; cleanup only occurs on major releases at user request.
- **Absolute Verification Engine**: AI must iterate through optional fixes ([TRIO-PATH] Research) until success is PROVED via Deselection and Collision-Check screenshots.

### 🛠️ Developer Hot Commands
- **`/run`**: Master Broad loop for multi-task fix sessions (Planning → Fast-Execution → Verification).
- **`/deep_run`**: Focused surgical loop for critical bugs (Documentation → Test Planning → Implementation → Absolute Verification).
- **`/fix`**: Surgical code injection of approved plans.
- **`/deep_fix`**: THREE-PHASE manual surgical fix (Research 30m, Plan 15m, Exec 15m).
- **`/deep_test`**: Hardened visual verification via Test Route execution and screenshot analysis.
- **`/emulator`**: Absolute Rebuild Mandate: Clean APK rebuild and redeployment.
- **`/logit`**: Universal terminal-based documentation sync for all project files.
- **`/plan`**: Priority-based planning with [TRIO-PATH] and "Meaning" requirements.
- **`/sync`**: Automatically syncs the AI agent with the v3.7.5 project protocols and history.
- **`/organize`**: Smart Governance engine for dynamic artifact routing and root cleanup.
- **`/backup`**: Surgical mirrors and full session snapshots.
- **`/test`**: Basic stability and regression verification.

## 📂 Project Structure
- `AutoTeleprompter/lib/`: Flutter source code for the teleprompter engine.
- `AutoTeleprompter/lib/platform/`: Multi-platform abstraction layer (STT, file import, permissions, keyboard).
- `_agent/`: Hardened autonomous engine logic, workflows, and safety scripts.
- `backups/`: Surgical path-mirrors and full project archives.
- `schemes/`: Architectural loop schemes and loop blueprints.
- `test/deep_analysis/`: Visual loop verification artifacts and surgical test routes.
- `DAILY_LOG.md`: Real-time development diary and session history.
- `MASTER_TODO.md`: Centralized task tracking and bug status.
- `AI_PROTOCOL.md`: Mandatory agentic governance and safety rules (v3.7.5).
- `Project platforms structure.md`: Multi-platform architecture guide and development rules.

## 🎯 v3.9.6 — Styling Engine Hardening (2026-04-12)
- **Global Multi-Block Selection**: Select All works across all paragraph blocks with drag handles for refinement.
- **Style Toggle Engine**: B/I/U/Color/Font correctly toggle on AND off, including nested styles and partial selections.
- **Professional History System**: 10-char/10s typing bulking, suite-sectioned commits, duplicate prevention.
- **Clear Style 3-Mode**: Selection → word-level → baseline (whole script) depending on cursor context.
- **Markup Controller**: Tag-skipping backspace, selection snapping past hidden tags, zero-size tag rendering.

## 🎤 v3.9.8 — Teleprompter Hardening (2026-04-12)
- **Hebrew STT Recognition**: Expanded prefix stripping (triple/double combos), phonetic normalization, lowered match thresholds.
- **Improvisation Tolerance**: Larger search window (60 words), relaxed distance penalties, 15-second stuck grace period.
- **Graceful Error Recovery**: Non-fatal STT errors auto-restart silently; only hardware/permission errors surface to UI.
- **Presentation Font Scaling**: 2x font multiplier restored for teleprompter presentation mode.
- **Upcoming Text Color Override**: Toggle to override all editor inline colors for uniform presentation.

## 🚀 v4.0 — Stable Release (2026-04-12)
- Core teleprompter feature set: Script editor, inline formatting (B/I/U, color, font, size, alignment), recent activity with auto-save, and presentation mode.
- Premium features (recording, cloud sync, login, settings page, controller/remote) hidden — deferred to v4.1+.

## 🎤 v4.0.1 — Native STT & Whisper Fallback Engine (2026-04-13)
- **Native Android STT**: Custom `MethodChannel`-based speech recognition bypassing `speech_to_text` plugin.
- **4-Stage Fallback Chain**: On-device+locale → on-device+default → TTS service component → regular recognizer → auto-Whisper fallback.
- **Whisper Offline STT**: Sequential chunk design (2.5-4s chunks), model download with `.complete` integrity markers.
- **Defunct Element Fix**: All STT/Whisper callbacks guarded with `_disposed` and `_sessionStopped`.

## 🍎 v4.0.2 — iOS Hardening + Multi-Platform Separation (2026-04-17)
- **`lib/platform/` Architecture**: Abstract STT interface (`AbstractSttService`) + adapters for Apple, Android, Windows. `PlatformFileImport`, `PlatformPermissions`, `PlatformKeyboard` factories.
- **DOCX Round-Trip**: `DocxService.generate()` properly wired — no more corrupted files.
- **RTF Round-Trip**: `RtfService.generate()` with Unicode escapes for Hebrew/Arabic — full round-trip fidelity.
- **Pages Export**: `PagesService.generate()` (iOS/macOS only) — ZIP with old Apple Pages XML format.
- **Mic Button Race Fix**: `_startingSession` guard blocks stale iOS async `notListening` from previous stop().
- **Hebrew Colors**: `word.textColor` takes priority over `showUpcomingWordColor` in all presenter states.

---

## 🍎 Building for iOS (Without a Mac)
Since this project is managed on Windows, we use **GitHub Actions** to build the iOS version.

### How to get the iPhone App (.ipa):
1.  **Push your code**: Simply commit and push your changes to GitHub.
2.  **Go to Actions**: Visit the **Actions** tab on [GitHub](https://github.com/abprogroup/AutoTeleprompter).
3.  **Choose the Workflow**: Click on the latest **"Build iOS IPA (Free Edition)"** run.
4.  **Download**: Scroll down to **Artifacts** and download the `AutoTeleprompter-iOS` zip.
5.  **Install**: On your Windows laptop, use [Sideloadly](https://sideloadly.io/) to install the `.ipa` onto your iPhone.

*Last Hardened: 2026-04-17 (v4.0.3 Editor & Presenter Bug Fixes)*
