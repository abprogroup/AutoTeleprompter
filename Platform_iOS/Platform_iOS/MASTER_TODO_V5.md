# Master TODO List: AutoTeleprompter v5.0 Android
# (Premium Features & Deferred Functionality)

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
