import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/speech_service.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../settings/providers/settings_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/stt/stt_service_factory.dart';

class TeleprompterNotifier extends Notifier<TeleprompterState> {
  late final AbstractSttService _sttService;
  late final RemoteControlService _remoteControlService;
  Script? _currentScript;
  String _accumulatedTranscript = '';
  bool _disposed = false;
  int _noProgressCount = 0;
  Timer? _heartbeatTimer;
  Timer? _fluidAdvanceTimer;
  int _fluidTarget = 0;
  String? _scriptLanguageLocale;
  String? _activeLocale;
  List<String> _sectionLocales = const [];
  DateTime? _lastVolLog;
  DateTime? _sessionStartTime;
  bool _silentWarningFired = false;
  Future<void>? _stopInFlight;
  int _sessionToken = 0;
  int? _visibleWordStart;
  int? _visibleWordEnd;

  // ── Tuning: how patient we are before force-skipping ───────────────────────
  static const int _googleSkipAfterStuck = 45;
  static const int _maxAdvancePerUpdate = 30;

  @override
  TeleprompterState build() {
    _disposed = false;
    _sttService = SttServiceFactory.create();
    _remoteControlService = ref.read(remoteControlProvider);
    _setupRemoteCallbacks();
    _setupSttCallbacks();
    ref.onDispose(() {
      _disposed = true;
      _heartbeatTimer?.cancel();
      _sttService.stop();
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

  /// Common handler for Android STT results.
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

    const engineTag = '🎤';
    final skipThreshold = _effectiveSkipThreshold();
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

      if (_noProgressCount >= skipThreshold) {
        _noProgressCount = 0;
        final next = _nextRealWord(state.confirmedWordIndex, script);
        if (next != null) {
          final skippedWord = script.words[next].raw;
          _addDebugLog(
              '🤖 ⏭ FORCE SKIP → #$next "$skippedWord" (stuck too long)');
          _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
          _checkAndSwitchLocale();
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
      if (_disposed || _sessionStopped) return;
      // Push live level to UI state.
      _safeSetState((s) => s.copyWith(soundLevel: level.clamp(0.0, 1.0)));
      _lastVolLog = DateTime.now();
    };

    _sttService.onDiagnostic = (msg) {
      if (_disposed) return;
      _addDebugLog(msg);
    };

    _sttService.onAudioInputDevicesChanged = (devices) {
      if (_disposed || _sessionStopped) return;
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
      if (_disposed || _sessionStopped) return;
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
      if (_disposed || _sessionStopped) return;
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
      if (_disposed || _sessionStopped) return;
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
      if (_disposed || _sessionStopped) return;
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

  /// Pre-compute a per-word locale map so mixed Hebrew/English scripts can
  /// switch languages before the boundary, matching the tested iOS behavior.
  void _precomputeSectionLocales(Script script) {
    const minSectionWords = 3;

    final realWords = script.words
        .where((w) => !w.isNewline && w.normalized.isNotEmpty)
        .toList();
    if (realWords.isEmpty) {
      _sectionLocales = const [];
      return;
    }

    final raw = realWords.map((w) => w.isRtl ? 'he_IL' : 'en_US').toList();
    final smoothed = List<String>.from(raw);
    var changed = true;
    while (changed) {
      changed = false;
      var i = 0;
      while (i < smoothed.length) {
        final locale = smoothed[i];
        final runStart = i;
        while (i < smoothed.length && smoothed[i] == locale) {
          i++;
        }
        final runLen = i - runStart;
        if (runLen < minSectionWords) {
          final inherit = runStart > 0
              ? smoothed[runStart - 1]
              : (i < smoothed.length ? smoothed[i] : locale);
          if (inherit != locale) {
            for (var j = runStart; j < i; j++) {
              smoothed[j] = inherit;
            }
            changed = true;
          }
        }
      }
    }

    final mapped = <String>[];
    var realIndex = 0;
    for (final word in script.words) {
      if (word.isNewline || word.normalized.isEmpty) {
        mapped.add(mapped.isNotEmpty ? mapped.last : smoothed.first);
      } else {
        mapped.add(realIndex < smoothed.length ? smoothed[realIndex] : 'en_US');
        realIndex++;
      }
    }
    _sectionLocales = mapped;
  }

  int _effectiveSkipThreshold() {
    if (_sectionLocales.isEmpty) return _googleSkipAfterStuck;
    final currentIdx = state.confirmedWordIndex;
    for (var lookahead = 1; lookahead <= 2; lookahead++) {
      final checkIdx = currentIdx + lookahead;
      if (checkIdx < _sectionLocales.length &&
          _sectionLocales[checkIdx] != _activeLocale) {
        return 5;
      }
    }
    return _googleSkipAfterStuck;
  }

  void _checkAndSwitchLocale() {
    if (_disposed || _sessionStopped || _sectionLocales.isEmpty) return;
    final currentIdx = state.confirmedWordIndex;
    if (currentIdx < 0 || currentIdx >= _sectionLocales.length) return;
    final lookIdx =
        (currentIdx + 1).clamp(0, _sectionLocales.length - 1).toInt();
    final needed = _sectionLocales[lookIdx];
    if (needed == _activeLocale) return;
    _activeLocale = needed;
    _scriptLanguageLocale = needed;
    _accumulatedTranscript = '';
    _addDebugLog('LANG PRE-SWITCH: $needed (cur=$currentIdx)');
    _safeSetState((s) => s.copyWith(isStarting: true, soundLevel: 0.0));
    _sttService.setLocale(needed);
  }

  void _syncLocaleForPosition(Script script, int wordIndex,
      {required String reason}) {
    if (_sessionStopped || _disposed) return;
    if (_sectionLocales.length != script.words.length) {
      _precomputeSectionLocales(script);
    }
    if (_sectionLocales.isEmpty) return;
    final lookIdx = wordIndex.clamp(0, _sectionLocales.length - 1).toInt();
    final needed = _sectionLocales[lookIdx];
    if (needed == _activeLocale) return;
    _activeLocale = needed;
    _scriptLanguageLocale = needed;
    _accumulatedTranscript = '';
    final engineName = _sttService.platformName.toUpperCase();
    _addDebugLog('LANG SYNC [$engineName]: $needed ($reason)');
    _safeSetState((s) => s.copyWith(isStarting: true, soundLevel: 0.0));
    _sttService.setLocale(needed);
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
    // Compare by sessionId rather than object identity. _startPresenting()
    // always rebuilds the Script object, so identical() always returns false
    // — causing the resume position to reset to 0 on every re-entry. Using
    // sessionId (stable across editor edits of the same session) lets us
    // distinguish "re-entered same session" from "loaded a different script".
    final sameScript = _currentScript != null &&
        _currentScript!.sessionId.isNotEmpty &&
        _currentScript!.sessionId == script.sessionId;
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sessionStopped = false;
    _sessionStartTime = DateTime.now();
    _silentWarningFired = false;
    _lastVolLog = null;
    _visibleWordStart = null;
    _visibleWordEnd = null;
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
    _precomputeSectionLocales(script);
    final localeId = startIndex < _sectionLocales.length
        ? _sectionLocales[startIndex]
        : (_sectionLocales.isNotEmpty ? _sectionLocales.first : 'en_US');
    _scriptLanguageLocale = localeId;
    _activeLocale = localeId;
    _addDebugLog(
        'START LOCALE: $localeId | ${_sectionLocales.toSet().length} section(s)');

    // Start heartbeat timer in debug mode
    _heartbeatTimer?.cancel();
    final settings = ref.read(settingsProvider);
    if (settings.debugMode) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_disposed) return;
        final engineName = _sttService.platformName.toUpperCase();
        final listening = _sttService.isListening;
        final pos = state.confirmedWordIndex;
        final total = script.words.where((w) => !w.isNewline).length;
        _addDebugLog(
            '💓 HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');

        // Silent-listening detector: STT says listening but no audio level or results received.
        if (listening &&
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
        if (listening && _currentScript != null) {
          _checkAndSwitchLocale();
        }
      });
    }

    {
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

      // Optional embedded browser STT URL. Apple-native macOS adapters return null.
      final browserUrl = _sttService.sttBrowserUrl;
      if (browserUrl != null) {
        _safeSetState((s) => s.copyWith(sttBrowserUrl: browserUrl));
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
    _activeLocale = null;
    _sectionLocales = const [];

    // Stop the Android-native speech recognizer.
    final stopFuture = _sttService.stop();
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
          sttBrowserUrl: null,
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
