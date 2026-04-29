# Master TODO List: AutoTeleprompter v5.0
# (Premium Features & Deferred Functionality — All Platforms)

### Status Legend
- `[ ]` = Planned; Not started.
- `[T]` = Pending AI test; Was not tested by AI.
- `[R]` = Reverted; AI testing failed; Reverting/Fixing.
- `[F]` = AI testing failed; Not reverted.
- `[P]` = AI test verified; Pending Manual User verification.
- `[X]` = User test failed; Bug still present after fix attempt.
- `[U]` = User Verified; Confirmed working (Confirmed by User).
- `[-]` = Deferred; Should be attached with an explanation why.

## 📜 Rules of Protocol
- **Versioning**: Only the USER can authorize major stable version jumps. AI performs sub-version steps for internal tracking.
- **Cleanup**: `[U]` items are preserved for history and only cleared by the USER during major stable version transitions.
- **Surgical Updates**: When updating the TODO list or Logs, only modify the specific item(s) related to the current task. Do NOT shorten, delete, or summarize unrelated items.
- **Persistence**: Deferred `[-]` and unfinished items are **NEVER** deleted, maintaining a full project audit trail.
- **v4.0 Reference**: The sealed v4.0 TODO is at `MASTER_TODO.md`. Do not modify it.
- **Git Reference**: The commit `6ae6a22` is the last commit before v4.0 hiding. Use `git show 6ae6a22:<path>` to view the pre-hiding state of any file.

---

## 🎤 Speech Recognition Engine

### Native Android STT (Built, functional, active in v4.0)
- [ ] **STT Engine Selector UI**: Dropdown to choose between Google STT and Whisper models. Built and working but removed from settings screen.
  - *File*: `lib/features/settings/widgets/app_settings_screen.dart`
  - *What was removed*: `_SectionHeader(title: 'SPEECH RECOGNITION')`, engine dropdown (`DropdownButton<String>` with `_EngineOption` items), the `_EngineOption` class, and all Whisper-related state (`_downloadedModels`, `_downloading`, `_downloadStatus`, `_checkAllModels()`, `_downloadModel()`, `_deleteModel()`).
  - *To restore*: Check git history for the full `app_settings_screen.dart` before v4.0 seal. The engine dropdown and model cards were in the `build()` method between the Profile section and the end of the ListView.

### Whisper Offline Models UI (Built, functional, hidden)
- [ ] **Whisper Model Download/Delete Cards**: UI cards for each Whisper model (Tiny 75MB, Base 142MB, Small 466MB, Medium 1.5GB) with download progress, delete confirmation, and auto-select after download.
  - *File*: `lib/features/settings/widgets/app_settings_screen.dart`
  - *What was removed*: `_SectionHeader(title: 'OFFLINE MODELS')`, the `for (final info in whisperModels)` loop rendering `_ModelCard` widgets, the `_ModelCard` class (shows download/delete/active state for each model).
  - *Still functional*: `WhisperSpeechService` in `lib/features/teleprompter/services/whisper_speech_service.dart` — `downloadModel()`, `deleteModel()`, `isModelDownloaded()` all work. Model list defined in `whisperModels` const.
  - *Integrity*: Download uses `.complete` marker files. `isModelDownloaded()` checks both model file AND marker. `initialize()` cleans up partial downloads (no marker = delete file).

### Whisper Streaming Service (Built, functional, active as auto-fallback)
- [ ] **Whisper Speech Service**: Full offline speech recognition using whisper.cpp via `whisper_flutter_new` package.
  - *File*: `lib/features/teleprompter/services/whisper_speech_service.dart`
  - *How it works*: Records audio via `record` package at 16kHz mono PCM. Accumulates in buffer. Every 500ms checks if 2.5s+ of audio available. Takes up to 4s chunk, writes WAV, runs whisper.cpp inference, appends result to `_fullTranscript`, sends to provider for word alignment.
  - *Known issues*: Inference too slow on older phones (7-8s for 3-4s audio on Oppo A53 with base model). Tiny model faster but less accurate. Hallucination filtering (`_isArtifact()`) catches common false positives ("[Music]", "Thanks for watching", etc.).
  - *Auto-fallback*: `_autoFallbackToWhisper()` in `teleprompter_provider.dart` tries whisper_tiny → whisper_base → whisper_small when all Google STT stages fail.

### Native STT 4-Stage Fallback (Built, functional, active in v4.0)
- [ ] **MainActivity.kt Native STT**: Custom MethodChannel-based speech recognition with 4-stage fallback.
  - *File*: `android/app/src/main/kotlin/com/autoteleprompt/autoteleprompt/MainActivity.kt`
  - *Channel*: `autoteleprompter/stt` — methods: `isAvailable`, `start`, `stop`. Callbacks: `onResult`, `onStatus`, `onError`, `onNeedLanguagePack`.
  - *Stage 0*: `SpeechRecognizer.createOnDeviceSpeechRecognizer(context)` with locale (e.g., `en-US`). Uses app's mic permission. Needs SODA language pack.
  - *Stage 1*: Same on-device recognizer, no locale (device default language).
  - *Stage 2*: `SpeechRecognizer.createSpeechRecognizer(context, ComponentName("com.google.android.tts", "...GoogleTTSRecognitionService"))` — targets Speech Services by Google directly.
  - *Stage 3*: `SpeechRecognizer.createSpeechRecognizer(context)` — default recognizer (works on Samsung/Pixel).
  - *Stage 4*: All failed → `onNeedLanguagePack` callback → triggers `_autoFallbackToWhisper()` in Dart.
  - *ColorOS issue*: `appops RECORD_AUDIO: foreground` on Google app blocks stages 2 & 3. SODA packs for on-device recognizer are separate from Speech Services packs — stages 0 & 1 fail with error 12/13.
  - *Dart wrapper*: `lib/features/teleprompter/services/native_speech_service.dart` — `NativeSpeechService` class with `onResult`, `onStatusChange`, `onError`, `onLanguageUnavailable`, `onNeedLanguagePack` callbacks.

### STT Provider Settings (Built, functional, hidden default)
- [ ] **STT Engine Setting**: Provider field for selecting active engine.
  - *File*: `lib/features/settings/providers/settings_provider.dart`
  - *Field*: `sttEngine` (String, default `'google'`). Values: `'google'`, `'whisper_tiny'`, `'whisper_base'`, `'whisper_small'`, `'whisper_medium'`.
  - *Method*: `setSttEngine(String engine)` — persists to SharedPreferences key `'sttEngine'`.
  - *Used by*: `teleprompter_provider.dart` in `startSession()` — checks `sttEngine.startsWith('whisper')` to decide engine.

---

## 🎬 Content Creator Mode

### Recording Screen (Built, functional, hidden)
- [ ] **ContentCreatorScreen**: Full camera + teleprompter overlay with video recording.
  - *File*: `lib/features/teleprompter/widgets/content_creator_screen.dart`
  - *What it does*: Front camera preview with teleprompter text overlay. Start/stop video recording with timer. Countdown before recording. Save to gallery via `gal` package. Camera resolution from settings.
  - *Dependencies*: `camera` package, `gal` package, `path_provider`.
  - *How it was accessed*: Record button (videocam icon) in `ProjectActionsSuite` top bar → navigated to `ContentCreatorScreen`. See `v3.9.5.1_script_editor_screen.dart` line 1005 for the old navigation code.
  - *What was removed from UI*: The Record/videocam `IconButton` was removed from `ProjectActionsSuite` in `lib/features/script/widgets/editor/suites/project_actions_mvp.dart`. The PRESENT button was made full-width to fill the space.

### Live Streaming (Not built)
- [ ] **Live Streaming**: Real-time broadcast from teleprompter. Not yet implemented — placeholder for v5.0.

### Video Export (Not built)
- [ ] **Video Export**: Export recorded presentations with teleprompter overlay. Not yet implemented — placeholder for v5.0.

---

## ☁️ Cloud Sync

### Cloud Sync Screen (Built, placeholder UI, not functional)
- [ ] **CloudSyncScreen**: Settings screen for connecting cloud storage providers.
  - *File*: `lib/features/settings/widgets/cloud_sync_screen.dart`
  - *What it shows*: Three connection cards (Google Drive, Dropbox, AutoTeleprompter Cloud) + auto-sync toggles (auto-sync on save, upload recordings automatically). All `onTap` callbacks are empty `() {}` — no backend wired.
  - *How it was accessed*: `_ProDashboard` widget in gallery screen had a "CLOUD SYNC" card that navigated to `CloudSyncScreen`.

### Pro Dashboard (Built, hidden)
- [ ] **_ProDashboard**: Premium feature card shown on gallery home screen.
  - *File*: `lib/features/script/widgets/script_gallery_screen.dart` — widget was removed, only comment remains at line 182.
  - *What it showed*: "CLOUD SYNC" card with cloud icon. Tapped → navigated to `CloudSyncScreen`.
  - *To restore*: Check `git show 6ae6a22:AutoTeleprompter/lib/features/script/widgets/script_gallery_screen.dart` for the `_ProDashboard` class (line 324-371).

---

## 🔐 Login & Authentication

### Auth Provider (Built, functional, hidden)
- [ ] **AuthNotifier / AuthState**: User authentication state with email, Pro status, admin detection, and license key.
  - *File*: `lib/features/auth/providers/auth_provider.dart`
  - *State fields*: `email` (String?), `isPro` (bool), `isAdmin` (bool), `licenseKey` (String?).
  - *Methods*: `login(email)`, `logout()`, `activateLicense(key)`. Persists to SharedPreferences (`auth_email`, `auth_is_pro`, `auth_license_key`).
  - *Admin*: `abmpro.office@gmail.com` auto-activates Pro with key `'PRO-ADMIN-V3'`.
  - *License check*: Mock — any key starting with `'PRO-'` activates Pro.
  - *Provider*: `authProvider` — `StateNotifierProvider<AuthNotifier, AuthState>`.

### Login Screen (Built, functional, hidden)
- [ ] **LoginScreen**: Email + license key activation screen with purchase dialog.
  - *File*: `lib/features/auth/widgets/login_screen.dart`
  - *What it shows*: AutoTeleprompter branding, email text field, license key text field (obscured), ACTIVATE LICENSE button, "NEED A LICENSE?" link → purchase dialog ($29.99 lifetime mock).
  - *How it was accessed*: Login button (`Icons.login_rounded`) in gallery app bar when `auth.email == null`. After login, shows account menu with avatar, email, settings gear, logout.
  - *What was removed from gallery*: The entire auth-dependent app bar section — login button, account avatar, email display, settings icon, logout. See `git show 6ae6a22:...script_gallery_screen.dart` lines 61-131.

---

## 🎮 Controller & Remote

### Remote Control Service (Built, functional, hidden)
- [ ] **RemoteControlService**: WebSocket-based remote control server for teleprompter.
  - *File*: `lib/features/remote/services/remote_control_service.dart`
  - *What it does*: Starts HTTP+WebSocket server on port 8080. Serves a responsive HTML remote control page. Receives commands: `TOGGLE`, `FASTER`, `SLOWER`, `RESET`, `MODE_MANUAL`, `MODE_AUTO`. Exposes `onCommand` stream.
  - *Dependencies*: `shelf`, `shelf_router`, `shelf_web_socket`, `web_socket_channel` packages.
  - *Provider*: `remoteControlProvider` — `Provider((ref) => RemoteControlService())`.
  - *How it was connected*: `teleprompter_provider.dart` had `_setupRemoteCallbacks()` which listened to `onCommand` stream and translated commands to scroll speed changes / position resets. Now empty method: `void _setupRemoteCallbacks() {}`.

### Remote Dashboard (Built, hidden)
- [ ] **_RemoteDashboard**: Gallery widget showing remote control status and connection info.
  - *File*: `lib/features/script/widgets/script_gallery_screen.dart` — widget was removed, only comment at line 182.
  - *What it showed*: Server start/stop toggle, IP address display, QR code for connection, action buttons (Guide, Share). Was gated behind `auth.isPro`.
  - *To restore*: Check `git show 6ae6a22:...script_gallery_screen.dart` for `_RemoteDashboard` class (line 373-520) and `_RemoteActionBtn` (line 521-540).

### Remote Hub Button (Built, hidden)
- [ ] **Remote Hub App Bar Button**: Gallery app bar button to access remote control.
  - *What was removed*: `_RemoteActionBtn` in gallery app bar (wifi_tethering icon). Showed "Remote Hub" tooltip for Pro users, "Premium Feature" for free users. Gated behind `auth.isPro`.
  - *To restore*: Check `git show 6ae6a22:...script_gallery_screen.dart` lines 61-77.

---

## 🛠️ Settings & Configuration

### Settings Button in Editor (Hidden)
- [ ] **Settings IconButton in Editor Top Bar**: Quick access to settings from the script editor.
  - *File*: `lib/features/script/widgets/editor/suites/project_actions_mvp.dart`
  - *What was removed*: `IconButton(icon: Icon(Icons.settings), onPressed: () => Navigator.push(...AppSettingsScreen()))` was in the top action bar row. The comment at line 4 says: "v4.0: Stable Release — Record and Settings buttons hidden (premium features)".
  - *To restore*: Add settings and record IconButtons back to the `Row` in `build()`. The old version had: back, delete, save, import, **settings**, **record** buttons.

### Debug Mode Toggle (Active, accessed via hidden gesture)
- [ ] **Debug Mode**: Triple-tap on gallery header toggles debug mode.
  - *File*: `lib/features/script/widgets/script_gallery_screen.dart`
  - *How it works*: Triple-tap on the app title calls `settingsProvider.notifier.toggleDebugMode()`. Shows debug logs in teleprompter screen (STT results, heartbeat, word alignment).
  - *Status*: Still functional in v4.0 — accessed via hidden gesture, not a settings toggle.

---

## 📝 UI Polish (Carried from earlier versions)

- [ ] **FEATURE: RTL/LTR Suite Hardening**: Re-add Direction buttons with Locked logic. (Deferred per user instruction in v3.x)
  - *File*: `lib/features/script/widgets/editor/suites/layout_suite_mvp.dart` — comment at line 8: "Alignment via icons, RTL/LTR deferred".

- [ ] **Faded Files in Picker**: Grey out/disable unsupported files in file picker. Needs dedicated file picker widget. (Deferred since v2.x)

- [ ] **Emulator Hebrew Keyboard Bridge**: Hebrew keyboard input in Android emulator. (Deferred — hard to implement, not critical for production)

## 🪟 Windows & macOS — Deferred
- [ ] **Windows - Whisper Offline STT (Backup Solution)**: Disabled for Windows build to prevent native plugin conflicts. To be revisited as a premium desktop feature.
- [ ] **Windows - Web Browser STT (Premium Fallback)**: The previously developed `webview_windows` embedded localhost STT wrapper. To be preserved as a premium fallback engine if native SAPI or Whisper fails, utilizing an optical trick (`Opacity(0.01)`) to maintain connection without disrupting the UI.
- [ ] **macOS - Verification**: Run macOS build on a Mac to verify `SttAppleAdapter` performance.

## 📽️ Presentation Mode — Pending Fixes
- [ ] **Upcoming Text Highlight**: Add a toggle in settings similar to "Upcoming text color" that resets the highlight background of read text.
- [ ] **Spacing Synchronization**: Ensure line spacing, word spacing, and letter spacing values perfectly sync between the editor and presentation mode. Allow negative scales (down to -1.0) in presentation mode to match the editor's default limit constraints.
- [ ] **Bookmarks / Chapter Jumping**: Add script-level bookmarks so long scripts can be divided into chapters, scenes, or filming sections. Presentation mode should allow jumping directly to saved bookmark sentences, starting STT from that point, and resuming after pause/stop without resetting to the beginning. v4.1 Windows has the first lightweight step: tap a word in presentation mode to set the current resume point; full bookmark creation, labels, persistence, and chapter navigation belong to v5.
- [ ] **Edit From Present Mode**: Add a presenter control that exits or overlays into script editing at the current reading/bookmark position, so corrections can be made without hunting for the same sentence in editor mode. The edit path must stop STT first, preserve the current resume point, and return to presentation without resetting to the beginning.

## 🎙️ Audio Input — Pending Features
- [ ] **External Microphone / Input Device Selector**: Add cross-platform support for choosing an outer connected microphone for STT and recording workflows. Windows now has the v4 baseline: WebView2/browser STT enumerates `audioinput` devices, persists `sttInputDeviceId` + label, exposes a presenter dropdown, applies live changes without resetting script position, and falls back to system default when the saved mic is unavailable. V5 should port or formally document equivalent behavior for iOS, Android, and macOS, including whether each platform allows app-level input selection or only OS-level routing. (Requested from Windows testing 2026-04-28; Windows baseline implemented 2026-04-28)

---

## 📋 Quick Reference: What Was Hidden Where

| Feature | Hidden From | File | How to Find Old Code |
|---------|-------------|------|---------------------|
| STT Engine Selector | Settings screen | `app_settings_screen.dart` | Git history pre-v4.0 seal |
| Whisper Model Cards | Settings screen | `app_settings_screen.dart` | Git history pre-v4.0 seal |
| Record Button | Editor top bar | `project_actions_mvp.dart` | Comment at line 4 |
| Settings Button | Editor top bar | `project_actions_mvp.dart` | Comment at line 4 |
| Login Button | Gallery app bar | `script_gallery_screen.dart` | `git show 6ae6a22:<path>` |
| Account Menu | Gallery app bar | `script_gallery_screen.dart` | `git show 6ae6a22:<path>` |
| Cloud Sync Card | Gallery home | `script_gallery_screen.dart` | `_ProDashboard` at commit `6ae6a22` |
| Remote Dashboard | Gallery home | `script_gallery_screen.dart` | `_RemoteDashboard` at commit `6ae6a22` |
| Remote Hub Button | Gallery app bar | `script_gallery_screen.dart` | `_RemoteActionBtn` at commit `6ae6a22` |
| Remote Callbacks | Teleprompter provider | `teleprompter_provider.dart` | `_setupRemoteCallbacks()` emptied at line 50 |

---
*Created: 2026-04-13 (Carried deferred items from v4.0 sealed TODO)*

## 🎙️ iOS Audio Buffer MVP — Seamless Bilingual STT Switching

- [ ] **Audio Buffer for Gap-Free Locale Switching (iOS)**: When the STT switches languages mid-script, a ~300ms gap occurs where speech is captured by neither the old nor new recognizer. For fast readers this causes words to be missed at every section boundary.
  - *Design doc*: `_agent/mvp/Platform_iOS/audio_buffer_mvp.md`
  - *Approach*: Replace `speech_to_text` plugin on iOS with a custom native `SpeechBridge.swift` that owns `AVAudioEngine` directly. At `setLocale()` call: tap continues capturing to an in-memory buffer → new `SFSpeechRecognizer` initialized → buffer replayed via `SFSpeechAudioBufferRecognitionRequest` → live mic hands off seamlessly.
  - *Why deferred*: Requires replacing the `speech_to_text` plugin for iOS — high-risk change to a working STT system. Deferred until v5 native plugin work is planned.
  - *User preference option*: In v5, expose an STT method selector so users can choose between: (A) current plugin-based switching, (B) native bridge with audio buffer catch-up.
  - *Implementation phases (documented in MVP)*: Phase 1 — custom bridge parity; Phase 2 — audio tap + buffer; Phase 3 — `setLocale()` with buffer replay; Phase 4 — remove `speech_to_text` from iOS pubspec.
  - *Dependency*: Must ship after STT Engine Selector UI (above) is restored, since the selector UI is how users would choose between methods.
---

## V5 Platform Migration Prep From Windows v4.1.12 (Added 2026-04-29)

- [x] **Windows Behavior-Preserving Large File Split Gate**: Windows V5 prep
  split `script_editor_screen.dart` and `teleprompter_screen.dart` into Dart
  `part` files on 2026-04-29. All Windows split files are under 750 lines, and
  targeted analyzer found no compile errors. This is a mechanical extraction
  only; no in-app behavior was intentionally changed.
- [ ] **Cross-Platform Behavior-Preserving Large File Split Gate**: Before adding major V5
  features, split oversized editor/presenter screens into MVP-owned files. The
  first targets are `script_editor_screen.dart` and `teleprompter_screen.dart`
  on every platform. Keep each extracted file ideally under 500-1000 lines.
  Required extraction candidates: search/bookmarks, presentation controls,
  debug console/sound bar, scroll controller, STT controls, editor block list,
  editor shortcut/search, style metadata synchronization, import/export
  orchestration, and project action toolbar. No behavior changes during the
  split.
- [ ] **Cross-Platform Bookmark System**: Port the Windows v4.1.12 bookmark
  baseline to iOS, Android, and macOS: multiple anchors, visible markers,
  add/remove in editor and presenter, previous/next buttons, active-STT jumps,
  direct jump behavior, and shared persistence between modes.
- [ ] **Cross-Platform Presenter Search**: Port visible-text search with raw
  markup offset mapping and presenter resume-point updates.
- [ ] **Cross-Platform STT Resume/Stop Contract**: Stop tears down recognition
  without resetting the script; start resumes from the current index; Restart is
  the only reset-to-zero action.
- [ ] **Cross-Platform Presenter Scroll Contract**: Active STT locks manual
  scrolling and uses row-progress follow; stopped mode allows browsing and
  resume-point selection; bookmark/search/restart commands jump immediately.
- [ ] **Cross-Platform Typography Contract**: One font-size metadata value must
  drive editor controls, presenter controls, style tags, save metadata, and
  export. Any editor/presenter visual scale must be display-only.
- [ ] **Cross-Platform Export Hygiene**: RTF/DOCX/Pages exporters must convert
  app-private markup into document styling or visible text, never leak raw
  `[color]`, `[size]`, bold, alignment, or display-only tags.
- [ ] **Present-Mode Script Editing Button**: Add a presenter control that opens
  editing at the current bookmark/reading position. It must stop STT first,
  preserve the resume point, and return to presenter without resetting.

## V5/iOS Handoff From Final Windows v4.1.12 (Finalized 2026-04-29)

- [x] **Windows v4 Source Baseline Locked**: Windows v4.1.12 is user verified
  and ready as the migration source for iOS and future V5 work. Latest verified
  behavior commit is `160d137`; Windows workflow run `25110648732` passed.
- [x] **Windows Maintainability Gate Passed**: All Dart files under
  `Platform_Windows/lib` are below 800 lines after the behavior-preserving
  split. Future Windows V5 work must keep edits in the smallest owning part
  file and update the matching MVP document in the same change.
- [ ] **iOS Large File Split Gate**: Before adding large iOS features, split
  iOS editor/presenter screens by MVP ownership using the Windows Dart `part`
  pattern only if it preserves private state and behavior. This is a refactor
  gate, not a feature task.
- [ ] **iOS STT Resume + Visible Skip Migration**: Port the final Windows STT
  behavior to iOS with platform-appropriate Apple STT implementation:
  stop/start preserves position, default local recovery allows up to 5 missed
  words, longer skip requires an opt-in visible-viewport setting, and visible
  skipping remains fallback-only after nearby 3+ word phrase priority.
- [ ] **iOS Presenter Viewport Contract**: Presenter must publish the rendered
  visible word window for skip decisions, lock manual scroll while STT is
  active, allow stopped browsing/resume selection, and keep bookmark/search
  direct jumps immediate.
- [ ] **iOS Bookmarks/Search Migration**: Port Windows cross-mode bookmarks and
  visible-text search: multiple anchors, visible markers, explicit add/remove
  controls, active-STT previous/next bookmark jumps, editor/presenter sync, and
  raw-markup offset mapping only after visible-text matching.
- [ ] **iOS Typography/Export Migration**: Enforce one font-size metadata value
  across editor, presenter, style tags, settings, and export; keep any
  presenter visual scale display-only; sync spacing ranges; preserve symbols,
  quotes, punctuation, and blank lines; prevent app-private markup from leaking
  into RTF/DOCX/Pages/plain exports.
- [ ] **Cross-Platform External Mic Policy**: Windows supports WebView2 audio
  input enumeration with system-default fallback. For iOS, Android, and macOS,
  document whether the platform supports in-app input device selection or only
  OS-level routing before implementation.
