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
    } catch (_) { return; }
    final now = DateTime.now();
    final ts = "${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}";
    final entry = "[$ts] $log";
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

    final engineTag = _useWhisper ? '🤖' : '🎤';
    final skipThreshold = _useWhisper ? _whisperSkipAfterStuck : _googleSkipAfterStuck;

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

  void _setupSttCallbacks() {
    final platform = _sttService.platformName;

    _sttService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _sttService.onSoundLevelChange = (level) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // High-precision sound level telemetry for debugging silent Windows engines.
      // We throttle this to prevent UI stutter from log overflow.
      final now = DateTime.now();
      if (_lastVolLog == null || now.difference(_lastVolLog!) > const Duration(milliseconds: 700)) {
        _lastVolLog = now;
        final bar = ('#' * (level * 10).round().clamp(0, 10)).padRight(10, '_');
        _addDebugLog('🎤 [$platform] VOL: [$bar] (${level.toStringAsFixed(2)})');
      }
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
        statusMessage: 'Speech recognition language not installed on this device',
      ));
    };

    // Android-only: fires when offline + cloud STT both fail for a language.
    // On Apple/Windows this callback is never invoked.
    _sttService.onNeedLanguagePack = (locale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(locale);
      _addDebugLog('🎤 [$platform] ALL STT FAILED for $langName — internet required');
      _safeSetState((s) => s.copyWith(
        hasError: true,
        isListening: false,
        statusMessage: '$langName speech recognition requires an internet connection. '
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
        statusMessage: '',
        hasError: false,
      ));
    };

    _whisperService.onError = (error) {
      if (_disposed || _sessionStopped) return;
      _addDebugLog('🤖 WHISPER ERROR: $error');
      final isFatal = error.contains('not available') || error.contains('init failed');
      if (isFatal) {
        _safeSetState((s) => s.copyWith(
          statusMessage: error,
          hasError: true,
          isListening: false,
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
      statusMessage: 'Google speech blocked on this device. '
          'Go to Settings and download a Whisper model for offline recognition.',
    ));
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
    final sttEngine = ref.read(settingsProvider).sttEngine;
    _useWhisper = sttEngine.startsWith('whisper');
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
        final engineName = _useWhisper ? 'WHISPER' : _sttService.platformName.toUpperCase();
        final listening = _useWhisper ? _whisperService.isListening : _sttService.isListening;
        final pos = state.confirmedWordIndex;
        final total = script.words.where((w) => !w.isNewline).length;
        _addDebugLog('💓 HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');

        // Dead-air detection (specific to Windows native STT hanging silently)
        if (listening && pos == 0 && _noProgressCount > 0 && !state.hasError) {
           _addDebugLog('⚠️ WARNING: 15 seconds of dead-air. Windows mic may be muted or blocked.');
           if (_noProgressCount >= 3) {
             _safeSetState((s) => s.copyWith(
               statusMessage: 'Microphone is active but no audio detected. Check Windows sound settings or microphone privacy!',
             ));
           }
        }
      });
    }

    if (_useWhisper) {
      final model = whisperModelFromEngine(sttEngine);
      _addDebugLog('🤖 Starting Whisper STT ($sttEngine) offline...');
      await _whisperService.start(localeId: localeId, model: model);
    } else {
      final platform = _sttService.platformName;
      _addDebugLog('🎤 [$platform] Starting STT locale=$localeId...');
      final result = await _sttService.start(localeId: localeId);

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
        Future.delayed(const Duration(milliseconds: 1500), () => _startingSession = false);
      }

      if (result.languageMissing && result.missingLanguageName != null) {
        _addDebugLog('⚠️ [$platform] LANG MISSING: ${result.missingLanguageName} — using ${result.actualLocale}');
        _safeSetState((s) => s.copyWith(missingLanguage: result.missingLanguageName));
      } else {
        _addDebugLog('🎤 [$platform] STT using locale: ${result.actualLocale}');
      }
    }
  }

  Future<void> stopSession() async {
    _sessionStopped = true;
    _startingSession = false;
    _heartbeatTimer?.cancel();
    _fluidAdvanceTimer?.cancel();

    // Stop all engines — Whisper may have been auto-started via fallback
    await _sttService.stop();
    await _whisperService.stop();

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
