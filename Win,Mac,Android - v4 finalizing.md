# Win, Mac, Android - v4 Finalizing Control Plan

## Mission

Stabilize Windows, Android, and macOS v4 before moving deeper into v5 work.
This file is the shared control document for the remaining bugs, priorities,
platform authority rules, and acceptance checks.

The work must be handled step by step:

1. Windows STT regression repair.
2. Android mobile fixes.
3. macOS launch and packaging recovery.

Do not mix these streams unless a focused plan explicitly says to do so.

## Platform Authority Rules

- iOS v4.1.8 is the authority for tested mobile UX:
  keyboard Done behavior, dense mobile toolbar layout, text-flow bookmark sign
  behavior, and mixed-language visible STT skip.
- Windows v4.1.13 / Windows v5 tested editor work is the authority for desktop
  command behavior, selection command correctness, rich clipboard rules, and
  Windows WebView2 STT plumbing.
- macOS is currently build-verified only. It is not a behavioral authority until
  the black-screen launch bug is diagnosed and fixed.
- Android should combine iOS mobile UX lessons with Windows/iOS command
  correctness. It must not blindly copy Windows desktop layouts.

## Current Verified Bugs

### Windows

- Latest Windows STT language-section change from commit `590cad3` made visible
  skip less functional.
- Visible skip no longer reliably skips English -> later English when Hebrew is
  visible between the English sections.
- Mixed-language skip must support:
  - English -> Hebrew when the Hebrew text is visible and visible skip is on.
  - Hebrew -> English when the English text is visible and visible skip is on.
  - English -> later English while skipping a visible Hebrew section.
  - Hebrew -> later Hebrew while skipping a visible English section.
- Windows must keep native WebView2 STT plumbing. The fix should repair the
  section/skip logic, not replace the STT engine.
- Universal support for every system STT language is deferred to v5. For v4,
  English/Hebrew mixed-script behavior is the tested requirement.

### Android

- Editor keyboard still needs a visible Done control to close the keyboard.
  Repo note: Android already has `_buildBottomActions(keyboardVisible: ...)`,
  but `PlatformKeyboard.showDoneBar` is currently false.
- Presenter Restart button does not visually jump to the beginning of the
  script, even though provider reset logic exists.
- Android STT skip does not yet match iOS-tested visible language-section skip.
- Android mobile UI must continue following iOS density rules. Avoid desktop
  toolbar layouts that overflow on phones.
- Android must keep Android-native `speech_to_text` / Android STT behavior and
  existing Android language-pack/offline handling.

### macOS

- Latest macOS workflow artifact builds successfully but opens to a black page.
- macOS must be treated as runtime-failing until startup logs identify the
  cause.
- Do not continue macOS parity features before launch is fixed.
- Artifact size must be audited, but size is separate from launch correctness.
  Current observed workflow artifacts:
  - Windows: about 13 MB.
  - Android workflow artifact: about 61 MB zipped, with debug APK around 117 MB.
  - macOS workflow artifact: about 57 MB zipped.
- Android currently builds a debug APK, which likely explains much of its size.
  This should be reviewed later, but it is not the first functional blocker.

## Execution Order

### 1. Windows STT Regression Repair

Goal: restore and improve the visible skip behavior without breaking WebView2
STT.

Required focused plan:

- Compare current Windows STT provider/aligner against:
  - the last known good Windows skip behavior before `590cad3`;
  - iOS-tested mixed-language provider/aligner behavior.
- Identify why same-language visible skip became worse.
- Restore same-language visible skip before changing mixed-language behavior.
- Then reintroduce mixed visible language-section skip carefully.
- Keep WebView2 STT, microphone selection, and Windows diagnostics intact.

Acceptance checks:

- English -> later English works when Hebrew is visible between sections.
- English -> Hebrew works when visible skip is enabled.
- Hebrew -> English works when visible skip is enabled.
- Hebrew -> later Hebrew works when English is visible between sections.
- Normal same-language skip still works.
- Default safe recovery skip still works when visible skip is off.
- Windows workflow passes and uploads `AutoTeleprompter-Windows-EXE`.

Repair status:

- Full visible-window phrase/sequence matching has been restored in the Windows
  aligner.
- Windows locale assistance is delayed and guarded so it cannot steal a
  same-locale visible skip before alignment has searched the visible window.
- Targeted Windows tests cover mixed English/Hebrew visible skip and
  visible-skip-off conservative recovery.
- Follow-up debug QA found the provider was clipping successful visible-window
  matches to the normal 30-word advance cap. Trusted visible-window matches now
  land directly on the aligner target; non-visible progress remains capped.
- Second follow-up QA showed WebView2 STT switched to Hebrew too late and
  heartbeat could switch it back to English before recognition resumed. The
  provider now uses a faster two-step visible-locale assist with a short
  assisted-locale pin and active-language transcript protection.

### 2. Android Mobile Fixes

Goal: bring Android closer to the tested iOS mobile behavior without breaking
Android-native services.

Required focused plan:

- Enable the Android editor Done bar or equivalent visible Done control.
- Fix presenter Restart so provider state and visible scroll both return to the
  beginning.
- Port the tested iOS visible language-section STT behavior to Android.
- Keep Android-native STT and existing Android missing-language/offline-pack
  behavior.
- Preserve the two-row mobile presenter toolbar already added after the Android
  overflow bug.

Acceptance checks:

- Keyboard Done closes Android keyboard reliably.
- Restart jumps to the beginning visually and resets confirmed word index to 0.
- Android visible skip supports English/Hebrew section jumps like iOS.
- Android default skip still recovers up to the intended safe range.
- Android Hebrew missing-language/offline-pack behavior still works.
- Android workflow passes, APK installs to the connected phone, and app launches.

Status update - 2026-05-04:

- Done bar runtime path is implemented by enabling
  `PlatformKeyboard.showDoneBar`; targeted analyzer on the keyboard helper
  passes.
- Restart now routes through one presenter helper from the main control bar and
  resume dialog, using an immediate word-0 jump plus forced visible-window sync.
- Android visible skip now uses the final Windows aligner/provider behavior on
  top of Android-native `speech_to_text`: full visible phrase/sequence scans,
  trusted visible-match cap bypass, quick guarded locale assist, and assist
  pinning.
- Targeted Android visible-skip tests pass. Presenter split files still report
  existing part-extension analyzer warnings unrelated to this focused repair.

Professional repair status - 2026-05-04:

- Android export is now extension-safe for duplicate names and keeps app-known
  exports in a registry so known duplicates can Replace, Keep Both, or Cancel.
- Android Done/PRESENT footer is anchored above the soft keyboard instead of
  hiding behind it.
- Android script selection command UI now follows the tested iOS protocol:
  native selection may seed a range, native command toolbar is suppressed, and
  the app toolbar owns Cut / Copy / Paste / Select All.
- Android STT locale switching now ignores stale callbacks during a short
  switch grace window and pins visible-locale assists long enough to receive
  fresh recognition.
- Android workflow now builds release split-per-ABI APKs for QA; local APK
  build/install remains blocked on this workstation because no Android SDK is
  installed.
- Android duplicate export repair now uses a persistent SAF export folder
  instead of the system save sheet. The app lists the selected folder before
  saving and resolves `Replace / Keep Both / Cancel` before creating a document,
  preventing provider-created broken names like `name.rtf (1)`.

### 3. macOS Launch Recovery

Goal: make the macOS artifact launch correctly before any additional parity work.

Required focused plan:

- Collect macOS launch/runtime logs from the artifact.
- Verify app entrypoint, splash route, ProviderScope, permissions, and startup
  services.
- Check whether black page is caused by an exception, asset/font load, permission
  block, dependency mismatch, minimum OS issue, or packaging problem.
- Audit artifact contents and size after launch is fixed.
- Only then continue macOS parity cleanup.

Acceptance checks:

- macOS artifact opens to the expected app UI, not a black page.
- Startup logs show no fatal route/provider/permission exception.
- macOS workflow passes.
- User QA confirms the app reaches editor/presenter flows.

## Scope Guards

- Do not stage unrelated release deletions, old sealed artifacts, or IPA changes.
- Do not version bump unless explicitly requested.
- Do not use macOS behavior as proof for Windows or Android until macOS is
  runtime-tested.
- Do not replace platform-native STT engines during v4 repair:
  - Windows keeps WebView2 STT.
  - Android keeps Android-native STT.
  - iOS remains the tested mobile behavior reference.
- Do not fix multiple platform streams in one commit unless the plan explicitly
  requires it.

## v5 Parking Lot

- Universal language-section support for all system STT languages.
- Release-size optimization for Android and macOS after functional stability.
- Android release APK/AAB workflow review instead of debug APK artifact only.
- macOS deeper feature parity after black-screen launch is fixed.
- Cross-platform STT language MVP that generalizes beyond English/Hebrew.

## Next Focus

The next focused plan should be Windows STT regression repair only.
It should not touch Android or macOS runtime files.
