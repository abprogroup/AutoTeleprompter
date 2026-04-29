# AutoTeleprompter Windows v4.1.12 FINAL

Sealed: 2026-04-29

Windows v4 is complete at `Platform_Windows/pubspec.yaml` version `4.1.12+12`
and GitHub workflow title `Build Windows EXE (v4.1.12)`.

Final backup:

- `backups/final_windows_v4/20260429_103357`

Final sealed contracts:

- STT stop/start resumes from the current reading position.
- Restart is the only command that resets to the beginning of the script.
- Bookmarks sync between editor and present mode, support multiple anchors,
  visible markers, explicit removal, and active-STT previous/next jumps.
- Present mode locks manual scrolling while STT is active and allows browsing
  only while STT is stopped.
- STT auto-follow uses smoother row-progress motion; bookmark/search/restart
  commands jump directly.
- External microphone selection is implemented through the Windows WebView2 STT
  path with System Default fallback.
- Debug mode has a collapsible output window and compact sound bar; recurring
  volume-bar log spam is intentionally disabled.
- Editor and presenter share one font-size metadata value. Presenter visual
  scaling is display-only and must not persist as a larger font number.
- Editor and presenter spacing controls use the same persisted ranges.
- Symbols, quotes, punctuation, and intentional blank lines are preserved.
- RTF/DOCX export converts internal markup into document styling; plain formats
  export visible text only.

V5 preparation note:

- Split oversized editor and presenter files before adding large new features.
  In Windows v4.1.12, `script_editor_screen.dart` is 2885 lines and
  `teleprompter_screen.dart` is 2528 lines. Splitting must be
  behavior-preserving and must not be mixed with feature work.

## Final Verified Addendum (2026-04-29)

The note above records the pre-split sealed state. Windows v4.1.12 was later
user-verified after the behavior-preserving V5-prep split and final STT skip
tuning.

- Latest verified commit: `160d137`.
- Verified workflow run: `Build Windows EXE (v4.1.12)` / `25110648732`.
- Every Dart file under `Platform_Windows/lib` is now below 800 lines.
- Default STT recovery may skip up to 5 missed words.
- Longer visible skips require `Allow visible text skip`, must stay inside the
  rendered viewport, and must remain fallback-only after nearby 3+ word phrase
  priority fails.
- This final Windows behavior is the migration baseline for iOS and future V5
  development.
