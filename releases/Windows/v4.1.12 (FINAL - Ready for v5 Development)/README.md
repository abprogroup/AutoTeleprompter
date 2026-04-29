# AutoTeleprompter Windows v4.1.12 FINAL - Ready for V5 Development

Finalized: 2026-04-29

Windows v4 is user verified at `Platform_Windows/pubspec.yaml` version
`4.1.12+12` and GitHub workflow title `Build Windows EXE (v4.1.12)`.

Latest verified behavior commit: `160d137`.
Verified workflow run: `25110648732`.

## Final Contracts

- STT stop/start resumes from the current reading position.
- Restart is the only command that resets to the beginning of the script.
- Default STT recovery may skip up to 5 missed words.
- Longer visible skips require `Allow visible text skip`, must stay inside the
  rendered viewport, and must remain fallback-only after nearby 3+ word phrase
  priority fails.
- Bookmarks sync between editor and present mode, support multiple anchors,
  visible markers, explicit add/remove, and active-STT previous/next jumps.
- Present mode locks manual scrolling while STT is active and allows browsing
  only while STT is stopped.
- STT auto-follow uses row-progress motion; bookmark/search/restart commands
  jump directly.
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

## Maintainability Gate

The Windows V5-prep screen split is complete. Every Dart file under
`Platform_Windows/lib` is below 800 lines. Future Windows work must edit the
smallest owning file and update the matching `_agent/mvp/Platform_Windows/*.md`
document in the same change.

## Migration Note

This release is the behavior source for iOS migration and future V5 planning.
Port product behavior through the target platform MVP docs; do not copy Windows
WebView2 or desktop-specific implementation details blindly.
