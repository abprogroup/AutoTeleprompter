# AutoTeleprompter v4.0.7
# (Core Teleprompter Engine - iOS - Android - macOS - Windows)

A high-performance, professional teleprompter engine for iOS, Android, macOS, and Windows, featuring a hardened autonomous development loop. Hardened at v4.0.7.

## Key Improvements (v4.0.7 - 2026-04-17)
- Multi-Line Handle Drag Fixed: Handles can now be dragged to the second (and further) visual lines of wrapped text within a single block. Root cause: collapsing native controller.selection in _enterRefineMode() was corrupting RenderEditable's internal state used by getPositionForPoint(). Fixed by making selectionColor always transparent and removing the collapse — all amber rendering is now exclusively in MarkupController.buildTextSpan.

## Key Improvements (v4.0.6 - 2026-04-17)
- Highlight Preserved After Alignment: Applying alignment to a Select All selection no longer clears the amber highlight (overlay hasSelection guard added to _onSelectionChanged).
- Full-Block Highlight Fixed on Drag: Starting a drag from Select All no longer shows the entire block highlighted; only the dragged selection is amber (native selection collapsed in _enterRefineMode after _isGlobalSelection flips false).

## Key Improvements (v4.0.5 - 2026-04-17)
- Selection Handles Correct After Select All: Handles now appear at the true caret positions after Select All (deferred to post-frame).
- Highlight Clears Immediately on Drag: Deselected blocks no longer retain the amber highlight when a drag handle is moved.
- Handle Position Lag Fixed: Handle positions recalculate after each drag frame settles, not before.

## Key Improvements (v4.0.4 - 2026-04-17)
- Alignment Button Highlights After Apply: Tapping left/center/right in the layout suite now immediately lights up the correct button.
- Alignment Button Reflects Script on Load: Opening a Hebrew (right-aligned) script now shows the right button as active in the layout suite.
- Alignment Button Reflects Active Block When Suite Opens: Moving focus to the layout suite no longer resets the toolbar to left.

## Key Improvements (v4.0.3 - 2026-04-17)
- Upcoming Text Color Toggle: Restored correct override logic for uniform futureWordColor in presentation mode.
- B/I/U Single-Click Fix: Removed false-positive forward scan in _isStyleActiveAt.
- Hebrew Alignment Detection: Fixed _detectAlignAtCursor close tag format detection.

## Key Improvements (v4.0.2 - 2026-04-17)
- Multi-Platform Architecture: Clean lib/platform/ separation layer for iOS, Android, macOS, Windows.
- RTF Round-Trip: Full save + load fidelity including Hebrew/Arabic Unicode characters.
- Pages Export: Save as Apple Pages format (.pages) on iOS and macOS.
- Mic Button Fix: Reliable start/stop state on iOS - race condition resolved.
- Hebrew Colors in Presenter: Inline markup colors survive presentation mode.
- DOCX Round-Trip: Proper ZIP-based DOCX archive generation.

## Hardened Agentic Intelligence (v3.7.5)
The project includes a state-of-the-art autonomous development engine designed for precision, safety, and absolute visual proof.

### Agentic Safety Protocols
- Persistence Guard: Managed caffeinate bridge ensures the system stays awake during autonomous sessions.
- Surgical Backups: Mandatory path-mirroring before any file modification via the /backup command.
- Task Timer: Hard 30-minute safety limit per atomic task to prevent run-away processes.
- Auditor Layer (/logit): Mandatory universal documentation synchronization for every development cycle.
- Versioning Governance: Only the USER can authorize major stable version transitions.
- Cleanup Policy: User-verified [U] items are permanently preserved; cleanup only occurs on major releases at user request.

### Developer Hot Commands
- /run: Master Broad loop for multi-task fix sessions.
- /deep_run: Focused surgical loop for critical bugs.
- /fix: Surgical code injection of approved plans.
- /deep_fix: THREE-PHASE manual surgical fix.
- /deep_test: Hardened visual verification.
- /emulator: Absolute Rebuild Mandate.
- /logit: Universal terminal-based documentation sync.
- /plan: Priority-based planning with [TRIO-PATH].
- /sync: Automatically syncs the AI agent with project protocols.
- /organize: Smart Governance engine for dynamic artifact routing.
- /backup: Surgical mirrors and full session snapshots.
- /test: Basic stability and regression verification.

## Project Structure
- AutoTeleprompter/lib/: Flutter source code for the teleprompter engine.
- AutoTeleprompter/lib/platform/: Multi-platform abstraction layer (STT, file import, permissions, keyboard).
- _agent/: Hardened autonomous engine logic, workflows, and safety scripts.
- backups/: Surgical path-mirrors and full project archives.
- schemes/: Architectural loop schemes and loop blueprints.
- test/deep_analysis/: Visual loop verification artifacts and surgical test routes.
- DAILY_LOG.md: Real-time development diary and session history.
- MASTER_TODO.md: Centralized task tracking and bug status.
- AI_PROTOCOL.md: Mandatory agentic governance and safety rules (v3.7.5).
- Project platforms structure.md: Multi-platform architecture guide and development rules.

## v3.9.6 - Styling Engine Hardening (2026-04-12)
- Global Multi-Block Selection: Select All works across all paragraph blocks with drag handles.
- Style Toggle Engine: B/I/U/Color/Font correctly toggle on AND off, including nested styles.
- Professional History System: 10-char/10s typing bulking, suite-sectioned commits.
- Clear Style 3-Mode: Selection, word-level, and baseline modes.

## v3.9.8 - Teleprompter Hardening (2026-04-12)
- Hebrew STT Recognition: Expanded prefix stripping, phonetic normalization, lowered match thresholds.
- Improvisation Tolerance: Larger search window (60 words), relaxed distance penalties.
- Graceful Error Recovery: Non-fatal STT errors auto-restart silently.
- Presentation Font Scaling: 2x font multiplier restored for teleprompter presentation mode.

## v4.0 - Stable Release (2026-04-12)
- Core teleprompter feature set: Script editor, inline formatting, recent activity, and presentation mode.
- Premium features hidden and deferred to v4.1+.

## v4.0.1 - Native STT and Whisper Fallback Engine (2026-04-13)
- Native Android STT: Custom MethodChannel-based speech recognition.
- 4-Stage Fallback Chain for broad device compatibility.
- Whisper Offline STT: Sequential chunk design (2.5-4s chunks).

## v4.0.2 - iOS Hardening + Multi-Platform Separation (2026-04-17)
- lib/platform/ Architecture with abstract STT interface and platform adapters.
- DOCX, RTF, Pages export round-trips all fixed.
- Mic Button Race Fix and Hebrew Colors fix.

---

## Building for iOS (Without a Mac)
Since this project is managed on Windows, we use GitHub Actions to build the iOS version.

### How to get the iPhone App (.ipa):
1. Push your code: Simply commit and push your changes to GitHub.
2. Go to Actions: Visit the Actions tab on GitHub (https://github.com/abprogroup/AutoTeleprompter).
3. Choose the Workflow: Click on the latest "Build iOS IPA (Free Edition)" run.
4. Download: Scroll down to Artifacts and download the AutoTeleprompter-iOS zip.
5. Install: On your Windows laptop, use Sideloadly (https://sideloadly.io/) to install the .ipa onto your iPhone.

*Last Hardened: 2026-04-17 (v4.0.7 Multi-Line Handle Drag Hardening)*
