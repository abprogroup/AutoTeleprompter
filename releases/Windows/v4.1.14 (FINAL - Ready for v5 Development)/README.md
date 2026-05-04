# AutoTeleprompter Windows v4.1.14

Status: FINAL candidate - STT relock slice implemented, awaiting artifact QA

Version metadata: `4.1.14+14`

Workflow title: `Build Windows EXE (v4.1.14)`

## Release Payload

- `AutoTeleprompter.exe`
- `flutter_windows.dll`
- `WebView2Loader.dll`
- Windows plugin DLLs
- `data/` Flutter runtime assets

## v4.1.14 Focus

- Adds explicit `Strict bullet/header STT` for presenters who use visible
  headers or bullet cues instead of reading every word.
- Keeps normal Windows WebView2 STT as the default behavior.
- Blocks guessed force-skip advancement in strict mode.
- Allows confident visible-window phrase/sequence relock, including
  English/Hebrew visible sections.
- Keeps bookmark marker deletion behind the explicit Remove Bookmark command;
  marker taps select/jump to the bookmark position.
- Treats strict no-match speech as improvisation instead of stuck recognition.
- Searches visible phrases inside longer transcripts so a presenter can
  improvise, say a visible cue, and relock.
- Hides the bottom controls during active STT and reveals them with the Windows
  bottom hover hot-zone.

## Final STT QA Contract

Before this folder is treated as fully sealed, Windows QA should confirm:

- Off-script speech during strict bullet/header mode is treated as
  improvisation, not failure.
- STT keeps listening without reset, force-skip, or panic language switching.
- Speaking a visible two-or-more-word cue relocks to that cue.
- English/Hebrew visible relock works after language switch recognition resumes.
- Active-STT presenter controls stay out of the reading surface but remain
  reachable through the planned bottom hot-zone/shortcut behavior.

## V5 Notes

- Universal language-section support for all system STT languages remains V5.
- Three presenter STT reading modes are parked as V5 research / V6 premium
  candidate: Strict Reading, Flexible Reading, and Bullet Reading.
