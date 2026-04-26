import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/speech_service.dart';
import '../services/native_speech_service.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../settings/providers/settings_provider.dart';

import '../../remote/services/remote_control_service.dart';

class TeleprompterNotifier extends Notifier<TeleprompterState> {
  late final NativeSpeechService _nativeSttService;
  late final RemoteControlService _remoteControlService;
  Script? _currentScript;
  String _accumulatedTranscript = '';
  bool _disposed = false;
  int _noProgressCount = 0;
  Timer? _heartbeatTimer;
  Timer? _fluidAdvanceTimer;
  int _fluidTarget = 0;
  String? _scriptLanguageLocale;

  // ── Tuning: how patient we are before force-skipping ───────────────────────
  static const int _googleSkipAfterStuck = 45;
  static const int _maxAdvancePerUpdate = 30;

  @override
  TeleprompterState build() {
    _disposed = false;
    _nativeSttService = NativeSpeechService();
    _remoteControlService = ref.read(remoteControlProvider);
    _setupRemoteCallbacks();
    _setupNativeSttCallbacks();
    ref.onDispose(() {
      _disposed = true;
      _heartbeatTimer?.cancel();
      _nativeSttService.stop();
      _remoteControlService.stop();
    });
    return const TeleprompterState();
  }

  // v4.0: Remote control features hidden for stable release
  void _setupRemoteCallbacks() {}

  bool _sessionStopped = false;

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
    } catch (_) { return; }
    final now = DateTime.now();
    final ts = "${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}";
    final entry = "[$ts] $log";
    final logs = [...state.debugLogs, entry];
    if (logs.length > 80) logs.removeRange(0, logs.length - 80);
    _safeSetState((s) => s.copyWith(debugLogs: logs));
  }

  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;

    final words = result.words.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);

      // Voice Commands
      if (words.contains('stop prompt') || words.contains('עצור') || words.contains('עצירה')) {
        _addDebugLog('🗣️ VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') || words.contains('בוא')) {
        _addDebugLog('🗣️ VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) ref.read(settingsProvider.notifier).setScrollSpeed(100);
        return;
      } else if (words.contains('speed up') || words.contains('מהר')) {
        _addDebugLog('🗣️ VOICE COMMAND: FASTER');
        ref.read(settingsProvider.notifier).setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') || words.contains('לאט')) {
        _addDebugLog('🗣️ VOICE COMMAND: SLOWER');
        ref.read(settingsProvider.notifier).setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }
    } catch (_) {}

    _accumulatedTranscript = result.words;
    final script = _currentScript!;

    final aligned = WordAligner.align(
      script: script.words,
      transcript: _accumulatedTranscript,
      lastConfirmedIndex: state.confirmedWordIndex,
    );

    final currentIdx = state.confirmedWordIndex;
    final nextExpected = (currentIdx + 1 < script.words.length)
        ? script.words.skip(currentIdx + 1).where((w) => !w.isNewline).take(3).map((w) => w.raw).join(' ')
        : '<END>';

    const engineTag = '🎤';
    const skipThreshold = _googleSkipAfterStuck;

    if (aligned.confirmedWordIndex > state.confirmedWordIndex) {
      _noProgressCount = 0;
      final capped = aligned.confirmedWordIndex.clamp(
        state.confirmedWordIndex,
        state.confirmedWordIndex + _maxAdvancePerUpdate,
      );
      final advancedWord = capped < script.words.length ? script.words[capped].raw : '?';
      _addDebugLog('$engineTag ✅ ADVANCE → #$capped "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "${result.words}"');

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
    } else {
      _noProgressCount++;
      _addDebugLog('$engineTag ⏸ WAIT #$_noProgressCount/$skipThreshold | heard: "${result.words}" | next: "$nextExpected"');

      if (_noProgressCount >= skipThreshold) {
        _noProgressCount = 0;
        final next = _nextRealWord(state.confirmedWordIndex, script);
        if (next != null) {
          final skippedWord = script.words[next].raw;
          _addDebugLog('🤖 ⏭ FORCE SKIP → #$next "$skippedWord" (stuck too long)');
          _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
        }
      }
    }
  }

  void _setupNativeSttCallbacks() {
    _nativeSttService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _nativeSttService.onStatusChange = (status) {
      if (_disposed || _sessionStopped) return;
      _addDebugLog('🎤 STATUS: $status');
      _safeSetState((s) => s.copyWith(
        isListening: status == SpeechStatus.listening,
        statusMessage: '',
        hasError: false,
      ));
    };

    _nativeSttService.onError = (error) {
      if (_disposed || _sessionStopped) return;
      _addDebugLog('🎤 STT ERROR: $error');
      if (error.contains('error_language')) return;
      final isFatal = error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available');
      _safeSetState((s) => s.copyWith(
        statusMessage: isFatal ? error : '',
        hasError: isFatal,
        isListening: isFatal ? false : s.isListening,
      ));
    };

    _nativeSttService.onLanguageUnavailable = (requestedLocale) {
      if (_disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(
        _scriptLanguageLocale ?? requestedLocale,
      );
      _addDebugLog('🎤 LANGUAGE UNAVAILABLE: $langName — speech data not installed');
      _safeSetState((s) => s.copyWith(
        missingLanguage: langName,
        hasError: true,
        isListening: false,
        statusMessage: 'Speech recognition language not installed',
      ));
    };

    _nativeSttService.onNeedLanguagePack = (locale) {
      if (_disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(locale);
      _addDebugLog('🎤 ALL GOOGLE STT FAILED for $langName — internet required for cloud recognition');
      _safeSetState((s) => s.copyWith(
        hasError: true,
        isListening: false,
        statusMessage: '$langName speech recognition requires an internet connection. '
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

    _fluidAdvanceTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_disposed || _sessionStopped) { timer.cancel(); return; }
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

  /// Find the next non-newline word index after [from]
  int? _nextRealWord(int from, Script script) {
    for (int i = from + 1; i < script.words.length; i++) {
      if (!script.words[i].isNewline) return i;
    }
    return null;
  }

  Future<void> startSession(Script script) async {
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sessionStopped = false;
    state = state.copyWith(
        confirmedWordIndex: 0, isListening: false, hasError: false,
        statusMessage: '', debugLogs: [], missingLanguage: null);

    _addDebugLog('🚀 SESSION START | ${script.words.where((w) => !w.isNewline).length} words');

    // Auto-detect language from script content
    final realWords = script.words.where((w) => !w.isNewline).toList();
    String? localeId;
    bool isHebrew = false;
    if (realWords.isNotEmpty) {
      final hebrewCount = realWords.where((w) => w.isRtl).length;
      final ratio = hebrewCount / realWords.length;
      isHebrew = ratio > 0.3;
      localeId = isHebrew ? 'he_IL' : 'en_US';
      _scriptLanguageLocale = localeId;
      _addDebugLog('🌐 LANG: ${isHebrew ? "Hebrew" : "English"} (${(ratio * 100).round()}% Hebrew chars)');
    }

    // Start heartbeat timer in debug mode
    _heartbeatTimer?.cancel();
    final settings = ref.read(settingsProvider);
    if (settings.debugMode) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_disposed) return;
        final pos = state.confirmedWordIndex;
        final total = script.words.where((w) => !w.isNewline).length;
        _addDebugLog('💓 HEARTBEAT: NATIVE_STT ${_nativeSttService.isListening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');
      });
    }

    _addDebugLog('🎤 Starting Native STT locale=$localeId...');
    final result = await _nativeSttService.start(localeId: localeId);

    if (!result.success) {
      _addDebugLog('🎤 STT FAILED: ${result.message}');
      _safeSetState((s) => s.copyWith(
        statusMessage: result.message ?? 'Speech recognition failed',
        hasError: true,
        isListening: false,
      ));
      return;
    }

    if (result.languageMissing && result.missingLanguageName != null) {
      _addDebugLog('⚠️ LANG MISSING: ${result.missingLanguageName} not available, using ${result.actualLocale}');
      _safeSetState((s) => s.copyWith(
        missingLanguage: result.missingLanguageName,
      ));
    } else {
      _addDebugLog('🎤 Using locale: ${result.actualLocale}');
    }
  }

  Future<void> stopSession() async {
    _sessionStopped = true;
    _heartbeatTimer?.cancel();
    _fluidAdvanceTimer?.cancel();

    await _nativeSttService.stop();

    if (!_disposed) {
      try {
        state = state.copyWith(
          isListening: false,
          hasError: false,
          statusMessage: '',
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
  }
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(TeleprompterNotifier.new);
