# AutoTeleprompter v4.0 Stable Release
# (Core Teleprompter Engine — Production Ready)

A high-performance, professional teleprompter engine for macOS and Android, featuring a hardened autonomous development loop. Hardened at **v3.9.5.1**.

## 🚀 Key Improvements (v3.9.5.1)
- **Zero-Lag Color Sync**: Instant feedback in the editor's color picker modal via local state binding.
- **Precision Prompter Toggles**: User-controlled switches for "Current Word Focus" and "Upcoming Text Color".
- **Context-Aware Previews**: Text color defaults to visual White bubble, while highlights maintain "None" icon clarity.
- **Authority Priority**: Manual editor styles (markup) strictly override automated prompter styling.
- **Iconized Color Presets**: Grid picker now displays the "None" state icon for transparent choices.

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
- `_agent/`: Hardened autonomous engine logic, workflows, and safety scripts.
- `backups/`: Surgical path-mirrors and full project archives.
- `schemes/`: Architectural loop schemes and loop blueprints.
- `test/deep_analysis/`: Visual loop verification artifacts and surgical test routes.
- `DAILY_LOG.md`: Real-time development diary and session history.
- `MASTER_TODO.md`: Centralized task tracking and bug status.
- `AI_PROTOCOL.md`: Mandatory agentic governance and safety rules (v3.7.5).

## 🎯 v3.9.6 — Styling Engine Hardening (2026-04-12)
- **Global Multi-Block Selection**: Select All works across all paragraph blocks with drag handles for refinement.
- **Style Toggle Engine**: B/I/U/Color/Font correctly toggle on AND off, including nested styles and partial selections.
- **Professional History System**: 10-char/10s typing bulking, suite-sectioned commits (Style, Font Size, Font Family, Alignment, Line/Letter/Word Spacing), duplicate prevention.
- **Clear Style 3-Mode**: Selection → word-level → baseline (whole script) depending on cursor context.
- **Markup Controller**: Tag-skipping backspace, selection snapping past hidden tags, zero-size tag rendering.

## 🚀 Stable Release Plan
The stable release (v4.0) will ship with core teleprompter features only:
- Script editor with inline formatting (B/I/U, color, font, size, alignment)
- Recent activity list with auto-save
- Prompter presentation mode
- Premium features (recording, cloud sync, login, settings page, content creator mode) deferred to next version.

## 🎤 v3.9.8 — Teleprompter Hardening (2026-04-12)
- **Hebrew STT Recognition**: Expanded prefix stripping (triple/double combos), phonetic normalization, lowered match thresholds for Hebrew.
- **Improvisation Tolerance**: Larger search window (60 words), relaxed distance penalties, 15-second stuck grace period.
- **Graceful Error Recovery**: Non-fatal STT errors auto-restart silently; only hardware/permission errors surface to UI.
- **Presentation Font Scaling**: 2x font multiplier restored for teleprompter presentation mode.
- **Upcoming Text Color Override**: Toggle to override all editor inline colors for uniform presentation.
- **Text Alignment Override**: Toggle-gated alignment picker in presentation settings panel.
- **Hebrew Selection Fix**: Normalized RTL selection rendering and deselection cleanup.

## 🚀 v4.0 — Stable Release (2026-04-12)
- Core teleprompter feature set only: Script editor, inline formatting (B/I/U, color, font, size, alignment), recent activity with auto-save, and presentation mode.
- Premium features (recording, cloud sync, login, settings page, controller/remote) hidden — deferred to v4.1+.
- Release APK built for real-device testing.

## 🎤 v4.0.1 — Native STT & Whisper Fallback Engine (2026-04-13)
- **Native Android STT**: Custom `MethodChannel`-based speech recognition bypassing `speech_to_text` plugin. Runs via `SpeechRecognizer.createOnDeviceSpeechRecognizer()` in app's own process, using app's mic permission.
- **4-Stage Fallback Chain** (in `MainActivity.kt`):
  - Stage 0: On-device recognizer with locale (SODA, our mic)
  - Stage 1: On-device recognizer without locale (device default language)
  - Stage 2: Regular recognizer targeting TTS service component (`com.google.android.tts`)
  - Stage 3: Regular recognizer default (works on Samsung/Pixel/most devices)
  - Auto-fallback to Whisper if all stages fail (ColorOS/MIUI devices)
- **Whisper Offline STT**: Sequential chunk design (2.5-4s chunks), model download with `.complete` integrity markers, artifact filtering for hallucinations.
- **ColorOS Workaround**: Identified `appops RECORD_AUDIO: foreground` restriction on Google app. Native on-device recognizer uses app's own mic permission. SODA language packs separate from Speech Services by Google — packs shown as downloaded in settings are for TTS service, not system SODA.
- **Defunct Element Fix**: All STT/Whisper callbacks guarded with `_disposed` and `_sessionStopped` checks to prevent assertion failures when leaving teleprompter screen.
- **Settings UI**: Whisper model download/delete and STT engine selector built but hidden for stable release (deferred to v4.1+). Profile/Display Name setting retained.
- **Bluetooth Mic Support**: No forced audio source — allows bluetooth headset mic passthrough.

---

## 🍎 Building for iOS (Without a Mac)
Since this project is managed on Windows, we use **GitHub Actions** to build the iOS version.

### How to get the iPhone App (.ipa):
1.  **Push your code**: Simply commit and push your changes to GitHub.
2.  **Go to Actions**: Visit the **Actions** tab on [GitHub](https://github.com/abprogroup/AutoTeleprompter).
3.  **Choose the Workflow**: Click on the latest **"Build iOS IPA (Free Edition)"** run.
4.  **Download**: Scroll down to **Artifacts** and download the `AutoTeleprompter-iOS` zip.
5.  **Install**: On your Windows laptop, use [Sideloadly](https://sideloadly.io/) to install the `.ipa` onto your iPhone.

*Last Hardened: 2026-04-15 (v4.0.2 iOS Cloud Build Ready)*
