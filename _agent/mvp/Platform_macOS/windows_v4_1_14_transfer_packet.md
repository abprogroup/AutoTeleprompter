---
name: Windows v4.1.14 Transfer Packet
type: parity-handoff
platform: macOS
last_updated: 2026-05-05
---

# Windows v4.1.14 Transfer Packet - macOS

Purpose: collect the verified Windows v4.1.14 changes that were added after
the previous macOS parity pass, and prepare a safe macOS port plan. Windows is
the behavior authority for these features, but macOS must keep Apple-native STT
and macOS file/UI behavior.

## Authority Commits

Port or consciously adapt these Windows commits:

| Commit | Windows change | Port to macOS? |
|---|---|---|
| `590cad3` | Stabilized visible-skip STT and language section behavior | Yes, behavior only |
| `b2c14de` | Repaired full visible-window phrase/sequence matching | Yes |
| `a220555` | Trusted visible matches bypass large-jump cap | Yes |
| `faff251` | Faster visible locale assist and assist pin | Yes, Apple-safe |
| `250f65d` | Strict bullet/header STT mode setting and aligner behavior | Yes |
| `61bd51f` | Presenter bookmark safety and controls follow-up | Yes |
| `3443f66` | Strict improvisation relock and hover-reveal toolbar | Yes |
| `da99e17` | DOCX import preserves underline, breaks, and blanks | Yes |

Do not copy Windows-only WebView2 plumbing, mic selector internals, Windows
speech-pack dialogs, or Windows release/version metadata.

## Transfer Slices

### Slice 1 - DOCX Import Preservation

Source files:
- `Platform_Windows/lib/features/script/providers/script_provider.dart`
- `Platform_Windows/test/script/docx_import_test.dart`

macOS targets:
- `Platform_macOS/lib/features/script/providers/script_provider.dart`
- `Platform_macOS/test/script/docx_import_test.dart` if tests are active

Behavior to port:
- Preserve Word underline as `[u]...[/u]`.
- Preserve Word italics as `[i]...[/i]`.
- Preserve `w:br`, `w:cr`, and `w:tab`.
- Preserve empty Word paragraphs as blank rows.
- Preserve explicit Word `left`/`center`/`right` alignment.
- Treat Word RTL/bidi paragraph hints as right alignment.
- Use `trimRight()` only; do not remove intentional leading blank content.

Gate:
- Import the user sample DOCX and verify underline and empty rows survive in
  editor and present mode.

### Slice 2 - Visible-Skip STT Repair

Source files:
- `Platform_Windows/lib/features/teleprompter/services/word_aligner.dart`
- `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart`
- `Platform_Windows/test/teleprompter/word_aligner_visible_skip_test.dart`

macOS targets:
- `Platform_macOS/lib/features/teleprompter/services/word_aligner.dart`
- `Platform_macOS/lib/features/teleprompter/providers/teleprompter_provider.dart`
- macOS teleprompter tests if enabled

Behavior to port:
- Visible skip off: keep conservative local recovery only.
- Visible skip on: phrase/sequence matching scans the full visible window.
- Large single-word jumps remain blocked.
- Trusted visible phrase/sequence matches bypass the 30-word provider cap.
- Active-locale plausible text blocks unnecessary locale switches.
- Alternate visible locale assist only runs after full visible matching fails.
- Assist pin prevents immediate heartbeat rollback.
- Visible-window changes reset assist state.

macOS adaptation:
- Use Apple STT adapter `setLocale(...)` behavior or an Apple-safe restart
  path. Do not port WebView2/browser STT code.
- Keep current macOS permission/error messaging.

### Slice 3 - Strict Bullet / Improvisation Relock

Source files:
- `Platform_Windows/lib/features/settings/providers/settings_provider.dart`
- `Platform_Windows/lib/features/teleprompter/services/word_aligner.dart`
- `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart`
- `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.settings_panel.dart`
- `Platform_Windows/test/teleprompter/word_aligner_strict_bullet_test.dart`

macOS targets:
- matching macOS settings, provider, aligner, settings panel, and tests

Behavior to port:
- Add `sttStrictBulletMode` setting and presenter toggle.
- Strict mode blocks guessed local single-word walk-through.
- Strict mode still advances on deliberate next-word reads.
- Strict mode uses visible-window phrase matching even if visible skip is off.
- Off-script speech is treated as improvisation, not STT failure.
- Improvisation no-match must not force-skip, reset, panic restart, or rapidly
  switch language.
- Relock only on confident visible phrases, including Hebrew phrases.
- Heartbeat locale sync must not undo an assisted locale during improvisation.

macOS adaptation:
- Preserve Apple STT lifecycle. The behavior model ports; WebView2 restart
  mechanics do not.

### Slice 4 - Presenter Bookmark And Toolbar Safety

Source files:
- `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.dart`
- `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.build.dart`
- `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.bookmarks_search.dart`
- `Platform_Windows/lib/features/teleprompter/widgets/teleprompter_screen.session_stt.dart`

macOS targets:
- matching macOS presenter part files

Behavior to port:
- Clicking a bookmark sign in presenter must not delete the bookmark.
- Bookmark deletion stays behind explicit remove-bookmark controls.
- Presenter controls remain accessible without requiring a body tap that also
  jumps the resume point.
- During active STT, hide controls to reduce visual noise.
- On desktop, reveal controls by hovering/moving pointer near the bottom zone.
- Stop/cancel/restart paths restore controls safely.

macOS adaptation:
- Implement with macOS pointer/mouse hover semantics.
- Keep trackpad/body tap behavior from accidentally changing resume position
  when the user only wants controls.

### Slice 5 - Tests, Docs, And Build Gates

Before each slice:
- Confirm backup of touched macOS files.
- Re-read Windows source and matching macOS target.
- Confirm staged/dirty scope excludes Windows/iOS/Android runtime.

After each slice:
- Run focused macOS tests for that slice where available.
- Run `flutter analyze --no-pub` in `Platform_macOS`.
- Run `git diff --check`.
- Inspect `git diff --name-only` for scope.

Final:
- Confirm macOS workflow builds.
- If the old black-screen-at-launch issue is still present, treat it as a
  separate startup blocker and do not hide it behind STT/import parity.

## Explicit Exclusions

Do not port:
- `Platform_Windows/lib/platform/stt/stt_browser_adapter.dart`.
- Windows WebView2 local server or browser JavaScript STT page.
- Windows microphone picker internals based on `navigator.mediaDevices`.
- Windows speech-pack/settings dialog text.
- Windows-only pubspec version bumps or release archive paths.
- Android/iOS mobile selection toolbar changes.

## QA Checklist

- Import DOCX with underline and blank rows: editor and presenter preserve both.
- Visible skip on: English -> later English across visible Hebrew works.
- Visible skip on: Hebrew -> later Hebrew across visible English works.
- Visible skip on: English -> Hebrew and Hebrew -> English work after assist.
- Visible skip off: no large hidden/visible jumps.
- Strict bullet mode: off-script improvisation does not advance by guessed words.
- Strict bullet mode: speaking a visible heading/phrase relocks quickly.
- Bookmark sign tap does not delete a bookmark.
- Presenter controls are accessible without accidental resume-point jump.
- Active STT hides controls; bottom hover reveals them.
- Restart still resets to beginning; stop/start still resumes.
# 2026-05-05 Implementation Status

The macOS v4.1.14 parity port has been implemented against this packet:

- launch startup permission deferral;
- DOCX import preservation and markup decoration painting;
- strict bullet/header STT and full visible-window skip;
- Apple-safe locale switching through `SttAppleAdapter`;
- presenter bookmark marker safety and active-STT bottom-hover controls.

Local validation: targeted macOS script/STT tests pass with
`flutter test --no-pub`. Final launch proof remains GitHub macOS workflow and
user QA on a Mac.
