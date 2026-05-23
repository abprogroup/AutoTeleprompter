import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/debug_log_formatter.dart';
import '../services/speech_service.dart';
import '../services/whisper_speech_service_native.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../script/models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/stt/stt_service_factory.dart';

part 'teleprompter_provider.session_parts.dart';

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
  String? _activeLocale;
  List<String> _sectionLocales = [];
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

  // â”€â”€ Tuning: how patient we are before force-skipping â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const int _googleSkipAfterStuck = 45;
  static const int _whisperSkipAfterStuck = 10;
  static const int _strictBulletWaitLogThreshold = 9999;
  static const int _maxAdvancePerUpdate = 30;
  static const int _visibleLocaleAssistAfterWaits = 2;
  static const Duration _visibleLocaleAssistCooldown =
      Duration(milliseconds: 900);
  static const Duration _visibleLocaleAssistPinDuration =
      Duration(milliseconds: 5000);

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

  /// Common handler for STT results â€” shared between Google and Whisper
  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));

    final words = result.words.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);

      // Voice Commands
      if (words.contains('stop prompt') ||
          words.contains('×¢×¦×•×¨') ||
          words.contains('×¢×¦×™×¨×”')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') || words.contains('×‘×•×')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return;
      } else if (words.contains('speed up') || words.contains('×ž×”×¨')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') || words.contains('×œ××˜')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: SLOWER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }
    } catch (_) {}

    _accumulatedTranscript = result.words;
    final script = _currentScript!;
    final settings = ref.read(settingsProvider);
    final strictBulletMode = settings.sttStrictBulletMode;
    final maxSkipTargetIndex = resolveVisibleSkipTarget(
      visibleSkipEnabled: settings.sttVisibleSkipEnabled,
      strictBulletMode: strictBulletMode,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );

    final aligned = WordAligner.align(
      script: script.words,
      transcript: _accumulatedTranscript,
      lastConfirmedIndex: state.confirmedWordIndex,
      visibleSkipStartIndex:
          maxSkipTargetIndex == null ? null : _visibleWordStart,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: strictBulletMode,
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

    final engineTag = _useWhisper ? 'ðŸ¤–' : 'ðŸŽ¤';
    final forceSkipEnabled = !strictBulletMode;
    final skipThreshold = forceSkipEnabled
        ? (_useWhisper ? _whisperSkipAfterStuck : _effectiveSkipThreshold())
        : _strictBulletWaitLogThreshold;
    if (aligned.confirmedWordIndex > state.confirmedWordIndex) {
      _noProgressCount = 0;
      _resetVisibleLocaleAssist();
      final visibleSkipTargetTrusted = isTrustedVisibleSkipTarget(
        alignedIndex: aligned.confirmedWordIndex,
        visibleWordStart: _visibleWordStart,
        visibleWordEnd: _visibleWordEnd,
      );
      final target = resolveAdvanceTarget(
        currentIndex: state.confirmedWordIndex,
        alignedIndex: aligned.confirmedWordIndex,
        visibleMaxSkipTargetIndex:
            visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
      );
      final advancedWord =
          target < script.words.length ? script.words[target].raw : '?';
      _addDebugLog(
          '$engineTag âœ… ADVANCE â†’ #$target "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "${result.words}"');

      // Fluid advancement: if jumping more than 3 words, animate
      // through intermediate words so the user's eye can follow.
      final jump = target - state.confirmedWordIndex;
      if (visibleSkipTargetTrusted || jump <= 3) {
        // Small jumps and trusted visible-skip targets are instant.
        _fluidAdvanceTimer?.cancel();
        _safeSetState((s) => s.copyWith(confirmedWordIndex: target));
      } else {
        // Large jump â€” advance word by word with short delays
        _startFluidAdvance(target, script);
      }
      _syncLocaleForPosition(script, target + 1, reason: 'advance');
    } else {
      final improvising = shouldUseImprovisationNoMatch(
        strictBulletMode: strictBulletMode,
        alignedIndex: aligned.confirmedWordIndex,
        currentIndex: state.confirmedWordIndex,
      );
      _noProgressCount++;
      if (improvising) {
        _addDebugLog(
            '$engineTag IMPROVISING | heard: "${result.words}" | visible relock waiting');
      } else {
        _addDebugLog(
            '$engineTag â¸ WAIT #$_noProgressCount/$skipThreshold | heard: "${result.words}" | next: "$nextExpected"');
        _checkAndSwitchLocale();
      }

      if (_maybeAssistVisibleLocale(script, settings, result.words)) {
        return;
      }

      if (shouldForceSkipAfterNoProgress(
        strictBulletMode: strictBulletMode,
        noProgressCount: _noProgressCount,
        skipThreshold: skipThreshold,
      )) {
        _noProgressCount = 0;
        final next = _nextRealWord(state.confirmedWordIndex, script);
        if (next != null) {
          final skippedWord = script.words[next].raw;
          _addDebugLog(
              'ðŸ¤– â­ FORCE SKIP â†’ #$next "$skippedWord" (stuck too long)');
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
      _lastVolLog = DateTime.now();
      _handleSttResult(result);
    };

    _sttService.onSoundLevelChange = (level) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Push live level to UI state.
      _safeSetState(
        (s) => s.copyWith(soundLevel: _normalizeSoundLevel(level)),
      );
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
          'ðŸŽ™ï¸ Selected microphone was not found; using system default input.');
    };

    _sttService.onStatusChange = (status) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Ignore non-listening statuses during the start-up guard window.
      // This prevents stale async 'notListening' from the previous stop()
      // from resetting isListening=false right after the new session starts.
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('ðŸŽ¤ [${_sttService.platformName}] STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _sttService.onError = (error) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('ðŸŽ¤ [${_sttService.platformName}] STT ERROR: $error');
      if (error.contains('error_language')) return;
      final isFatal = error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available') ||
          error.contains('error_unknown');
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
      _addDebugLog('ðŸŽ¤ [$platform] LANGUAGE UNAVAILABLE: $langName');
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
          'ðŸŽ¤ [$platform] ALL STT FAILED for $langName â€” internet required');
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

  static bool shouldForceSkipAfterNoProgress({
    required bool strictBulletMode,
    required int noProgressCount,
    required int skipThreshold,
  }) {
    if (strictBulletMode) return false;
    if (skipThreshold <= 0) return false;
    return noProgressCount >= skipThreshold;
  }

  static bool shouldUseImprovisationNoMatch({
    required bool strictBulletMode,
    required int alignedIndex,
    required int currentIndex,
  }) {
    return strictBulletMode && alignedIndex <= currentIndex;
  }

  static int? resolveVisibleSkipTarget({
    required bool visibleSkipEnabled,
    required bool strictBulletMode,
    required int? visibleWordStart,
    required int? visibleWordEnd,
  }) {
    if (!(visibleSkipEnabled || strictBulletMode)) return null;
    if (visibleWordStart == null) return null;
    return visibleWordEnd;
  }

  static bool isTrustedVisibleSkipTarget({
    required int alignedIndex,
    required int? visibleWordStart,
    required int? visibleWordEnd,
  }) {
    if (visibleWordStart == null || visibleWordEnd == null) return false;
    final start =
        visibleWordStart <= visibleWordEnd ? visibleWordStart : visibleWordEnd;
    final end =
        visibleWordStart <= visibleWordEnd ? visibleWordEnd : visibleWordStart;
    return alignedIndex >= start && alignedIndex <= end;
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

  /// Current v4 metadata safely resolves Hebrew/RTL and English/LTR only.
  /// Universal same-script language support belongs to the v5 language MVP.
  static String? _strongLocaleForWord(ScriptWord word) {
    if (word.isNewline) return null;
    final visible = word.raw.replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), '');
    if (RegExp(r'[\u0590-\u05FF]').hasMatch(visible)) return 'he_IL';
    if (RegExp(r'[A-Za-z]').hasMatch(visible)) return 'en_US';
    return null;
  }

  static String _fallbackLocaleForWords(List<ScriptWord> words) {
    var hebrew = 0;
    var english = 0;
    for (final word in words) {
      final locale = _strongLocaleForWord(word);
      if (locale == 'he_IL') hebrew++;
      if (locale == 'en_US') english++;
    }
    return hebrew > english ? 'he_IL' : 'en_US';
  }

  static List<String> resolveSttSectionLocalesForWords(
    List<ScriptWord> words,
  ) {
    const minSectionWords = 3;
    if (words.isEmpty) return [];

    final fallback = _fallbackLocaleForWords(words);
    final realWords =
        words.where((w) => !w.isNewline && w.normalized.isNotEmpty).toList();
    if (realWords.isEmpty) return [];

    final raw = realWords.map(_strongLocaleForWord).toList();
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] != null) continue;

      String? previous;
      for (var p = i - 1; p >= 0; p--) {
        if (raw[p] != null) {
          previous = raw[p];
          break;
        }
      }

      String? next;
      for (var n = i + 1; n < raw.length; n++) {
        if (raw[n] != null) {
          next = raw[n];
          break;
        }
      }

      raw[i] = previous ?? next ?? fallback;
    }

    final smoothed = raw.map((locale) => locale ?? fallback).toList();
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

    final resolved = <String>[];
    var realIndex = 0;
    for (final word in words) {
      if (word.isNewline || word.normalized.isEmpty) {
        resolved.add(resolved.isNotEmpty ? resolved.last : fallback);
      } else {
        resolved.add(
          realIndex < smoothed.length ? smoothed[realIndex] : fallback,
        );
        realIndex++;
      }
    }
    return resolved;
  }

  static double _normalizeSoundLevel(double level) {
    if (level >= 0.0 && level <= 1.0) return level;
    if (level > 1.0) return (level / 10.0).clamp(0.0, 1.0).toDouble();
    return ((level + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
  }
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(
        TeleprompterNotifier.new);
