import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/debug_log_formatter.dart';
import '../services/speech_service.dart';
import '../services/stt_locale_section_service.dart';
import '../services/stt_recognition_policy_service.dart';
import '../services/whisper_speech_service_native.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../settings/providers/settings_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/stt/stt_service_factory.dart';

class TeleprompterNotifier extends Notifier<TeleprompterState> {
  late final AbstractSttService _sttService;
  late final WhisperSpeechService _whisperService;
  late final RemoteControlService _remoteControlService;
  bool _useWhisper = false;
  Script? _currentScript;
  String _accumulatedTranscript = '';
  bool _disposed = false;
  int _noProgressCount = 0;
  Timer? _heartbeatTimer;
  Timer? _fluidAdvanceTimer;
  int _fluidTarget = 0;
  String? _scriptLanguageLocale;
  String? _activeLocale; // locale the STT is currently using
  List<String> _sectionLocales =
      []; // per-word locale map, pre-computed at session start
  Future<void>? _stopInFlight;
  int _sessionToken = 0;
  int? _visibleWordStart;
  int? _visibleWordEnd;
  bool _sttReadingStandby = false;

  // ── Tuning: how patient we are before force-skipping ───────────────────────
  static const int _googleSkipAfterStuck = 45;
  static const int _whisperSkipAfterStuck = 10;
  static const int _maxAdvancePerUpdate = 30;

  @override
  TeleprompterState build() {
    _disposed = false;
    _sttService = SttServiceFactory.create();
    _whisperService = WhisperSpeechService();
    _remoteControlService = ref.read(remoteControlProvider);
    _setupRemoteCallbacks();
    _setupSttCallbacks();
    _setupWhisperCallbacks();
    Future.microtask(refreshAudioInputDevices);
    ref.onDispose(() {
      _disposed = true;
      _heartbeatTimer?.cancel();
      _sttService.stop();
      _whisperService.stop();
      _remoteControlService.stop();
    });
    return const TeleprompterState();
  }

  // Remote commands are translated at the presenter screen edge.
  void _setupRemoteCallbacks() {}

  bool _sessionStopped = false;
  // Guard against the race where iOS fires an async 'notListening' status
  // from the previous stop() call after the new session has already started.
  bool _startingSession = false;

  void _safeSetState(TeleprompterState Function(TeleprompterState) updater) {
    if (_disposed || _sessionStopped) return;
    try {
      final current = state;
      state = updater(current);
    } catch (_) {
      _disposed = true;
    }
  }

  void _addDebugLog(String log) {
    if (_disposed) return;
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.debugMode) return;
    } catch (_) {
      return;
    }
    final now = DateTime.now();
    final ts =
        "${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}";
    final entry = "[$ts] ${DebugLogFormatter.normalize(log)}";
    final logs = [...state.debugLogs, entry];
    if (logs.length > 80) logs.removeRange(0, logs.length - 80);
    _safeSetState((s) => s.copyWith(debugLogs: logs));
  }

  /// Common handler for STT results — shared between Google and Whisper
  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;

    final words = result.words.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);

      // Voice Commands
      if (words.contains('stop prompt') ||
          words.contains('עצור') ||
          words.contains('עצירה')) {
        _addDebugLog('🗣️ VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') || words.contains('בוא')) {
        _addDebugLog('🗣️ VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return;
      } else if (words.contains('speed up') || words.contains('מהר')) {
        _addDebugLog('🗣️ VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') || words.contains('לאט')) {
        _addDebugLog('🗣️ VOICE COMMAND: SLOWER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }
    } catch (_) {}

    _accumulatedTranscript = result.words;
    final script = _currentScript!;
    final settings = ref.read(settingsProvider);
    final policy =
        SttRecognitionPolicyService.recognitionPolicyForSettings(settings);
    final maxSkipTargetIndex =
        policy.visibleSkipEnabled && _visibleWordStart != null
            ? _visibleWordEnd
            : null;

    final aligned = WordAligner.align(
      script: script.words,
      transcript: _accumulatedTranscript,
      lastConfirmedIndex: state.confirmedWordIndex,
      visibleSkipStartIndex:
          maxSkipTargetIndex == null ? null : _visibleWordStart,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: policy.bulletMode,
      policy: policy,
      readingStandby: _sttReadingStandby,
    );

    final currentIdx = state.confirmedWordIndex;
    final nextExpected = (currentIdx + 1 < script.words.length)
        ? script.words
            .skip(currentIdx + 1)
            .where((w) => !w.isNewline)
            .take(3)
            .map((w) => w.raw)
            .join(' ')
        : '<END>';

    final engineTag = _useWhisper ? '🤖' : '🎤';
    // Near a section boundary use a tight threshold so any unrecognised
    // word in the STT restart gap is force-skipped in under a second
    // rather than waiting the full 45-cycle window.
    final skipThreshold =
        _useWhisper ? _whisperSkipAfterStuck : _effectiveSkipThreshold();

    if (aligned.shouldEnterStandby) {
      _sttReadingStandby = true;
      _noProgressCount = 0;
      _addDebugLog(
          '$engineTag 🔒 STANDBY | ${aligned.debugInfo} | heard: "${result.words}"');
      return;
    }

    if (aligned.shouldAdvance &&
        aligned.confirmedWordIndex > state.confirmedWordIndex) {
      _sttReadingStandby = true;
      _noProgressCount = 0;
      final capped = SttRecognitionPolicyService.resolveAdvanceTarget(
        currentIndex: state.confirmedWordIndex,
        alignedIndex: aligned.confirmedWordIndex,
        visibleMaxSkipTargetIndex: maxSkipTargetIndex,
        maxAdvancePerUpdate: _maxAdvancePerUpdate,
      );
      final advancedWord =
          capped < script.words.length ? script.words[capped].raw : '?';
      _addDebugLog(
          '$engineTag ✅ ADVANCE → #$capped "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "${result.words}"');

      // Fluid advancement: if jumping more than 3 words, animate
      // through intermediate words so the user's eye can follow.
      final jump = capped - state.confirmedWordIndex;
      if (jump <= 3) {
        // Small jump — instant
        _fluidAdvanceTimer?.cancel();
        _safeSetState((s) => s.copyWith(confirmedWordIndex: capped));
      } else {
        // Large jump — advance word by word with short delays
        _startFluidAdvance(capped, script);
      }
      _checkAndSwitchLocale();
    } else {
      if (!policy.bulletMode) {
        _sttReadingStandby = false;
      }
      _noProgressCount++;
      _addDebugLog(
          '$engineTag ⏸ WAIT #$_noProgressCount/$skipThreshold | heard: "${result.words}" | next: "$nextExpected"');

      if (SttRecognitionPolicyService.shouldForceSkipAfterNoProgress(
        strictBulletMode: policy.bulletMode,
        noProgressCount: _noProgressCount,
        skipThreshold: skipThreshold,
      )) {
        _noProgressCount = 0;
        final next = _nextRealWord(state.confirmedWordIndex, script);
        if (next != null) {
          final skippedWord = script.words[next].raw;
          _addDebugLog(
              '🤖 ⏭ FORCE SKIP → #$next "$skippedWord" (stuck too long)');
          _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
        }
      }
    }
  }

  void _setupSttCallbacks() {
    final platform = _sttService.platformName;

    _sttService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _sttService.onStatusChange = (status) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Ignore non-listening statuses during the start-up guard window.
      // This prevents stale async 'notListening' from the previous stop()
      // from resetting isListening=false right after the new session starts.
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('🎤 [$platform] STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _sttService.onError = (error) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('🎤 [$platform] STT ERROR: $error');
      if (error.contains('error_language')) return;
      final isFatal = error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available');
      _safeSetState((s) => s.copyWith(
            statusMessage: isFatal ? error : '',
            hasError: isFatal,
            isListening: isFatal ? false : s.isListening,
            isStarting: isFatal ? false : s.isStarting,
          ));
    };

    _sttService.onLanguageUnavailable = (requestedLocale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(
        _scriptLanguageLocale ?? requestedLocale,
      );
      _addDebugLog('🎤 [$platform] LANGUAGE UNAVAILABLE: $langName');
      _safeSetState((s) => s.copyWith(
            missingLanguage: langName,
            hasError: true,
            isListening: false,
            isStarting: false,
            statusMessage:
                'Speech recognition language not installed on this device',
          ));
    };

    // Android-only: fires when offline + cloud STT both fail for a language.
    // On Apple/Windows this callback is never invoked.
    _sttService.onNeedLanguagePack = (locale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(locale);
      _addDebugLog(
          '🎤 [$platform] ALL STT FAILED for $langName — internet required');
      _safeSetState((s) => s.copyWith(
            hasError: true,
            isListening: false,
            isStarting: false,
            statusMessage:
                '$langName speech recognition requires an internet connection. '
                'This language is not available offline on your device. '
                'Please connect to WiFi or mobile data and try again.',
          ));
    };

    _sttService.onAudioInputDevicesChanged = (devices) {
      if (_disposed) return;
      try {
        state = state.copyWith(audioInputDevices: devices);
      } catch (_) {
        _disposed = true;
      }
    };
  }

  void _setupWhisperCallbacks() {
    _whisperService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _whisperService.onStatusChange = (status) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('🤖 WHISPER STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _whisperService.onError = (error) {
      if (_disposed || _sessionStopped) return;
      _addDebugLog('🤖 WHISPER ERROR: $error');
      final isFatal =
          error.contains('not available') || error.contains('init failed');
      if (isFatal) {
        _safeSetState((s) => s.copyWith(
              statusMessage: error,
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
      }
    };
  }

  /// Auto-fallback to Whisper when Google STT is completely blocked
  /// (e.g., ColorOS devices where mic permission is restricted)
  // ignore: unused_element
  Future<void> _autoFallbackToWhisper(String langName) async {
    if (_disposed || _sessionStopped) return;

    // Try Whisper models in order: tiny (fastest), base, small
    const fallbackModels = ['whisper_tiny', 'whisper_base', 'whisper_small'];

    for (final engineKey in fallbackModels) {
      final model = whisperModelFromEngine(engineKey);
      final downloaded = await _whisperService.isModelDownloaded(model);
      if (downloaded) {
        _addDebugLog('🤖 WHISPER FALLBACK: Found $engineKey, switching...');
        _useWhisper = true;
        await _whisperService.start(
          localeId: _scriptLanguageLocale,
          model: model,
        );
        return;
      }
    }

    // No Whisper model available — show error with guidance
    _addDebugLog('❌ NO WHISPER MODEL — cannot fallback, showing error');
    _safeSetState((s) => s.copyWith(
          missingLanguage: langName,
          hasError: true,
          isListening: false,
          statusMessage: 'Google speech blocked on this device. '
              'Go to Settings and download a Whisper model for offline recognition.',
        ));
  }

  /// Animate word advancement from current position to [target],
  /// advancing one word every ~80ms so the eye can follow.
  void _startFluidAdvance(int target, Script script) {
    _fluidAdvanceTimer?.cancel();
    _fluidTarget = target;

    _fluidAdvanceTimer =
        Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_disposed || _sessionStopped) {
        timer.cancel();
        return;
      }
      final current = state.confirmedWordIndex;

      // If a newer result pushed the target further, follow it
      final effectiveTarget = _fluidTarget;

      if (current >= effectiveTarget) {
        timer.cancel();
        return;
      }

      // Advance to next non-newline word
      int next = current + 1;
      while (next < script.words.length && script.words[next].isNewline) {
        next++;
      }
      if (next > effectiveTarget) next = effectiveTarget;

      _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
    });
  }

  /// Returns a tight force-skip threshold when the current position is within
  /// 2 words of an upcoming language boundary, normal threshold otherwise.
  /// This lets the STT skip over the ~1 unrecognised word in the restart gap
  /// in under a second instead of waiting the full 45-cycle window.
  int _effectiveSkipThreshold() {
    return SttLocaleSectionService.effectiveSkipThreshold(
      sectionLocales: _sectionLocales,
      currentIndex: state.confirmedWordIndex,
      activeLocale: _activeLocale,
      normalThreshold: _googleSkipAfterStuck,
    );
  }

  /// Pre-emptively switch STT locale 1 word BEFORE the section boundary so
  /// the new recognizer is initialised and listening by the time the first
  /// word of the new language is spoken.  For fast readers the STT restart
  /// (~300 ms) completes during that 1-word window rather than after it.
  ///
  /// The 1 transition word that lands in the wrong-locale window is handled
  /// by the tight force-skip threshold from _effectiveSkipThreshold().
  void _checkAndSwitchLocale() {
    if (_useWhisper || _disposed || _sessionStopped) return;
    if (_sectionLocales.isEmpty) return;
    final currentIdx = state.confirmedWordIndex;
    if (currentIdx < 0 || currentIdx >= _sectionLocales.length) return;

    // Look 1 word ahead — switch early so STT is ready at the boundary.
    final needed = SttLocaleSectionService.localeForIndex(
      _sectionLocales,
      currentIdx + 1,
    );
    if (needed == _activeLocale) return;

    _addDebugLog('🌐 PRE-SWITCH: ${_activeLocale ?? "?"} → $needed '
        '(1 word ahead, cur=#$currentIdx)');
    _activeLocale = needed;
    _scriptLanguageLocale = needed;
    _sttService.setLocale(needed);
  }

  /// Find the next non-newline word index after [from]
  int? _nextRealWord(int from, Script script) {
    for (int i = from + 1; i < script.words.length; i++) {
      if (!script.words[i].isNewline) return i;
    }
    return null;
  }

  bool _isSameScriptSession(Script? previous, Script next) {
    if (previous == null) return false;
    if (identical(previous, next)) return true;
    final previousSession = previous.sessionId.trim();
    final nextSession = next.sessionId.trim();
    if (previousSession.isNotEmpty && previousSession == nextSession) {
      return true;
    }
    return previous.title == next.title && previous.rawText == next.rawText;
  }

  Future<void> startSession(Script script) async {
    final pendingStop = _stopInFlight;
    if (pendingStop != null) await pendingStop;
    if (_disposed) return;

    final token = ++_sessionToken;
    final sameScript = _isSameScriptSession(_currentScript, script);
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _sessionStopped = false;
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _sectionLocales = SttLocaleSectionService.sectionLocalesForScript(script);
    final sttEngine = ref.read(settingsProvider).sttEngine;
    _useWhisper = sttEngine.startsWith('whisper');
    final resumeIndex = sameScript ? state.confirmedWordIndex : 0;
    final startIndex = resumeIndex.clamp(
      0,
      script.words.isEmpty ? 0 : script.words.length - 1,
    );
    state = state.copyWith(
        confirmedWordIndex: startIndex,
        isListening: false,
        isStarting: true,
        hasError: false,
        statusMessage: '',
        debugLogs: [],
        missingLanguage: null);

    _addDebugLog(
        '🚀 SESSION START | ${script.words.where((w) => !w.isNewline).length} words');

    // Starting locale comes from the pre-computed section map (word 0).
    // This is exact: if the script opens in English but has a Hebrew section
    // later, we start in English — not skewed by the whole-script ratio.
    final localeId = SttLocaleSectionService.localeForIndex(
      _sectionLocales,
      startIndex,
    );
    _scriptLanguageLocale = localeId;
    _activeLocale = localeId;
    _addDebugLog(
        '🌐 START LOCALE: $localeId | ${_sectionLocales.toSet().length} distinct section(s)');

    // Start heartbeat timer in debug mode
    _heartbeatTimer?.cancel();
    final settings = ref.read(settingsProvider);
    if (settings.debugMode) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_disposed) return;
        final engineName =
            _useWhisper ? 'WHISPER' : _sttService.platformName.toUpperCase();
        final listening =
            _useWhisper ? _whisperService.isListening : _sttService.isListening;
        final pos = state.confirmedWordIndex;
        final total = script.words.where((w) => !w.isNewline).length;
        _addDebugLog(
            '💓 HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');
      });
    }

    if (_useWhisper) {
      final model = whisperModelFromEngine(sttEngine);
      _addDebugLog('🤖 Starting Whisper STT ($sttEngine) offline...');
      await _whisperService.start(localeId: localeId, model: model);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _whisperService.stop();
        return;
      }
    } else {
      final platform = _sttService.platformName;
      final selectedMicId = settings.sttInputDeviceId.trim();
      final selectedMicLabel = settings.sttInputDeviceLabel.trim();
      await _sttService.setAudioInputDevice(
        selectedMicId.isEmpty ? null : selectedMicId,
        label: selectedMicLabel.isEmpty
            ? 'System default microphone'
            : selectedMicLabel,
      );
      _addDebugLog('🎤 [$platform] Starting STT locale=$localeId...');
      final result = await _sttService.start(localeId: localeId);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _sttService.stop();
        return;
      }

      if (!result.success) {
        _addDebugLog('🎤 [$platform] STT FAILED: ${result.message}');
        _safeSetState((s) => s.copyWith(
              statusMessage: result.message ?? 'Speech recognition failed',
              hasError: true,
              isListening: false,
            ));
        return;
      }

      // Apple platforms (iOS/macOS) fire onStatusChange asynchronously,
      // so we set isListening=true immediately here to avoid the mic button
      // staying yellow while waiting for the callback.
      if (_sttService.requiresImmediateListeningFlag) {
        _startingSession = true;
        _safeSetState((s) => s.copyWith(isListening: true));
        // Auto-clear the guard after 1.5 s in case listening status never fires
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (token == _sessionToken) _startingSession = false;
        });
      }

      if (result.languageMissing && result.missingLanguageName != null) {
        _addDebugLog(
            '⚠️ [$platform] LANG MISSING: ${result.missingLanguageName} — using ${result.actualLocale}');
        _safeSetState(
            (s) => s.copyWith(missingLanguage: result.missingLanguageName));
      } else {
        _addDebugLog('🎤 [$platform] STT using locale: ${result.actualLocale}');
      }
    }
  }

  Future<void> stopSession() async {
    if (_stopInFlight != null) {
      await _stopInFlight;
      return;
    }
    _sessionToken++;
    _sessionStopped = true;
    _startingSession = false;
    _heartbeatTimer?.cancel();
    _fluidAdvanceTimer?.cancel();
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;

    // Update UI synchronously before the async stop so re-entry never sees
    // a stale isListening=true if the user exits and returns quickly.
    if (!_disposed) {
      try {
        state = state.copyWith(
          isListening: false,
          isStarting: false,
          hasError: false,
          statusMessage: '',
        );
      } catch (_) {}
    }

    // Stop all engines — Whisper may have been auto-started via fallback
    final stopFuture = Future.wait([
      _sttService.stop(),
      _whisperService.stop(),
    ]);
    _stopInFlight = stopFuture.then((_) {});
    try {
      await _stopInFlight;
    } finally {
      _stopInFlight = null;
    }
  }

  void resetPosition() {
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _fluidAdvanceTimer?.cancel();
    _addDebugLog('🔄 POSITION RESET → 0');
    state = state.copyWith(confirmedWordIndex: 0);

    // Only adjust the STT locale when a session is actually running.
    // Calling setLocale() while _sessionStopped=true can race with a
    // concurrent stopSession() and re-trigger the recognizer.
    if (!_useWhisper && !_sessionStopped && _sectionLocales.isNotEmpty) {
      final startLocale = _sectionLocales.first;
      if (startLocale != _activeLocale) {
        _activeLocale = startLocale;
        _scriptLanguageLocale = startLocale;
        _addDebugLog('🔄 RESET LOCALE → $startLocale');
        _sttService.setLocale(startLocale);
      }
    }
  }

  Future<void> refreshAudioInputDevices() async {
    if (_disposed) return;
    final devices = await _sttService.refreshAudioInputDevices();
    if (_disposed) return;
    try {
      state = state.copyWith(audioInputDevices: devices);
    } catch (_) {
      _disposed = true;
    }
  }

  Future<void> setSttInputDevice(String deviceId, String label) async {
    final normalizedLabel =
        label.trim().isEmpty ? 'System default microphone' : label.trim();
    await _sttService.setAudioInputDevice(
      deviceId.trim().isEmpty ? null : deviceId.trim(),
      label: normalizedLabel,
    );
    await refreshAudioInputDevices();
    _addDebugLog(
      deviceId.trim().isEmpty
          ? '🎙️ [Apple] Using system default microphone'
          : '🎙️ [Apple] Requested microphone: $normalizedLabel',
    );
  }

  /// Presenter pushes the rendered visible word range here.
  void setVisibleWordWindow(int? startIndex, int? endIndex) {
    if (_disposed) return;
    _visibleWordStart = startIndex;
    _visibleWordEnd = endIndex;
  }

  /// Move the reading position without restarting STT.
  void jumpToPosition(int index, {Script? script}) {
    if (_disposed) return;
    if (script != null) _currentScript = script;
    final activeScript = _currentScript;
    if (activeScript == null || activeScript.words.isEmpty) return;
    final target = index.clamp(0, activeScript.words.length - 1);
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _addDebugLog(
        '📍 POSITION JUMP → #$target "${activeScript.words[target].raw}"');
    try {
      state = state.copyWith(confirmedWordIndex: target);
    } catch (_) {
      _disposed = true;
      return;
    }
    if (!_sessionStopped && state.isListening) {
      _syncLocaleForPosition(target, reason: 'manual jump');
    }
  }

  /// Resync STT locale to the section that contains [index].
  void _syncLocaleForPosition(int index, {String reason = ''}) {
    if (_useWhisper || _disposed || _sessionStopped) return;
    if (_sectionLocales.isEmpty) return;
    final needed = SttLocaleSectionService.localeForIndex(
      _sectionLocales,
      index,
    );
    if (needed == _activeLocale) return;
    _addDebugLog(
        '🌐 POSITION-SYNC: ${_activeLocale ?? "?"} → $needed (${reason.isEmpty ? "jump" : reason})');
    _activeLocale = needed;
    _scriptLanguageLocale = needed;
    _sttService.setLocale(needed);
  }
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(
        TeleprompterNotifier.new);
