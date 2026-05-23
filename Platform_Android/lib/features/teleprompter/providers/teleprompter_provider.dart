import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/debug_log_formatter.dart';
import '../services/speech_service.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../script/models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/stt/stt_service_factory.dart';

part 'teleprompter_provider.visible_skip.dart';

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
  DateTime? _lastVisibleLocaleAssistAt;
  String? _lastVisibleLocaleAssistLocale;
  DateTime? _visibleLocaleAssistPinnedUntil;
  String? _visibleLocaleAssistPinnedLocale;
  String? _pendingVisibleLocaleAssistLocale;

  // Tuning: how patient we are before force-skipping.
  static const int _googleSkipAfterStuck = 45;
  static const int _maxAdvancePerUpdate = 30;
  static const int _visibleLocaleAssistAfterWaits = 1;
  static const Duration _visibleLocaleAssistCooldown =
      Duration(milliseconds: 900);
  static const Duration _visibleLocaleAssistPinDuration =
      Duration(milliseconds: 3000);

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
    final entry = "[$ts] ${DebugLogFormatter.normalize(log)}";
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
        _addDebugLog('[VOICE] COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') || words.contains('בוא')) {
        _addDebugLog('[VOICE] COMMAND: START');
        if (settings.scrollSpeed == 0)
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        return;
      } else if (words.contains('speed up') || words.contains('מהר')) {
        _addDebugLog('[VOICE] COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') || words.contains('לאט')) {
        _addDebugLog('[VOICE] COMMAND: SLOWER');
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

    const engineTag = '[STT]';
    final skipThreshold = _effectiveSkipThreshold();
    if (aligned.confirmedWordIndex > state.confirmedWordIndex) {
      _noProgressCount = 0;
      _resetVisibleLocaleAssist();
      final visibleSkipTargetTrusted = maxSkipTargetIndex != null &&
          aligned.confirmedWordIndex <= maxSkipTargetIndex;
      final target = resolveAdvanceTarget(
        currentIndex: state.confirmedWordIndex,
        alignedIndex: aligned.confirmedWordIndex,
        visibleMaxSkipTargetIndex: maxSkipTargetIndex,
      );
      final advancedWord =
          target < script.words.length ? script.words[target].raw : '?';
      _addDebugLog(
          '$engineTag ADVANCE -> #$target "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "${result.words}"');

      // Fluid advancement: if jumping more than 3 words, animate
      // through intermediate words so the user's eye can follow.
      final jump = target - state.confirmedWordIndex;
      if (visibleSkipTargetTrusted || jump <= 3) {
        // Small jumps and trusted visible-skip targets are instant.
        _fluidAdvanceTimer?.cancel();
        _safeSetState((s) => s.copyWith(confirmedWordIndex: target));
      } else {
        // Large jump - advance word by word with short delays.
        _startFluidAdvance(target, script);
      }
      _syncLocaleForPosition(script, target + 1, reason: 'advance');
    } else {
      _noProgressCount++;
      _addDebugLog(
          '$engineTag WAIT #$_noProgressCount/$skipThreshold | heard: "${result.words}" | next: "$nextExpected"');
      _checkAndSwitchLocale();

      if (_maybeAssistVisibleLocale(script, settings, result.words)) {
        return;
      }

      if (_noProgressCount >= skipThreshold) {
        _noProgressCount = 0;
        final next = _nextRealWord(state.confirmedWordIndex, script);
        if (next != null) {
          final skippedWord = script.words[next].raw;
          _addDebugLog(
              '[STT] FORCE SKIP -> #$next "$skippedWord" (stuck too long)');
          _resetVisibleLocaleAssist();
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
          '[STT] Selected microphone was not found; using system default input.');
    };

    _sttService.onStatusChange = (status) {
      if (_disposed || _sessionStopped) return;
      // Ignore non-listening statuses during the start-up guard window.
      // This prevents stale async 'notListening' from the previous stop()
      // from resetting isListening=false right after the new session starts.
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('[STT] [${_sttService.platformName}] STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _sttService.onError = (error) {
      if (_disposed || _sessionStopped) return;
      _addDebugLog('[STT] [${_sttService.platformName}] ERROR: $error');
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
      _addDebugLog('[STT] [$platform] LANGUAGE UNAVAILABLE: $langName');
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
          '[STT] [$platform] ALL STT FAILED for $langName - internet required');
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

  static int resolveAdvanceTarget({
    required int currentIndex,
    required int alignedIndex,
    required int? visibleMaxSkipTargetIndex,
  }) {
    if (visibleMaxSkipTargetIndex != null &&
        alignedIndex <= visibleMaxSkipTargetIndex) {
      return alignedIndex;
    }
    return alignedIndex
        .clamp(currentIndex, currentIndex + _maxAdvancePerUpdate)
        .toInt();
  }

  static bool visibleTranscriptPlausiblyMatchesLocale({
    required List<ScriptWord> words,
    required List<String> sectionLocales,
    required String locale,
    required String transcript,
    required int visibleStart,
    required int visibleEnd,
    required int currentIndex,
  }) {
    if (words.isEmpty || sectionLocales.length != words.length) return false;
    final start = visibleStart.clamp(0, words.length - 1).toInt();
    final end = visibleEnd.clamp(start, words.length - 1).toInt();
    final minIndex = (currentIndex + 1).clamp(0, end).toInt();
    final scanStart = start < minIndex ? minIndex : start;
    if (scanStart > end) return false;

    final visible = <String>[];
    for (var i = scanStart; i <= end; i++) {
      final word = words[i];
      if (word.isNewline || word.normalized.isEmpty) continue;
      if (sectionLocales[i] != locale) continue;
      visible.add(word.normalized.normalizeForMatching());
    }
    if (visible.isEmpty) return false;

    final spoken = transcript
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().normalizeForMatching())
        .where((w) => w.isNotEmpty)
        .toList();
    if (spoken.isEmpty) return false;

    var usefulMatches = 0;
    for (final spokenWord in spoken) {
      if (_visibleAssistStopWords.contains(spokenWord)) continue;
      var best = 0.0;
      for (final visibleWord in visible) {
        final sim = spokenWord.similarity(visibleWord);
        if (sim > best) best = sim;
      }
      if (best >= 0.92 && spokenWord.length >= 4) {
        usefulMatches++;
      }
      if (best >= 0.96 && spokenWord.length >= 6) {
        return true;
      }
    }
    return usefulMatches >= 2;
  }

  static bool shouldBlockLocaleSyncDuringAssistPin({
    required String? pinnedLocale,
    required String? activeLocale,
    required String? scriptLocale,
    required DateTime? pinnedUntil,
    required DateTime now,
  }) {
    if (pinnedLocale == null || pinnedUntil == null) return false;
    if (!now.isBefore(pinnedUntil)) return false;
    return pinnedLocale == activeLocale || pinnedLocale == scriptLocale;
  }

  static const Set<String> _visibleAssistStopWords = {
    'a',
    'an',
    'and',
    'at',
    'for',
    'in',
    'is',
    'of',
    'or',
    'the',
    'to',
    'we',
    'you',
  };

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

  Future<void> startSession(Script script) async {
    final pendingStop = _stopInFlight;
    if (pendingStop != null) await pendingStop;
    if (_disposed) return;

    final token = ++_sessionToken;
    // Compare by sessionId rather than object identity. _startPresenting()
    // always rebuilds the Script object, so identical() always returns false
    // - causing the resume position to reset to 0 on every re-entry. Using
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
    _resetVisibleLocaleAssist();
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
        '[STT] SESSION START | ${script.words.where((w) => !w.isNewline).length} words | pos=$startIndex');
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
            '[STT] HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');

        // Silent-listening detector: STT says listening but no audio level or results received.
        if (listening &&
            !_silentWarningFired &&
            _lastVolLog == null &&
            _sessionStartTime != null) {
          final elapsed = DateTime.now().difference(_sessionStartTime!);
          if (elapsed.inSeconds >= 10) {
            _silentWarningFired = true;
            _addDebugLog(
                '[STT] SILENT LISTENING: engine is active but receiving NO audio for ${elapsed.inSeconds}s.');
            _addDebugLog(
                '[STT] FIX: Ensure "Online Speech Recognition" is ON in Privacy Settings or install the Hebrew Offline Pack.');
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
      _addDebugLog('[STT] [$platform] Starting STT locale=$localeId...');
      _addDebugLog(selectedMicId.isEmpty
          ? '[STT] [$platform] Microphone: system default input'
          : '[STT] [$platform] Microphone: $selectedMicLabel');
      final result = await _sttService.start(localeId: localeId);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _sttService.stop();
        return;
      }

      if (!result.success) {
        _addDebugLog('[STT] [$platform] FAILED: ${result.message}');
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
            '[STT] [$platform] LANG MISSING: ${result.missingLanguageName} - using ${result.actualLocale}');
        _safeSetState(
            (s) => s.copyWith(missingLanguage: result.missingLanguageName));
      } else {
        _addDebugLog(
            '[STT] [$platform] STT using locale: ${result.actualLocale}');
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
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _resetVisibleLocaleAssist();

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
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog('[STT] POSITION RESET -> 0');
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
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog(
        '[STT] POSITION JUMP -> #$target "${activeScript.words[target].raw}"');
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
        ? '[STT] Microphone input set to system default'
        : '[STT] Microphone input set to $normalizedLabel');
  }

  void setVisibleWordWindow(int? startIndex, int? endIndex) {
    if (_disposed) return;
    if (startIndex != _visibleWordStart || endIndex != _visibleWordEnd) {
      _resetVisibleLocaleAssist();
    }
    _visibleWordStart = startIndex;
    _visibleWordEnd = endIndex;
  }
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(
        TeleprompterNotifier.new);
