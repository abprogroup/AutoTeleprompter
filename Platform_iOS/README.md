# AutoTeleprompter v3.9.5.7 Professional
(Styling Sentry - Mission SUCCESS)

Auto-scrolling teleprompter with speech recognition, institutional-grade styling (MS Office Parity), and leak-proof data persistence.

## 🚀 Version History
- **v3.9.5.7**: Institutionalized Styling Engine. Implementation of Structural Category Splitting, Zero-Blink UI Stabilization, and Absolute Guard leak prevention.
- **v3.9.5.1**: Hardened Alignment signatures + Proportional Paragraph isolation.
- **v3.5.3**: Recent Activity Timer + Conflict Resolution.
---

## Windows v4.1.12 Migration Target (Added 2026-04-29)

When porting post-v4 Windows behavior to iOS, keep platform isolation intact and
read the matching `_agent/mvp/Platform_iOS/*.md` file before editing. Windows
v4.1.12 is the behavioral reference for STT resume, cross-mode bookmarks,
visible bookmark markers/removal, active-STT bookmark jumps, present/editor
search, active-STT scroll lock, stopped-mode browsing, one font-size metadata
source, synchronized spacing controls, preserved symbols/blank lines, and
markup-safe export.

Before major V5 feature work, plan a behavior-preserving split of iOS
`script_editor_screen.dart` and `teleprompter_screen.dart`; both exceed the
preferred 1000-line maintainability ceiling.

## iOS Next-Step Handoff From Final Windows v4.1.12 (Updated 2026-04-29)

Windows v4 is now fully user verified at commit `160d137` and is the source
behavior to port next. Before touching iOS source, read the matching
`_agent/mvp/Platform_iOS/*.md` contracts.

Port behavior, not Windows implementation details:

- STT stop/start resumes the current word; only Restart resets to `0`.
- Default STT recovery may skip up to 5 missed words.
- Longer skipping must be opt-in, bounded to visible rendered text, and
  fallback-only after nearby 3+ word phrase priority fails.
- Bookmarks must sync between editor and presenter, support add/remove in both
  modes, and work while STT is active.
- Active STT owns scrolling; stopped STT allows browsing and resume selection.
- Search must match visible text and then map back to raw markup offsets.
- Font size has one metadata value; spacing ranges must sync; symbols, quotes,
  punctuation, and blank lines must be preserved; export must not leak markup.
