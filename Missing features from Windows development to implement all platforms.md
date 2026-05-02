iOS Windows-Parity Handoff

Goal: port verified Windows v4 behavior into Platform_iOS surgically. Work only inside Platform_iOS/, relevant _agent/mvp/Platform_iOS/*.md, MASTER_TODO_V4.md, and DAILY_LOG.md. Do not touch other platform folders.

Before editing:

Read AI_PROTOCOL.md.
Read _agent/mvp/Platform_iOS/*.md.
Inspect the verified Platform_Windows implementation and matching _agent/mvp/Platform_Windows/*.md.
Treat Windows as behavior reference, not copy-paste code.
Create one surgical backup of touched iOS files.
Preserve existing behavior; append docs; do not remove correct protocol text.
Keep each fix narrow and push through the iOS workflow for testing.

Current iOS implementation status as of 2026-05-02:

- Done: iOS large-file separation for V5-safe development. The editor and
  presenter screens have already been split into smaller MVP-owned files, and
  the active rule remains that no Dart file under Platform_iOS/lib should grow
  beyond 800 lines.
- Done: iOS multi-block cut/paste recovery. Select All -> Cut -> Paste now has
  app-private raw-markup clipboard protection for multi-block selections,
  native-empty recovery, and native plain-paste interception so style/newline
  data can be restored from raw markup.
- Done by the later iOS agent: Task 1, STT stop/resume without reset.
- Done by the later iOS agent: Task 2, default 5-word local STT recovery.
- Done by the later iOS agent: Task 3, opt-in visible viewport skip with nearby
  phrase priority and default-off visible skip behavior.
- Done by the later iOS agent: Task 4, active-STT scroll lock and row-progress
  follow.
- Done by the later iOS agent: Task 5, stopped browsing/resume-point selection.
- Implemented now: Task 6, cross-mode bookmarks. iOS now has a shared
  ScriptBookmarkService, editor bookmark controls/markers, presenter bookmark
  controls/markers, and editor-to-present session/title handoff so both modes
  load the same bookmark scope.
- Implemented now: Task 8, visible-text search with raw-offset mapping. Editor
  search maps visible text matches back to raw markup offsets; presenter search
  maps visible phrase matches to word indexes and direct presenter jumps.
- Implemented now: Task 9, one font-size metadata authority. iOS editor and
  presenter controls now display/edit the same raw `settingsProvider.fontSize`
  / `Script.fontSize` value, while any presenter enlargement stays render-only.
- Implemented now: Task 10, synced spacing ranges. iOS editor and presenter
  now use the same spacing ranges, default-relative line-spacing display, and
  script metadata persistence path.
- Implemented now: Task 11, loaded-file symbol/quote/blank-line preservation
  audit. iOS import/save/tokenization paths now preserve punctuation-only
  display tokens and avoid generic trimming/newline collapse of loaded content.
- Implemented now: Task 12, markup-safe export. iOS DOCX/RTF export now converts
  internal markup to document styling through a shared export parser, and Pages
  export writes visible text instead of raw bracket tags.
- Still left after task 13: Task 7 active-STT bookmark jumps verification.
- Implemented now: Task 13, iOS external microphone selection. iOS v4 lists
  native `AVAudioSession.availableInputs`, persists the preferred route, applies
  `setPreferredInput(...)` before Apple STT start, and falls back to System
  Default if the route disappears.

1. STT stop/resume without reset

Behavior: When the user stops the mic in present mode, the STT session should pause/stop listening but must preserve the current script position. Starting the mic again should resume from the current confirmed word, tapped word, searched word, scrolled resume point, or bookmark position. It must not restart from word 0. Only the explicit Restart button may reset the script to the beginning.

Implementation insight: audit iOS presenter init, mic start, mic stop, provider startSession(), stopSession(), and any reset/scroll-to-top calls. Remove reset behavior from normal mic start. Add or reuse a provider method such as jumpToPosition(index) or a stored resume index. Stop should tear down STT cleanly while keeping position state. Restart remains the only owner of confirmedWordIndex = 0.

2. Default 5-word local recovery

Behavior: STT should tolerate normal recognizer misses. If the user speaks text that appears up to about 5 words ahead, the app may advance there by default. This is not a “skip paragraph” feature; it is local recovery for cases where STT misses one or two words.

Implementation insight: inspect Windows aligner/provider logic first. Then update the iOS word matching path to search a small forward window, likely currentIndex + 1 through currentIndex + 5, before declaring no match. Keep confidence strict enough to avoid false jumps. This should always be available and should not depend on the visible skip setting.

3. Opt-in visible viewport skip with nearby phrase priority

Behavior: Larger skipping should be possible only when the user enables a setting like Windows Allow visible text skip. It must default to off. When enabled, the app may jump forward only to text currently visible on the presenter screen. It must not jump to hidden text below the viewport. Nearby matching text must always win before a farther visible match.

Implementation insight: inspect Windows Allow visible text skip implementation and STT MVP. iOS presenter must expose the currently rendered visible word range to the STT/provider layer. Matching order should be: exact/current phrase, nearby phrase/local recovery, then visible viewport fallback only if nearby matching fails. Add safeguards against similar phrase false positives, for example requiring a stronger multi-word phrase match before far visible jump.

4. Active-STT scroll lock and row-progress follow

Behavior: While STT is active or starting, the user should not freely drag-scroll the presenter text. The app should keep the current reading point on screen automatically. Scrolling should feel smooth and continuous as the user progresses through a row, not like a hard jump every time a line is completed.

Implementation insight: inspect Windows scrolling MVP and presenter implementation. In iOS, block manual scroll gestures only while STT is active/starting, but keep explicit controls like bookmark jumps allowed. Use word render positions or key measurements to calculate the active row and target scroll offset. Update scroll in smaller bounded increments. Avoid row-end snapping as the primary movement model.

5. Stopped browsing/resume-point selection

Behavior: When STT is stopped, present mode should become browseable. The user should be able to scroll through the script, tap/select a point, and then press mic to start from that point. Stopping the mic means “pause here and let me browse,” not “reset the session.”

Implementation insight: audit iOS present-mode scroll handlers. When STT is inactive, allow manual scroll. On scroll end, determine the nearest visible word to the reading line and save it as the resume point. Tapping a visible word should set the same resume point. Starting STT should use that saved point. Restart button remains the only path that resets to word 0.

6. Cross-mode bookmarks

Behavior: Bookmarks must be shared between editor mode and present mode. If the user adds a bookmark in the editor, it should appear in present mode. If the user adds a bookmark in present mode, it should appear when returning to the editor. Multiple bookmarks per script should be supported. Users need visible markers, add bookmark, remove bookmark, previous bookmark, and next bookmark.

Implementation insight: inspect Windows bookmark storage and MVP docs. Use one shared script-scoped bookmark store, not separate editor and presenter stores. Bookmarks should be tied to stable script/session identity and durable coordinates such as raw word index plus enough block context to resolve in editor. Markers must be visible and removable in both modes. Bookmark state must survive mode switching and STT stop/start.

7. Active-STT bookmark jumps

Behavior: Bookmark navigation should work while STT is active. The user should be able to jump to previous/next bookmark without stopping the mic. This is one of the main reasons bookmarks exist: navigation during a live reading session.

Implementation insight: do not block bookmark controls during listening. Route bookmark jumps through the same provider position update used for resume-point selection. Clear stale transcript/no-progress state, update confirmed index, resync locale/alignment if needed, and keep STT listening. Present-mode bookmark jumps should be immediate, not smooth animated follow.

8. Visible-text search with raw-offset mapping

Behavior: Search should match the text the user sees, not internal markup. If visible text is wrapped in tags such as [color=#...]hello[/color], searching hello should find and select hello, not land inside the raw tag text. Search should work in both editor and present mode.

Implementation insight: inspect Windows search implementation. For editor mode, build a visible-text to raw-offset map for each MarkupController. Search the stripped/visible text, then translate the match start/end back to raw markup offsets before selecting. For lazy lists, pre-scroll/build the target block and then call exact ensureVisible. Present-mode search should jump to a word index and update resume point.

iOS implementation note 2026-05-02: editor search now lives in
`script_editor_screen.search.dart`, opens from the action bar and
`Ctrl/Meta+Shift+F`, searches `StylingService.stripTags(...)`, then maps the
match to raw offsets through `MarkupController.visualToRawOffset(...)`.
Presenter search now lives in `teleprompter_screen.search.dart`, opens from the
control bar and hardware-key shortcut, builds a visible phrase map from
rendered script words, and jumps through the same provider position path used
by bookmarks. Awaiting IPA/device verification.

9. One font-size metadata authority

Behavior: Editor and present mode must show the same font-size number. There should be one saved font-size metadata value for the script. The editor may render the text smaller for comfortable editing, or present mode may render larger for readability, but that visual scaling must not change the stored number.

Implementation insight: inspect Windows font sync fix and MVP docs. Audit iOS editor font suite, cursor style detection, script metadata, settings provider, present settings, and export. Do not let cursor inline [size] detection become the global font-size authority. Both editor and presenter controls should read/write the same metadata/settings value. Any scale difference must be render-only.

iOS implementation note 2026-05-02: editor Text Suite now reads
`settingsProvider.fontSize` instead of cursor inline size detection for its
global font-size dropdown. Editor font-size changes call
`SettingsNotifier.setFontSize(...)` and
`ScriptNotifier.updateStyleMetadata(fontSize: ...)`. Presenter settings and
A-/A+ controls use the same persistence path. Presenter labels show the raw
metadata number; any enlarged presentation rendering remains display-only.

10. Synced spacing ranges

Behavior: Line spacing, word spacing, and letter spacing should have the same ranges, defaults, labels, and persistence behavior in editor and present mode. A spacing change made in one mode should be reflected in the other mode and saved into script metadata.

Implementation insight: compare iOS editor Layout Suite sliders/steppers with present-mode settings controls. Match the editor’s correct ranges. Persist changes through one script metadata/settings path rather than temporary presenter-only state. If a label displays default-relative values, such as default 1.2 shown as 0.0, use the same rule in both places.

iOS implementation note 2026-05-02: editor `LayoutSuite` and presenter
`TeleprompterSettingsPanel` now share line spacing `0.5..3.0`, word spacing
`-5.0..20.0`, and letter spacing `-2.0..5.0`. Line spacing displays as an
offset from default `1.2`, so `1.2` reads `0.0`. Both editor and presenter
spacing controls update the settings provider and
`ScriptNotifier.updateStyleMetadata(...)` so the values persist across mode
switches.

11. Loaded-file symbol/quote/blank-line preservation audit

Behavior: When the user loads/imports a script file into the app, the editor and present mode must preserve the script’s original visible structure. Do not drop ", », punctuation-only tokens, or intentional multiple blank lines from loaded files. The same preservation must continue through editor save/recent-script storage, present mode rendering, and export.

Implementation insight: audit the full loaded-file pipeline: file import parsing → editor block creation → editor serialization/save/recent storage → script tokenization → present mode rendering → export. Punctuation-only tokens may be display-only/unspeakable for STT, but must render. Never trim() or collapse repeated newlines in loaded script content unless the user explicitly chooses a normalized/plain export format.

iOS implementation note 2026-05-02: file parsing no longer uses generic
`trim()`/`\n{3,}` collapse in the active DOCX/RTF/Pages/plain fallback import
paths. `_getRefinedFullText()` now preserves leading/trailing empty editor
blocks. `WordAligner.tokenize(...)` keeps punctuation-only display tokens such
as `"`, `»`, and section markers in `Script.words` with empty normalized text
so STT can ignore them while present mode still renders them.

12. Markup-safe export

Behavior: Exported files must not leak internal app markup tags as visible text. Tags like [color=#...], [size=...], [font=...], alignment tags, and markdown-like style markers should be converted to real document styling for rich formats. Plain formats should export clean visible text.

Implementation insight: inspect Windows export parser and file I/O MVP. Avoid blind regex stripping if style should survive. For RTF/DOCX, parse markup into spans and emit actual document styling. For TXT/MD/Pages/plain-ish paths, emit visible text without app-private tags. Default teleprompter white should not become white invisible text in exported documents.

iOS implementation note 2026-05-02: added
`Platform_iOS/lib/features/script/services/markup_export_service.dart`.
`DocxService` and `RtfService` now emit document styling from parsed export
runs instead of leaking `[color]`, `[size]`, `[font]`, `**`, underline, italic,
alignment, or shorthand color tags. `PagesService` writes
`MarkupExportService.toPlainText(...)` into `index.xml`, preserving visible
text and blank paragraphs while stripping app-private markup.

13. iOS external microphone selection

Behavior: Define exactly how iOS handles external microphones. If the app can support Bluetooth, USB, or headset microphones through iOS audio routing, it should do so without breaking STT. If explicit in-app mic selection is not possible, document that iOS uses the system/current audio input route.

Implementation insight: investigate iOS AVAudioSession, speech recognition plugin behavior, Bluetooth route options, USB audio input behavior, and permission flow. Do not copy Windows WebView2 mic picker logic. The deliverable may be implementation plus docs, or a documented platform limitation if iOS does not expose safe explicit input-device selection.

iOS implementation note 2026-05-02: the active iOS runtime path is
`SttAppleAdapter` -> `SpeechService` -> `speech_to_text` -> Apple
`SFSpeechRecognizer`. A native MethodChannel in `AppDelegate.swift` exposes
`AVAudioSession.availableInputs` and `setPreferredInput(...)`. Presenter
settings show System Default plus available iOS input routes, persist
`sttInputDeviceId`/`sttInputDeviceLabel`, and the provider applies the selected
route before STT start. This is iOS-native route preference, not Windows
WebView2 `navigator.mediaDevices`. If iOS refuses or loses a route, the app
falls back to System Default and stop/start resume preserves the script
position.

14. Surgical file separation for safe iOS development

Behavior: Before large feature work continues, keep the iOS editor and presenter code split into smaller MVP-owned files so future edits can stay surgical. No Dart source file under Platform_iOS/lib should grow above 800 lines. The split must be behavior-preserving: no UI changes, no state changes, no provider contract changes, no formatting churn outside touched files, and no app-visible differences.

Implementation insight: inspect the verified Windows split first and compare it with the current iOS split. Windows is the pattern source for MVP ownership, not a copy-paste source. Keep the root screen files as orchestration/state shells and move feature-owned logic into focused part files or helper widgets/services. Use existing iOS split files as the first ownership map: script editor loading/block lifecycle, dialogs/history, styling commands, file/present actions, build/layout, selection clipboard, editor block/context menu, presenter STT session, manual scroll, build, control bar, and settings panel. If any file approaches 750-800 lines while implementing a feature, split it before adding more behavior. Each split must preserve all imports, private state access, lifecycle order, callbacks, keyboard/selection behavior, STT state, and widget tree semantics exactly. After splitting, run line-count checks, targeted flutter analyze --no-pub, and update the relevant _agent/mvp/Platform_iOS/*.md owned-files tables so future agents know which file owns which behavior.

Required Docs After Each Feature

Update the matching _agent/mvp/Platform_iOS/*.md.
Append DAILY_LOG.md.
Update MASTER_TODO_V4.md status.
Do not edit platform READMEs unless explicitly asked.
Verification

Run targeted flutter analyze --no-pub for touched iOS files.
Push to main only with narrow staged files.
Confirm GitHub Build iOS IPA workflow passes.
Give the user the Actions run link and exact artifact name.

---

Windows Follow-Up Handoff From iOS QA - 2026-05-02

These are not replacements for the cross-platform task list above. They are
new improvements discovered while testing the iOS parity port and should be
handled by the correct Windows agent in a future Windows-only pass.

W1. Resume/restart choice when re-entering present mode

Behavior: If the user leaves present mode in the middle of a long script,
edits something, and returns to present mode, the app should explicitly offer
to continue from the previous reading point or restart from the beginning.
Starting STT after choosing Continue must resume from the same confirmed/tapped
/scrolled/bookmarked position. Restart remains the only path that resets to
word 0.

Implementation insight: inspect the final Windows provider and presenter
resume logic first. If Windows already preserves `confirmedWordIndex` across
same-session re-entry, add only the dialog/choice layer. Compare stable script
identity, not widget/object identity. Same session should be based on stable
script/session metadata, not only the in-memory `Script` object instance.

W2. Search result navigation toolbar

Behavior: Search currently works, but when the same text appears many times,
the user should be able to move next/previous between results before closing
the search session. The UI should be compact and must not hide half the screen.

Implementation insight: inspect Windows and iOS presenter/editor search code.
Build a reusable result list from visible-text matches. Keep the search field
compact, with previous/next result buttons and a small result counter. Editor
mode must continue mapping visible matches back to raw markup offsets.
Presenter mode must continue jumping through the provider position path so
resume point, locale/alignment, bookmarks, and active STT state stay synced.
Do not implement this by showing a large modal that blocks the reading area.
