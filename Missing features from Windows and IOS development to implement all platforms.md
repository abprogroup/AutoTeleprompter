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

Windows implementation note 2026-05-03: DONE. Resume dialog implemented in
`teleprompter_screen.bookmarks_search.dart` `_showResumeDialog()`. On
presenter entry, if `confirmedWordIndex > 0`, the screen first jumps to the
saved position (so the user sees where they were), then shows a dialog offering
Continue (stay at saved position) or Restart (jump to word 0). Session identity
compared by `sessionId` string, not object identity. Implemented in
`teleprompter_provider.dart` `startSession()`.

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

Windows implementation note 2026-05-04: DONE. Two separate implementations:

Editor search (`script_editor_screen.search.dart`, new file, commit 36063d5):
- All-match scan across all blocks at once using `StylingService.stripTags()`
- Persistent toolbar: ← match counter (3/12) → | query text | Word toggle | search | close
- Whole-word toggle with Hebrew word-boundary support (`[A-Za-z0-9֐-׿]`)
- `_jumpToEditorSearchMatchAt()` uses `MarkupController.visualToRawOffset()` to
  map visible matches back to raw markup offsets before selecting
- Search button added to `ProjectActionsSuite` toolbar

Presenter search (`teleprompter_screen.bookmarks_search.dart`, commit 36063d5):
- Replaced `List<int>` word-index matches with typed `_PresenterSearchMatch`
  objects carrying `{wordIndex, charStart, charEnd}`
- Char-based full-text search via `_PresenterSearchText` / `_PresenterSearchSpan`
  for accurate phrase matching across multi-word queries
- Same Hebrew whole-word boundary rules as editor search
- Search results jump instantly via `_jumpToWordIndex(wordIndex, immediate: true)`
- Same compact toolbar style as editor

---

iOS Follow-Up Commits — 2026-05-03 (commits 568abba → 21c1f36)

These iOS commits immediately preceded the Windows parity work and complete
the iOS bookmark + search stabilization. They are separate from the W1–W20
Windows items above.

iOS-P1. Stabilize iOS search toolbar and bookmarks (568abba)

Major stabilization pass for iOS editor and presenter search toolbar and
bookmark behavior. Rewrote key sections of `script_editor_screen.search.dart`,
`teleprompter_screen.search.dart`, `script_editor_screen.bookmarks.dart`,
and `teleprompter_screen.bookmarks.dart`. Fixed toolbar state persistence,
bookmark jump accuracy, and presenter search match navigation.

iOS-P2. Tighten iOS default STT recovery window (573071e)

Tightened the forward-match window in `word_aligner.dart` (shared file used by
both iOS and Windows) to reduce false jumps during default 5-word local
recovery. Stricter confidence threshold before advancing the confirmed word
index. This file is shared — any future change to STT recovery window must be
verified on both platforms.

iOS-P3. Place iOS editor bookmark markers at correct anchors (13dd7cc)

Fixed bookmark `»` sign placement in `script_editor_screen.editor_block.dart`
and `script_editor_screen.bookmarks.dart`. Markers were being drawn at wrong
visual anchor points inside the block layout. Editor block now positions the
`»` glyph precisely at the stored block offset rather than at the leading edge
of the block widget.

iOS-P4. Fix iOS bookmark marker overlap (ddf87d0)

Fixed visual overlap when two `»` markers appeared adjacent in the same block,
and resolved overlap between editor bookmark gutter indicators and the
teleprompter presenter word layout. Updated `teleprompter_screen.build.dart`
word row rendering to give bookmark indicators their own non-overlapping slot.

iOS-P5. Normalize iOS bookmark marker sign (2cd8a85)

Normalized the `»` character representation across editor and presenter.
Replaced multi-byte legacy sequences with the canonical `»` code point
everywhere in `script_editor_screen.editor_block.dart` and
`teleprompter_screen.build.dart`.

iOS-P6. Add iOS text-flow bookmark signs as full implementation (21c1f36)

Complete implementation of text-flow `»` bookmark signs in iOS:
`script_editor_screen.bookmarks.dart` extended with sign insertion, scan,
sync, and reconcile logic. `script_editor_screen.editor_block.dart` fully
restructured to render the `»` sign as part of the text flow.
`script_editor_screen.selection_clipboard.dart` updated to treat `»` as a
normal visible character during cut/copy/paste. `script_editor_screen.search.dart`
updated to skip `»` in visible-text match offsets.

---

iOS Fixes — 2026-05-03 Session (commits 3b990bb, 6dbdb33)

These two iOS fixes were applied in the same session and are not tracked
elsewhere in this file.

iOS-F1. Suppress iOS native selection toolbar on global/overlay selection
(commit 3b990bb)

Behavior: When the app owns a multi-block selection via the overlay, the iOS
native "Cut / Copy / Paste" toolbar should not appear on top of it. The
native toolbar's async re-appearance after Select All was re-selecting only the
double-tapped word, breaking global selection state.

iOS implementation note 2026-05-03: DONE (commit 3b990bb).
`contextMenuBuilder` in `_EditorBlock` (`script_editor_screen.editor_block.dart`)
was simplified — removed the `selectAllAndReopenToolbar()` helper that was
attempting to fight iOS's async native-selection reset with 120/180 ms
`Future.delayed` calls. The new builder suppresses the native toolbar entirely
when a global or overlay selection is active, delegating all Cut/Copy/Paste to
the app's own commands. `adoptPartialSelectionAfterMenuBuild()` retained for
the partial-selection path.

iOS-F2. Sync presenter bookmark deletions back to editor (commit 6dbdb33)

Behavior: When a bookmark is deleted in presenter mode, the change must be
reflected in the editor without requiring a full reload. The `»` sign in the
editor text and the metadata must both be removed.

iOS implementation note 2026-05-03: DONE (commit 6dbdb33).
Updated `script_editor_screen.bookmarks.dart` and `script_editor_screen.
file_present.dart`. On return from the presenter, `_startPresenting()` now
calls `_reconcileEditorBookmarkSignsFromMetadata(recordHistory: false)` after
the presenter screen is popped. This strips any `»` signs whose metadata was
deleted in presenter mode and re-inserts only the signs that still have
metadata, keeping editor text and metadata in sync without creating spurious
history entries.

---

Windows-Only Improvements — 2026-05-03/04 Session (commits a3abb9b, 36063d5, f0d159b)

These items were not on the original cross-platform task list. They are new
Windows improvements discovered and implemented during the v5.0 parity work.

W3. Cross-block arrow key navigation (keyboard long-press)

Behavior: Pressing and holding left/right/up/down arrow keys should chain
smoothly across paragraph blocks without stalling at boundaries.

Windows implementation note 2026-05-03: DONE (commit a3abb9b).
Root cause was Flutter desktop focus-dispatch race: async `requestFocus()`
during key-repeat caused multiple repeat events to fire on the old block.
Fix: `HardwareKeyboard.instance.addHandler(_onGlobalArrowKey)` in initState/
dispose. This fires before Flutter's focus system so key-repeat never stalls.
`_lastFocusedController` is updated synchronously before `requestFocus()` so
subsequent repeat events always use the correct block. RTL (Hebrew) direction
awareness included. iOS does NOT need this — iOS `TextField` chains arrows
natively via the OS focus system.

W4. Visual bookmark signs `»` (U+00BB) as real text characters

Behavior: Bookmark markers should be visible in the text, behave like regular
characters (delete with backspace, copy with text), and keep editor and
presenter in sync. Old metadata-only bookmarks should auto-migrate on load.

Windows implementation note 2026-05-04: DONE (commit 36063d5).
Ported from iOS `script_editor_screen.bookmarks.dart`. The `»` character is
inserted at the cursor by `_addEditorBookmark()`; metadata is derived by
scanning `»` positions via `_syncBookmarksFromEditorSigns()`. On first load,
`_reconcileEditorBookmarkSignsFromMetadata()` migrates old metadata-only
bookmarks by inserting `»` at the saved offsets. All save/present/STT paths
strip `»` via `_getRefinedFullTextWithoutBookmarkSigns()` before tokenizing so
the sign is never spoken. History snapshots keep `»` so undo/redo correctly
restores bookmark positions. The `_EditorBlock` gutter now shows
`Icons.bookmark` icon instead of a duplicate `»` text to avoid visual confusion.

W5. Selection handles sync to text on scroll

Behavior: When a word is selected and the user scrolls, the selection handles
should move with the text and disappear when the selection is fully scrolled
off-screen.

Windows implementation note 2026-05-04: DONE (commit f0d159b).
Wrapped `widget.child` in `NotificationListener<ScrollNotification>` inside
`GlobalSelectionOverlay.build()`. On every scroll notification,
`_calculateHandlePositions()` is called via `addPostFrameCallback` so handles
track their text position accurately. The off-screen visibility guard
(`pos.dy < -56 || pos.dy > _stackSize.height + 56`) was already present and
now fires correctly because positions are kept current.

W6. Handle drag promotes native single-block selections on pointer-up

Behavior: Double-clicking a word or drag-to-select within one block should
produce overlay handles, not just native selection highlighting.

Windows implementation note 2026-05-04: DONE (commit f0d159b).
`_promoteNativeSelectionToOverlay()` is called from `onPointerUp` in the
editor's `Listener` widget. It checks the focused block's native selection
after any gesture ends and promotes it to the overlay if non-collapsed and
partial (not full-block). Promotion is NOT done in the controller listener
during drag — doing it during drag caused a "1-letter selected" freeze because
once `overlayActive = true`, no further controller-listener updates were
allowed. Pointer-up is the correct trigger.

W7. Autoscroll stop on deselection

Behavior: If a handle-drag autoscroll is running and the user deselects via
keyboard or tap, the autoscroll must stop immediately.

Windows implementation note 2026-05-04: DONE (commit f0d159b).
Added `_stopAutoScroll()` as the first line of `clearSelection()` in
`GlobalSelectionOverlay`. Previously only `onPanEnd` stopped the timer, so
keyboard or tap deselection left it running indefinitely.

W8. Arrow keys collapse overlay selection correctly

Behavior: When text is selected via overlay handles, pressing any arrow key
should clear the selection and move the cursor to the selection start (← ↑)
or end (→ ↓), matching standard OS text-editing behavior.

Windows implementation note 2026-05-04: DONE (commit f0d159b).
In `_onGlobalArrowKey`, when `_isGlobalSelection || overlay.hasSelection`,
collapse each controller's native selection to start or end depending on arrow
direction, clear `isGlobalSelected`/`externalSelection`, call
`clearSelection()`, then return `false` so Flutter moves the cursor normally
from the collapsed position.

W9. Editor undo/redo history fixes

Behavior: Cut should appear as "Cut" in history (not "Delete"). Deleting an
empty line should create a history entry. Undo/redo should not jump the
viewport to the wrong scroll position.

Windows implementation note 2026-05-03: DONE (commit a3abb9b).
- `_deleteSelection(isCut: bool)` now logs "Cut" vs "Delete" based on caller.
- Backspace on empty block now calls `_saveHistory(description: 'Delete Empty Line')`.
- Undo/redo uses two-phase scroll restore: `requestFocus()` at 150 ms, then
  `WidgetsBinding.addPostFrameCallback` scroll, so TextField's internal
  auto-scroll settles before `_scrollEditorBlockIntoView` overrides it.

W11. Drag-handle autoscroll speed increase (Windows only)

Behavior: Dragging a selection handle to the edge of the editor viewport should
scroll fast enough to be usable on long scripts.

Windows implementation note 2026-05-03: DONE (commit a3abb9b).
`_autoScrollMax` in `global_selection_overlay.dart` raised from 18 px/tick to
40 px/tick. At 16 ms intervals that is ~2400 px/s at maximum speed (handle at
viewport edge), approximately 2-3 screenfuls per second.

W12. Clipboard snapshot guard — stale rich markup protection (Windows only)

Behavior: After copying styled text inside the app, if the user then copies
plain text from outside the app, a subsequent paste inside the app should use
the new plain text — not the stale rich markup from the earlier app copy.

Windows implementation note 2026-05-04: DONE (commit 36063d5).
Added `RichClipboard.clearInternal()` static method to `rich_clipboard.dart`.
After every `_onCopyClean()` / `_onCut()`, `_startClipboardGuard(expectedPlain)`
starts a 20-second `Timer`. On expiry it reads the current OS clipboard text;
if it no longer matches the expected plain text, `clearInternal()` is called.
Timer is cancelled in `dispose()`. iOS handles the equivalent problem through
the 20-second `_globalSelectionSnapshot` TTL in `selection_clipboard.dart` —
the mechanisms differ but the protection is equivalent.

W10. GlobalSelectionOverlay state machine upgrade (Windows only)

The Windows `GlobalSelectionOverlay` gained a full session state machine not
present on iOS. When merging overlay changes between platforms, the Windows
version is significantly more complex than iOS.

New types added (Windows only, commit range 36063d5–f0d159b):
- `SelectionSessionMode` enum: `none`, `overlaySelection`, `handleDrag`, `keyboardExtend`
- `SelectionPointerState` enum: `inside`, `edgeZone`, `outside`, `stale`
- `_HandleDragSession` class: encapsulates all per-drag state including
  auto-scroll timer and stale-pointer timeout
- `SelectionSessionSnapshot`: public read-only snapshot for debugging
- `isHandleInteractionActive` getter: used by `_promoteNativeSelectionToOverlay`
  guard to prevent re-activation during active handle drag
- `isPointInsideHandle(globalPos)`: hit-test helper used externally

iOS overlay remains simpler (no state machine). Do not assume a Windows overlay
change transfers cleanly to iOS without accounting for these additions.

---

Windows V3-SYNC Pass — 2026-05-03/04 (commits dd5263c → 4f81c58)

Eight follow-up commits from a separate Windows QA agent fixing handle, arrow,
autoscroll, and bookmark issues discovered after the v5.0 parity commits above.
All tracked in `_agent/mvp/Platform_Windows/selection_mvp.md` and
`script_editor_mvp.md`.

W13. Endpoint A/B ownership model — handle bar placement (dd5263c)

Root cause: overlay mixed endpoint ownership with normalized document order,
causing handles to draw inside the selected text rather than just outside it.
Fix: overlay treats `_startOffset`/`_endOffset` as stable raw ownership points
and normalizes only for highlight/copy/cut rendering. Handle bars are drawn
just outside selected text (caret boundary = selection truth). Editor Focus
shell now ignores arrows entirely — `HardwareKeyboard` is the single arrow
owner, eliminating duplicate handling. Debug sentry updated to report overlay
endpoint/range state and last arrow decision.

W14. Body drag + bookmark coordinate sync (41056d8)

Root cause: fast handle drags could activate body drag from inside an existing
handle hit box, moving the wrong endpoint; bookmark word-index mapping used
raw text offsets including `»` signs, misaligning present-mode positions.
Fix: body drag refuses to activate from an existing handle hit box and ignores
body drag updates while a handle session is active. When hit boxes overlap,
pan-start chooses the nearest visible handle center. Present-mode entry now
rebuilds bookmark metadata from live `»` text signs and maps word indexes
against the same cleaned/tokenized text that the presenter receives. Return
from presenter reconciles editor signs from metadata without creating a history
entry.

W15. Screen-level Ctrl/Cmd C/X/V + Ctrl Up/Down block navigation (cc87e99)

Root cause: Ctrl+C/Ctrl+X could break after a handle gesture because
copy/cut depended on TextField focus which was lost; Ctrl+Up/Down stalled at
current block start/end without crossing to adjacent blocks.
Fix: screen-level keyboard handling owns Ctrl/Cmd+C, X, V when an app-owned
overlay or global selection exists, so copy/cut/paste work regardless of
TextField focus state. Ctrl+Up/Down are block-aware: repeated presses move to
current block start/end first, then to the previous/next block.
Ctrl+Shift+Up/Down can extend selection to block boundaries and uses the app
overlay when the selected range crosses blocks.

W16. Shift-extension anchor preservation + autoscroll pointer zone (f3c8944)

Root cause: autoscroll timer could keep running after the pointer returned to
the safe middle zone of the screen; Shift+arrow combinations could restart
selections instead of extending from the existing anchor.
Fix: editor page forwards active handle pointer moves into
`GlobalSelectionOverlay` so the overlay can stop autoscroll immediately when
the pointer re-enters the safe zone. Shift-extension now preserves the existing
anchor and moves only the active (focus) edge. Modified horizontal/vertical
arrows use block-aware target helpers when crossing paragraph boundaries.

W17. Full session state machine + hard handle exit preservation (514abb3)

Root cause: after hard edge dragging and repeated Shift/Ctrl/Alt arrow
extension, handle state could become fragile — abandoned hard exits sometimes
converted into body drag selections.
Fix: overlay exposes `SelectionSessionSnapshot` with endpoint A/B plus
anchor/focus. Existing app-owned selection extension uses the fixed
anchor/focus model instead of deriving direction from the normalized range.
Hard handle exits now preserve the current selection, stop autoscroll, clear
active handle state, and block body-drag promotion until pointer-up or explicit
selection clear. Full Select All is excluded from Shift-extension and collapses
through the normal selection-clear path first. Alt+Left/Right uses block-aware
targets while preserving native in-block editing where safe.

W18. Plain Shift vertical selection + edge autoscroll mouse-exit fix (9996a7e)

Root cause: plain Shift+Up/Down selected to script top/bottom around empty rows
or grabbed entire second blocks; dragging handles to editor top/bottom no
longer triggered autoscroll.
Fix: plain Shift+Up/Down stays native inside a single block; at a block
boundary (or when selection is already app-owned) the editor moves the focus
endpoint by visual line using `TextPainter` geometry instead of paragraph
start/end targets. Empty blocks remain one-step selection stops.
Mouse exit no longer immediately ends a handle drag while the pointer is in the
edge-scroll zone. The overlay keeps scrolling from the latest pointer/handle
position and uses hard-margin/outside checks plus a stale timeout to stop
abandoned drags.

W19. Handle drag lifecycle refactor — `_HandleDragSession` (92de866)

Root cause: per-drag state was scattered across individual flags, making the
autoscroll and stale-drag logic brittle.
Fix: all active handle state consolidated into one private `_HandleDragSession`
object: endpoint ownership, pan-start pointer/caret positions, latest
pointer/handle positions, `SelectionPointerState`, autoscroll timer, stale
timer. Returning to the safe center stops autoscroll without ending the drag;
edge-zone movement keeps scrolling from the latest pointer; hard outside and
stale timeout end the session while preserving the selected range.

W20. Ctrl+Shift+Down past `»` signs + handle endpoint continuity (4f81c58)

Root cause: Ctrl+Shift+Down beside a bookmark `»` character could select the
entire script; handle edge drags could scroll briefly then stop following the
pointer while the button remained pressed.
Fix: Ctrl vertical paragraph navigation ignores `»` bookmark signs for target
arithmetic only, then maps the result back to raw editor offsets so the sign
remains real selectable text. Shift-arrow now clears a stale overlay selection
if the focused collapsed caret no longer matches the overlay focus endpoint,
instead of extending that old range. Page-level active-handle pointer updates
move the active endpoint and deduplicate identical positions so returning to
the editor safe zone can pull the selection back under the mouse.

W21. Stale selection + handle re-entry correction (12c17d0)

Root cause: stale overlay validation could clear or reuse the wrong focus
state after app-owned keyboard crossing, and hard handle exits still treated
some recoverable re-entry paths as abandoned drags. Fix: validate Shift reuse
against the editor's synchronous focused controller/caret authority, preserve
selection while suspended, and resume endpoint updates on re-entry when the
mouse button is still held.

W22. Selection follow-up correction (bc370d8)

Root cause: Ctrl+Shift horizontal crossings could create partial highlighted
islands after entering the next block, and vertical pointer movement outside
the editor could be mistaken for hard outside exit. Fix: block-aware
horizontal targets now keep one anchor/focus selection range through crossings;
vertical out-of-editor movement remains edge-zone autoscroll while horizontal
hard exits still suspend the drag.

W23. Mirrored vertical arrow logic (785aee0)

Root cause: Down-arrow behavior diverged from the better Up-arrow behavior.
Fix: vertical caret/line detection now compares caret Y against
`TextPainter` line metric centers for both directions. Cross-block targets use
mirrored first/last line center math instead of asymmetric top/bottom checks.
Handle code was intentionally untouched.

W24. Shift selection isolation + body drag scroll (3fd996b)

Root cause: Shift had too many competing routes, causing jumps,
deselections, and accidental select-all escalation at block boundaries.
Fix: Shift+Arrow uses one app-owned route: normal arrow target helpers choose
the destination, Shift only extends anchor-to-focus. Transient full-block
native selections do not escalate to Select All while Shift is pressed. Body
click-drag selection received its own edge autoscroll timer separate from the
verified handle drag system.

W25. Shift anchor preservation (317f3e5)

Root cause: reaching block starts/ends with Shift could reset selection and
start fresh from the new block. Fix: existing app-owned Shift selections keep
their original anchor and move only the focus endpoint through the next block
target. Shrinking/reversing direction collapses toward the anchor instead of
creating a second range.

W26. Selection-method bridge (969d288)

Root cause: double-click selection, click-drag selection, handle drag, and
Shift extension could not reliably continue each other. Fix: the latest
mouse/handle focus endpoint becomes the bridge point for subsequent Shift
extension. Double-click + handle drag, click-drag + handle drag, and then
Shift extension all share one app-owned anchor/focus model.

W27. Shift after mouse selection (385911e)

Root cause: after a mouse selection method ended, Shift extension still did
not consistently adopt the released endpoint. Fix: mouse-release and last
dragged-handle endpoints now seed the app-owned keyboard selection focus so
Shift can continue selection without clearing the previous range.

macOS parity port — 2026-05-04

The macOS implementation has been ported against Windows `385911e` with
Windows-only runtime paths excluded. macOS now carries the selection/session
model, editor search toolbar, text-flow bookmark signs, bookmark-safe history,
clipboard guard, visible-skip-aware word aligner, presenter search/bookmark
sync, resume behavior, body-drag edge autoscroll, and bridged mouse/handle/
Shift selection methods. macOS intentionally does not receive WebView2 STT,
Windows mic selector UI, `setx`, Windows Settings links, or Windows speech
pack dialogs. Future platform ports should treat `385911e` plus this macOS
port as the current behavior reference.
