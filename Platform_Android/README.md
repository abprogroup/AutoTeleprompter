# AutoTeleprompter v3.9.5.7 Professional
(Styling Sentry - Mission SUCCESS)

Auto-scrolling teleprompter with speech recognition, institutional-grade styling (MS Office Parity), and leak-proof data persistence.

## 🚀 Version History
- **v3.9.5.7**: Institutionalized Styling Engine. Implementation of Structural Category Splitting, Zero-Blink UI Stabilization, and Absolute Guard leak prevention.
- **v3.9.5.1**: Hardened Alignment signatures + Proportional Paragraph isolation.
- **v3.5.3**: Recent Activity Timer + Conflict Resolution.
---

## Windows v4.1.12 Migration Target (Added 2026-04-29)

When porting post-v4 Windows behavior to Android, keep platform isolation intact
and read the matching `_agent/mvp/Platform_Android/*.md` file before editing.
Windows v4.1.12 is the behavioral reference for STT resume, cross-mode
bookmarks, visible bookmark markers/removal, active-STT bookmark jumps,
present/editor search, active-STT scroll lock, stopped-mode browsing, one
font-size metadata source, synchronized spacing controls, preserved
symbols/blank lines, markup-safe export, and platform-appropriate external mic
selection.

Before major V5 feature work, plan a behavior-preserving split of Android
`script_editor_screen.dart`, `teleprompter_screen.dart`, and the legacy
`v3.9.5.1_script_editor_screen.dart`; all exceed the preferred 1000-line
maintainability ceiling.

## Android Future Handoff From Final Windows v4.1.12 (Updated 2026-04-29)

Windows v4 is now fully user verified at commit `160d137`. Android should not
be edited during the iOS pass, but future Android migration must preserve the
same product contracts in Android-native terms:

- STT stop/start resumes current position; only Restart resets to `0`.
- Default STT recovery may skip up to 5 missed words.
- Longer skipping must be opt-in, bounded to visible rendered text, and
  fallback-only after nearby 3+ word phrase priority fails.
- Cross-mode bookmarks, visible-text search, active-STT scroll lock, stopped
  browsing, one font-size metadata source, spacing sync, symbol/blank-line
  preservation, markup-safe export, and platform-appropriate external mic
  policy must be documented in Android MVP docs before implementation.
