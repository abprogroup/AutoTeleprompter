import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/speech_service.dart';
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
  DateTime? _lastVolLog;
  DateTime? _sessionStartTime;
  bool _silentWarningFired = false;
  Future<void>? _stopInFlight;
  int _sessionToken = 0;
  int? _visibleWordStart;
  int? _visibleWordEnd;

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
    ref.onDispose(() {
      _disposed = true;
      _heartbeatTimer?.cancel();
      _sttService.stop();
      _whisperService.stop();
      _remoteControlService.stop();
    });
    return const TeleprompterState();
  }

  // v4.0: Remote control features hidden for stable release
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
    final entry = "[$ts] $log";
    final logs = [...state.debugLogs, entry];
    if (logs.length > 80) logs.removeRange(0, logs.length - 80);
    _safeSetState((s) => s.copyWith(debugLogs: logs));
  }

  /// Common handler for STT results — shared between Google and Whisper
  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));

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
        if (settings.scrollSpeed == 0)
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
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
    final maxSkipTargetIndex =
        settings.sttVisibleSkipEnabled && _visibleWordStart != null
            ? _visibleWordEnd
            : null;

    final aligned = WordAligner.align(
      script: script.words,
      transcript: _accumulatedTranscript,
      lastConfirmedIndex: state.confirmedWordIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
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
    final skipThreshold =
        _useWhisper ? _whisperSkipAfterStuck : _googleSkipAfterStuck;
    if (aligned.confirmedWordIndex > state.confirmedWordIndex) {
      _noProgressCount = 0;
      final capped = aligned.confirmedWordIndex.clamp(
        state.confirmedWordIndex,
        state.confirmedWordIndex + _maxAdvancePerUpdate,
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
      _syncLocaleForPosition(script, capped + 1, reason: 'advance');
    } else {
      _noProgressCount++;
      _addDebugLog(
          '$engineTag ⏸ WAIT #$_noProgressCount/$skipThreshold | heard: "${result.words}" | next: "$nextExpected"');
      _syncLocaleForPosition(script, state.confirmedWordIndex + 1,
          reason: 'boundary wait');

      if (_noProgressCount >= skipThreshold) {
        _noProgressCount = 0;
        final next = _nextRealWord(state.confirmedWordIndex, script);
        if (next != null) {
          final skippedWord = script.words[next].raw;
          _addDebugLog(
              '🤖 ⏭ FORCE SKIP → #$next "$skippedWord" (stuck too long)');
          _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
          _syncLocaleForPosition(script, next + 1, reason: 'force skip');
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

    _sttService.onSoundLevelChange = (level) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Push live level to UI state.
      _safeSetState((s) => s.copyWith(soundLevel: level.clamp(0.0, 1.0)));
      _lastVolLog = DateTime.now();
    };

    _sttService.onDiagnostic = (msg) {
      if (_disposed) return;
      _addDebugLog(msg);
    };

    _sttService.onAudioInputDevicesChanged = (devices) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _safeSetState((s) => s.copyWith(audioInputDevices: devices));

      final selectedId = ref.read(settingsProvider).sttInputDeviceId;
      if (selectedId.isEmpty) return;
      for (final device in devices) {
        if (device.id == selectedId) {
          final currentLabel = ref.read(settingsProvider).sttInputDeviceLabel;
          if (device.label.isNotEmpty && device.label != currentLabel) {
            ref
                .read(settingsProvider.notifier)
                .setSttInputDevice(device.id, device.label);
          }
          return;
        }
      }
      _addDebugLog(
          '🎙️ Selected microphone was not found; using system default input.');
    };

    _sttService.onStatusChange = (status) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Ignore non-listening statuses during the start-up guard window.
      // This prevents stale async 'notListening' from the previous stop()
      // from resetting isListening=false right after the new session starts.
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('🎤 [${_sttService.platformName}] STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _sttService.onError = (error) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('🎤 [${_sttService.platformName}] STT ERROR: $error');
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
          isStarting: false,
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

  /// Detect the language of the next real expected word starting at [wordIndex].
  /// Broad lookahead can pivot too early in bilingual scripts; the recognizer
  /// should switch only when the next speakable word actually changes language.
  String _detectLanguageAhead(int wordIndex, Script script) {
    final words = script.words;
    final start = wordIndex.clamp(0, words.length);
    for (int i = start; i < words.length; i++) {
      if (words[i].isNewline || words[i].normalized.isEmpty) continue;
      return words[i].isRtl ? 'he_IL' : 'en_US';
    }
    return _scriptLanguageLocale ?? 'en_US';
  }

  void _syncLocaleForPosition(Script script, int wordIndex,
      {required String reason}) {
    if (_useWhisper || _sessionStopped || _disposed) return;
    final upcomingLocale = _detectLanguageAhead(wordIndex, script);
    if (upcomingLocale == _scriptLanguageLocale) return;
    _scriptLanguageLocale = upcomingLocale;
    _accumulatedTranscript = '';
    final engineName = _sttService.platformName.toUpperCase();
    _addDebugLog(
        '🔤 [$engineName] Switching STT locale → $upcomingLocale ($reason)');
    _safeSetState((s) => s.copyWith(isStarting: true, soundLevel: 0.0));
    _sttService.setLocale(upcomingLocale);
  }

  /// Find the next non-newline word index after [from]
  int? _nextRealWord(int from, Script script) {
    for (int i = from + 1; i < script.words.length; i++) {
      if (!script.words[i].isNewline && script.words[i].normalized.isNotEmpty) {
        return i;
      }
    }
    return null;
  }

  Future<void> startSession(Script script) async {
    final pendingStop = _stopInFlight;
    if (pendingStop != null) await pendingStop;
    if (_disposed) return;

    final token = ++_sessionToken;
    final sameScript = identical(_currentScript, script);
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sessionStopped = false;
    _sessionStartTime = DateTime.now();
    _silentWarningFired = false;
    _lastVolLog = null;
    _visibleWordStart = null;
    _visibleWordEnd = null;
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
        '🚀 SESSION START | ${script.words.where((w) => !w.isNewline).length} words | pos=$startIndex');
    String? localeId;

    // v4.2: Detect starting locale focusing ONLY on the immediate first words.
    // This prevents a long Hebrew document from forcing English start-text into Hebrew STT.
    if (script.words.isNotEmpty) {
      final initialLocale = _detectLanguageAhead(startIndex, script);
      _scriptLanguageLocale = initialLocale;

      final realWords = script.words.where((w) => !w.isNewline).toList();
      final hebrewCount = realWords.where((w) => w.isRtl).length;
      final ratio = hebrewCount / realWords.length;
      _addDebugLog(
          '🌐 LANG: ${initialLocale == "he_IL" ? "Hebrew" : "English"} start (${(ratio * 100).round()}% Hebrew overall)');
      localeId = initialLocale;
    }

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

        // Silent-listening detector: STT says listening but no audio level or results received.
        if (!_useWhisper &&
            listening &&
            !_silentWarningFired &&
            _lastVolLog == null &&
            _sessionStartTime != null) {
          final elapsed = DateTime.now().difference(_sessionStartTime!);
          if (elapsed.inSeconds >= 10) {
            _silentWarningFired = true;
            _addDebugLog(
                '🚨 SILENT LISTENING: engine is active but receiving NO audio for ${elapsed.inSeconds}s.');
            _addDebugLog(
                '👉 FIX: Ensure "Online Speech Recognition" is ON in Privacy Settings or install the Hebrew Offline Pack.');
            _safeSetState((s) => s.copyWith(
                  statusMessage:
                      'Microphone signal weak or blocked.\n1. Check Privacy Settings -> Microphone.\n2. Ensure "Online Speech Recognition" is enabled.',
                  hasError: true,
                ));
          }
        }

        // Dynamic language switching for mixed Hebrew/English scripts.
        // Every heartbeat, check the next expected word. If its language
        // changed, hot-switch the STT locale via WebSocket.
        if (!_useWhisper && listening && _currentScript != null) {
          _syncLocaleForPosition(_currentScript!, state.confirmedWordIndex + 1,
              reason: 'heartbeat');
        }
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
      _sttService.setAudioInputDevice(
        selectedMicId.isEmpty ? null : selectedMicId,
        label: selectedMicLabel.isEmpty
            ? 'System default microphone'
            : selectedMicLabel,
      );
      _addDebugLog('🎤 [$platform] Starting STT locale=$localeId...');
      _addDebugLog(selectedMicId.isEmpty
          ? '🎙️ [$platform] Microphone: system default input'
          : '🎙️ [$platform] Microphone: $selectedMicLabel');
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
              isStarting: false,
            ));
        return;
      }

      // Apple platforms (iOS/macOS) fire onStatusChange asynchronously,
      // so we set isListening=true immediately here to avoid the mic button
      // staying yellow while waiting for the callback.
      if (_sttService.requiresImmediateListeningFlag) {
        _startingSession = true;
        _safeSetState((s) => s.copyWith(isListening: true, isStarting: false));
        // Auto-clear the guard after 1.5 s in case listening status never fires
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (token == _sessionToken) _startingSession = false;
        });
      }

      // Expose WebView URL for the embedded browser STT (Windows only).
      final webViewUrl = _sttService.sttWebViewUrl;
      if (webViewUrl != null) {
        _safeSetState((s) => s.copyWith(sttWebViewUrl: webViewUrl));
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
    _lastVolLog = null;
    _scriptLanguageLocale = null;

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

    if (!_disposed) {
      try {
        state = state.copyWith(
          isListening: false,
          isStarting: false,
          hasError: false,
          statusMessage: '',
          soundLevel: 0.0,
          sttWebViewUrl: null,
        );
      } catch (_) {}
    }
  }

  void resetPosition() {
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _fluidAdvanceTimer?.cancel();
    _addDebugLog('🔄 POSITION RESET → 0');
    state = state.copyWith(confirmedWordIndex: 0);
    if (!_sessionStopped && _currentScript != null && state.isListening) {
      _syncLocaleForPosition(_currentScript!, 0, reason: 'reset');
    }
  }

  void jumpToPosition(int index, {Script? script}) {
    if (script != null) _currentScript = script;
    final activeScript = _currentScript;
    if (_disposed || activeScript == null || activeScript.words.isEmpty) return;
    final target = index.clamp(0, activeScript.words.length - 1);
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _fluidAdvanceTimer?.cancel();
    _addDebugLog(
        '📍 POSITION JUMP → #$target "${activeScript.words[target].raw}"');
    try {
      state = state.copyWith(confirmedWordIndex: target);
    } catch (_) {
      _disposed = true;
      return;
    }
    if (!_sessionStopped && state.isListening) {
      _syncLocaleForPosition(activeScript, target, reason: 'manual jump');
    }
  }

  void setSttInputDevice(String deviceId, String label) {
    final normalizedId = deviceId.trim();
    final normalizedLabel =
        label.trim().isEmpty ? 'System default microphone' : label.trim();
    _sttService.setAudioInputDevice(
      normalizedId.isEmpty ? null : normalizedId,
      label: normalizedLabel,
    );
    _addDebugLog(normalizedId.isEmpty
        ? '🎙️ Microphone input set to system default'
        : '🎙️ Microphone input set to $normalizedLabel');
  }

  void setVisibleWordWindow(int? startIndex, int? endIndex) {
    if (_disposed) return;
    _visibleWordStart = startIndex;
    _visibleWordEnd = endIndex;
  }
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(
        TeleprompterNotifier.new);
