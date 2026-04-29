# MVP Protocol Root: Total Platform Separation

This directory acts as the central architectural nervous system for the AutoTeleprompter project. It maps out the boundaries, contracts, and strict rules for every feature (MVP) within the application.

It is also the architectural contract layer for feature ownership, public call
boundaries, invariants, forbidden changes, known fragilities, and
platform-specific implementation notes.

## 🛡️ The 4-Way MVP Strategy

To completely eliminate the risk of cross-platform regressions (e.g., a Windows bug fix accidentally breaking iOS), the project embraces **Total Platform Separation**.

Both the codebase and this documentation are physically decoupled into 4 distinct branches:

- `/Platform_Windows/`
- `/Platform_iOS/`
- `/Platform_Android/`
- `/Platform_macOS/`

The MVP protocol files that describe those implementations live under:

- `_agent/mvp/Platform_Windows/`
- `_agent/mvp/Platform_iOS/`
- `_agent/mvp/Platform_Android/`
- `_agent/mvp/Platform_macOS/`

### How Documentation is Structured

You will not find a single `stt_mvp.md` file in this root directory. Instead, if an AI agent is working on the Windows Speech-to-Text engine, they MUST navigate into `Platform_Windows/` and read the `stt_mvp.md` document located there.

This guarantees **Zero Cross-Platform Hallucinations**. The agent will only ever see the rules, files, and constraints relevant to the specific platform they are actively editing.

If an agent is working on a Windows feature, it must read the matching document
inside `_agent/mvp/Platform_Windows/` before touching owned files. Do not infer
Windows rules from iOS, Android, or macOS docs except as historical context or
formatting examples.

The same rule applies to every platform: before touching files under
`/Platform_iOS/`, `/Platform_Android/`, or `/Platform_macOS/`, read the matching
MVP document inside that platform's `_agent/mvp/Platform_*` directory. If the
matching MVP document does not exist, that absence is a protocol gap and must be
documented before implementation proceeds.

## 📜 MVP Document Structure

Inside each platform directory, every feature has an MVP document (e.g., `Platform_Windows/auth_mvp.md`). Each document strictly defines:

1. **Owned Files**: A comprehensive list of the files that make up this feature.
   - *Shared Contracts*: Files that are identical across all platforms and dictate the core interface.
   - *Platform Specifics*: Files isolated to this specific platform's implementation.
2. **External API**: The exact methods and fields that other components are allowed to call. If it isn't listed here, it is a private internal function.
3. **All Callers**: A mapping of what external features rely on this MVP.
4. **Invariants**: Absolute logical truths and physics rules of the feature that must NEVER be broken.
5. **Forbidden Changes**: Explicit actions that AI agents and developers are barred from doing to prevent known regressions.
6. **Known Fragilities**: Documented weak points, race conditions, or quirks that require extreme caution.

Additive platform hardening rule:

7. **Shared-File Ownership Notes**: Section-level ownership when several MVPs share one large file.

## Platform MVP Indexes

Every platform directory must be indexed here. A platform is not considered
fully protocol-ready until all major source subsystems have matching MVP docs
with owned files, external APIs, callers, invariants, forbidden changes, known
fragilities, and shared-file ownership notes where needed.

### Windows MVP Index

The Windows platform currently has these MVP contracts:

| MVP | Context Doc | Governs |
|-----|-------------|---------|
| Auth | `Platform_Windows/auth_mvp.md` | Local login, license state, admin bypass |
| Remote | `Platform_Windows/remote_mvp.md` | Local remote-control server and command stream |
| Script Editor | `Platform_Windows/script_editor_mvp.md` | Editor orchestration, block controllers, gallery handoff |
| Settings | `Platform_Windows/settings_mvp.md` | App settings, recent scripts, persistence keys |
| Teleprompter Engine | `Platform_Windows/teleprompter_engine_mvp.md` | Presentation state, scrolling, word advancement |
| STT | `Platform_Windows/stt_mvp.md` | Windows speech adapters, callbacks, speech lifecycle |
| History | `Platform_Windows/history_mvp.md` | Undo/redo stack and history persistence |
| Selection | `Platform_Windows/selection_mvp.md` | Multi-block selection, overlay handles, copy/cut/delete |
| Styling Engine | `Platform_Windows/styling_engine_mvp.md` | Markup transforms, hidden tags, style detection/rendering |
| Editor Suites | `Platform_Windows/editor_suites_mvp.md` | Toolbar and suite widgets named `*_mvp.dart` |
| File I/O | `Platform_Windows/file_io_mvp.md` | Import/export, DOCX/RTF/Pages/TXT paths |
| Bookmarks | `Platform_Windows/bookmarks_mvp.md` | Cross-mode script anchors, visible markers, add/remove, previous/next jumps |
| Scrolling | `Platform_Windows/scrolling_mvp.md` | Presenter scroll physics, active-STT follow, stopped browsing, direct jumps |
| Content Creator | `Platform_Windows/content_creator_mvp.md` | Dormant recording/camera feature code |
| Platform Shell | `Platform_Windows/platform_shell_mvp.md` | App boot, shell, Windows no-op platform helpers, splash |

### iOS MVP Index

The iOS platform currently has these MVP contracts:

| MVP | Context Doc | Governs |
|-----|-------------|---------|
| Audio Buffer | `Platform_iOS/audio_buffer_mvp.md` | Gap-free language switching during STT recognition by capturing buffered audio |
| Auth | `Platform_iOS/auth_mvp.md` | Local login, license state, admin bypass |
| Remote | `Platform_iOS/remote_mvp.md` | Local remote-control server and command stream |
| Script Editor | `Platform_iOS/script_editor_mvp.md` | Editor orchestration, block controllers, gallery handoff |
| Settings | `Platform_iOS/settings_mvp.md` | App settings, recent scripts, persistence keys |
| Teleprompter Engine | `Platform_iOS/teleprompter_engine_mvp.md` | Presentation state, scrolling, word advancement |
| STT | `Platform_iOS/stt_mvp.md` | iOS speech-recognition session lifecycle, bilingual section switching, error handling, and word-alignment feedback loop |
| History | `Platform_iOS/history_mvp.md` | Undo/redo stack, history persistence, typing-bulk and suite-sectioned auto-save logic |
| Selection | `Platform_iOS/selection_mvp.md` | Multi-block text selection, overlay drag handles, cut/copy, and native TextField selection interplay |
| Styling Engine | `Platform_iOS/styling_engine_mvp.md` | Markup transforms, hidden tags, style detection/rendering |
| Editor Suites | `Platform_iOS/editor_suites_mvp.md` | Toolbar and suite widgets named `*_mvp.dart` |
| File I/O | `Platform_iOS/file_io_mvp.md` | Import/export, DOCX/RTF/Pages/TXT paths |
| Bookmarks | `Platform_iOS/bookmarks_mvp.md` | Planned Windows v4.1.12 bookmark migration contract |
| Scrolling | `Platform_iOS/scrolling_mvp.md` | Planned Windows v4.1.12 presenter scrolling migration contract |
| Content Creator | `Platform_iOS/content_creator_mvp.md` | Dormant recording/camera feature code |
| Platform Shell | `Platform_iOS/platform_shell_mvp.md` | App boot, shell, iOS platform helpers, splash |

### Android MVP Index

The Android platform currently has these MVP contracts:

| MVP | Context Doc | Governs |
|-----|-------------|---------|
| Auth | `Platform_Android/auth_mvp.md` | User authentication, local persistence states, and premium license boundaries |
| Remote | `Platform_Android/remote_mvp.md` | Localized network listener mapping and remote-control security boundaries |
| Script Editor | `Platform_Android/script_editor_mvp.md` | Editor orchestration, block controllers, gallery handoff, legacy editor reference |
| Settings | `Platform_Android/settings_mvp.md` | App settings, recent scripts, persistence keys |
| Teleprompter Engine | `Platform_Android/teleprompter_engine_mvp.md` | Presentation state, scrolling, word advancement |
| STT | `Platform_Android/stt_mvp.md` | Android STT adapter, native speech bridge, callbacks, speech lifecycle |
| History | `Platform_Android/history_mvp.md` | Undo/redo stack and history persistence |
| Selection | `Platform_Android/selection_mvp.md` | Multi-block selection, overlay handles, copy/cut/delete |
| Styling Engine | `Platform_Android/styling_engine_mvp.md` | Markup transforms, hidden tags, style detection/rendering |
| Editor Suites | `Platform_Android/editor_suites_mvp.md` | Toolbar, suite widgets, and Android file-save helper MVP |
| File I/O | `Platform_Android/file_io_mvp.md` | Import/export, DOCX/RTF/TXT paths, Android file save |
| Bookmarks | `Platform_Android/bookmarks_mvp.md` | Planned Windows v4.1.12 bookmark migration contract |
| Scrolling | `Platform_Android/scrolling_mvp.md` | Planned Windows v4.1.12 presenter scrolling migration contract |
| Content Creator | `Platform_Android/content_creator_mvp.md` | Dormant recording/camera feature code |
| Platform Shell | `Platform_Android/platform_shell_mvp.md` | App boot, shell, Android platform helpers, splash |

### macOS MVP Index

The macOS platform currently has these MVP contracts:

| MVP | Context Doc | Governs |
|-----|-------------|---------|
| Auth | `Platform_macOS/auth_mvp.md` | Local login, license state, admin bypass |
| Remote | `Platform_macOS/remote_mvp.md` | Local remote-control server and command stream |
| Script Editor | `Platform_macOS/script_editor_mvp.md` | Editor orchestration, block controllers, gallery handoff |
| Settings | `Platform_macOS/settings_mvp.md` | App settings, recent scripts, persistence keys |
| Teleprompter Engine | `Platform_macOS/teleprompter_engine_mvp.md` | Presentation state, scrolling, word advancement |
| STT | `Platform_macOS/stt_mvp.md` | macOS Apple STT adapter, callbacks, speech lifecycle |
| History | `Platform_macOS/history_mvp.md` | Undo/redo stack and history persistence |
| Selection | `Platform_macOS/selection_mvp.md` | Multi-block selection, overlay handles, copy/cut/delete |
| Styling Engine | `Platform_macOS/styling_engine_mvp.md` | Markup transforms, hidden tags, style detection/rendering |
| Editor Suites | `Platform_macOS/editor_suites_mvp.md` | Toolbar and suite widgets named `*_mvp.dart` |
| File I/O | `Platform_macOS/file_io_mvp.md` | Import/export, DOCX/RTF/Pages/TXT paths |
| Bookmarks | `Platform_macOS/bookmarks_mvp.md` | Planned Windows v4.1.12 bookmark migration contract |
| Scrolling | `Platform_macOS/scrolling_mvp.md` | Planned Windows v4.1.12 presenter scrolling migration contract |
| Content Creator | `Platform_macOS/content_creator_mvp.md` | Dormant recording/camera feature code |
| Platform Shell | `Platform_macOS/platform_shell_mvp.md` | App boot, shell, macOS platform helpers, splash |

## Platform Coverage Status

| Platform | MVP Docs Present | Protocol Readiness |
|----------|------------------|--------------------|
| Windows | 15 | Full major-source-subsystem MVP index present plus Windows Bookmarks and Scrolling contracts |
| iOS | 16 | Full major-source-subsystem MVP index present, including iOS-only Audio Buffer design plus planned Bookmarks and Scrolling migration contracts |
| Android | 15 | Full major-source-subsystem MVP index present plus planned Bookmarks and Scrolling migration contracts |
| macOS | 15 | Full major-source-subsystem MVP index present plus planned Bookmarks and Scrolling migration contracts |

## Shared-File Ownership

Some platform files are intentionally shared by multiple MVPs. Ownership is by
section, not by whole file. This rule applies separately inside every
`Platform_*` directory:

- `script_editor_screen.dart`: editor orchestration, history, selection,
  styling commands, save/import, and suite wiring each have separate MVP owners.
- `teleprompter_provider.dart`: STT session callbacks, teleprompter advancement,
  remote hooks, and settings reads have separate MVP owners.
- `settings_provider.dart`: settings persistence, recent script metadata, and
  history metadata are shared by Settings, History, Script Editor, and File I/O.
- `markup_controller.dart` and `styling_logic_mixin.dart`: Selection and Styling
  Engine share raw/visible selection and markup transformation boundaries.
- `Platform_Android/lib/features/script/widgets/v3.9.5.1_script_editor_screen.dart`:
  legacy Android editor evidence is documented by Script Editor, History,
  Selection, and Styling where relevant.

When changing a shared file, read every MVP that owns the affected section before
editing. Never change an external API without updating all callers and the
relevant MVP documents.

## Windows v4.1.12 Sealed Contract Capsule

Windows v4 is sealed at `4.1.12+12` as of 2026-04-29. The final backup is
`backups/final_windows_v4/20260429_103357`.

Before porting Windows behavior to another platform, read the Windows MVP docs
for the source behavior and then read the matching target-platform MVP docs.
Do not copy Windows implementation details blindly into iOS, Android, or macOS.

Windows v4.1.12 source contracts to preserve during migration:

- STT stop/start resumes at the current word; only Restart resets to word `0`.
- Bookmarks are shared between editor and presenter, support multiple anchors,
  visible markers, explicit removal, and active-STT previous/next jumps.
- Search jumps by visible text and maps back to raw markup only after the match.
- Active STT locks user scroll and owns row-progress follow; stopped STT allows
  browsing and updates the resume point.
- Direct navigation commands such as bookmarks, search, tap, and restart jump
  immediately rather than using smooth STT follow.
- Font size has one persisted metadata value across editor, presenter, style
  tags, settings, and export. Presenter visual scaling is display-only.
- Spacing ranges are synchronized between editor and presenter.
- Symbols, quotes, punctuation, and intentional blank lines are not disposable.
- RTF/DOCX export must convert app markup to document styling; plain exports
  must write visible text only.
- External microphone selection is implemented on Windows through WebView2
  audio input enumeration with system-default fallback.

V5 refactor gate: every platform has editor/presenter screen files above the
preferred 1000-line ceiling. Split these only as behavior-preserving,
platform-local refactors, and update every affected MVP doc in the same commit.

## Windows v4 Final Verified Capsule (Added 2026-04-29)

Windows v4.1.12 is now user verified and ready as the migration source for iOS
and later V5 work. Latest verified Windows behavior commit: `160d137`.
Verified workflow run: `Build Windows EXE (v4.1.12)` / `25110648732`.

Windows no longer violates the current maintainability gate: every Dart file
under `Platform_Windows/lib` is below 800 lines after the behavior-preserving
screen split. The old 2885/2528 line counts are historical pre-split evidence
only.

Final Windows contracts that target platforms must understand before porting:

- STT stop/start resumes at the current word; only Restart resets to `0`.
- Default STT local recovery may skip up to 5 missed words.
- `Allow visible text skip` is opt-in, bounded to the rendered viewport, and
  fallback-only after nearby 3+ word phrase priority fails.
- Active STT locks manual scroll and owns row-progress follow. Stopped mode
  allows browsing and resume-point selection.
- Bookmarks sync between editor and presenter, show markers, support explicit
  add/remove, allow active-STT previous/next jumps, and must be usable from
  both modes.
- Search uses visible text first and maps back to raw markup offsets only after
  the match.
- Font size has one saved metadata value. Presenter visual scaling is
  display-only and must not be persisted.
- Spacing ranges match between editor and presenter.
- Symbols, quotes, punctuation, and intentional blank lines are preserved.
- RTF/DOCX/Pages/plain exporters must not leak app-private markup tags.
- Windows external mic selection uses WebView2 audio input enumeration with
  system-default fallback; other platforms must document their own OS limits.

Next active platform: iOS. Before touching iOS source, read the matching
`_agent/mvp/Platform_iOS/*.md` documents and port the behavior in iOS-native
terms. Do not copy Windows WebView2 or desktop-specific implementation details
blindly.

## ⚖️ Zero-Collateral Damage Mandate

When working within an MVP:

- **Never touch files outside the "Owned Files" list** unless specifically requested by the user.
- **Respect the boundaries.** If the Script Editor MVP states that it does not interact with STT, you must not inject STT dependencies into the Script Editor.
- **Do not guess shared logic.** If you modify a *Shared Contract* file, you must recognize that your change will eventually affect the other 3 platforms when the logic is ported. Exercise extreme surgical precision.
- Never touch files outside the relevant MVP's owned-file list unless the user
  specifically asks or the target section is listed as shared ownership.
- Respect platform separation. Windows documentation describes Windows behavior
  only.
- Preserve cumulative documentation. Do not truncate rows, delete historical
  details, or simplify away invariants.
- Before modifying owned files, list affected invariants and callers, then verify
  the change preserves them.

---

## Verbatim Original Protocol Block

This block preserves the pre-hardening root protocol text verbatim so future
edits can remain append-only against the original contract.

```markdown
# MVP Protocol Root: Total Platform Separation

This directory acts as the central architectural nervous system for the AutoTeleprompter project. It maps out the boundaries, contracts, and strict rules for every feature (MVP) within the application.

## 🛡️ The 4-Way MVP Strategy

To completely eliminate the risk of cross-platform regressions (e.g., a Windows bug fix accidentally breaking iOS), the project embraces **Total Platform Separation**. 

Both the codebase and this documentation are physically decoupled into 4 distinct branches:
- `/Platform_Windows/`
- `/Platform_iOS/`
- `/Platform_Android/`
- `/Platform_macOS/`

### How Documentation is Structured
You will not find a single `stt_mvp.md` file in this root directory. Instead, if an AI agent is working on the Windows Speech-to-Text engine, they MUST navigate into `Platform_Windows/` and read the `stt_mvp.md` document located there. 

This guarantees **Zero Cross-Platform Hallucinations**. The agent will only ever see the rules, files, and constraints relevant to the specific platform they are actively editing.

## 📜 MVP Document Structure

Inside each platform directory, every feature has an MVP document (e.g., `Platform_Windows/auth_mvp.md`). Each document strictly defines:

1. **Owned Files**: A comprehensive list of the files that make up this feature.
   - *Shared Contracts*: Files that are identical across all platforms and dictate the core interface.
   - *Platform Specifics*: Files isolated to this specific platform's implementation.
2. **External API**: The exact methods and fields that other components are allowed to call. If it isn't listed here, it is a private internal function.
3. **All Callers**: A mapping of what external features rely on this MVP.
4. **Invariants**: Absolute logical truths and physics rules of the feature that must NEVER be broken.
5. **Forbidden Changes**: Explicit actions that AI agents and developers are barred from doing to prevent known regressions.
6. **Known Fragilities**: Documented weak points, race conditions, or quirks that require extreme caution.

## ⚖️ Zero-Collateral Damage Mandate

When working within an MVP:
- **Never touch files outside the "Owned Files" list** unless specifically requested by the user. 
- **Respect the boundaries.** If the Script Editor MVP states that it does not interact with STT, you must not inject STT dependencies into the Script Editor.
- **Do not guess shared logic.** If you modify a *Shared Contract* file, you must recognize that your change will eventually affect the other 3 platforms when the logic is ported. Exercise extreme surgical precision.
```
