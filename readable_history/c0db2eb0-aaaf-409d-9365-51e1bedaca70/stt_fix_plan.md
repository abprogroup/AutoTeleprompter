# Windows STT Hardening — Phase 2: Audio Integrity

## The Problem
Windows reports `STATUS: SpeechStatus.listening` and `STT using locale: en-US`, but no words are captured. This indicates the engine is running but receiving "dead air" or silent buffers.

## Root Cause Hypotheses
1. **Audio Routing Failure**: The plugin is bound to a "listening" session but isn't receiving audio data from the Windows Microphone (potentially due to sample rate mismatch or exclusive mode).
2. **Dictation Mode Mismatch**: `ListenMode.dictation` might be unsupported by the specific Windows build or driver, causing the engine to stay silent.
3. **Locale Strictness**: Even though `en-US` was matched, the Windows native Speech recognizer might be failing to load the acoustic model silently.

## Proposed Strategy

### 1. Audio Level Monitoring (Telemetry)
Add an `onSoundLevelChange` listener. This will log a 💓 heart-rate style sound meter in the debug log.
- If sound level is `> 0`, the mic is working and the issue is **Recognition** (Language/Model).
- If sound level is `0.0` or constant, the issue is **Hardware/Privacy/Routing** (Audio Input).

### 2. "System Default" Force Fallback
Bypass my `_findBestLocale` normalization and pass `localeId: null` if the requested language matches the system default language. This is often more stable on Windows than requesting a specific string like `en-US`.

### 3. Verbose Result Logging
Log *every* `onResult` call, even if it contains an empty string, to see if the plugin is firing but failing to fill the word buffer.

## Execution Steps

### [MODIFY] [speech_service.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/services/speech_service.dart)
- [ ] Add `onSoundLevelChange` callback support.
- [ ] In `_startListening`, add `onSoundLevelChange` listener to `_stt.listen`.
- [ ] Add `print` or `_addLog` for every `onResult` callback triggered.
- [ ] Change `listenMode` to `ListenMode.confirmation` as a fallback or remove it.

### [MODIFY] [teleprompter_provider.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart)
- [ ] Handle the new `onSoundLevelChange` and pipe it to `_addDebugLog`.

### [MODIFY] [abstract_stt_service.dart](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Platform_Windows/lib/platform/stt/abstract_stt_service.dart)
- [ ] Add `onSoundLevelChange` to the interface.

---

## User Verification Plan
1. **The Sound Meter Check**: Run the app and look at the debug log.
   - Do you see `[Windows] VOL: X.X` changing as you speak?
   - If YES, we know the mic is fine and we need to fix the Language ID.
   - If NO, the Windows OS is blocking audio even though it says it's listening.

2. **The Default Mode Test**: I will provide a build that avoids specific locale indices to see if SAPI auto-discovery is more reliable.
