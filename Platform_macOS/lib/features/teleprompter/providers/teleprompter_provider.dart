import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/debug_log_formatter.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../services/speech_service.dart';
import '../services/whisper_speech_service_native.dart';
import '../services/stt_recognition_policy_service.dart';
import '../services/stt_visible_relock_service.dart';
import '../services/teleprompter_locale_resolver.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../script/models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/stt/stt_service_factory.dart';

part 'teleprompter_provider.session_parts.dart';
part 'teleprompter_provider.session_watchdog.dart';
part 'teleprompter_provider.stt_callbacks.dart';

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
  DateTime? _lastSttResultAt;
  DateTime? _sessionStartTime;
  DateTime? _lastSttWatchdogRestartAt;
  DateTime? _appleSilentRestartWindowStart;
  int _appleSilentRestartCount = 0;
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
  bool _sttReadingStandby = false;
  String _lastRelockScope = 'none';
  int? _sequentialSttBaseIndex;
  int? _sequentialSttEndIndex;
  double _sequentialSttEvidence = 0.0;
  bool _sequentialSttUnlocked = false;
  String? _sequentialSttLastToken;
  DateTime? _sequentialSttLastTokenAt;
  Timer? _speechActivityMeterTimer;
  int _speechActivityMeterToken = 0;
  bool _stateFailureDiagnosticRecorded = false;

  // STT tuning
  static const int _maxAdvancePerUpdate = 30;
  static const int _maxLocalSttJumpWithoutWait = 5;
  static const int _maxTrustedVisibleSttJumpWithoutWait = 12;
  static const int _visibleLocaleAssistAfterWaits = 2;
  static const int _sttLiveAlignmentWindowWords = 10;
  static const int _sttAlignmentWindowWords = 18;
  static const int _sttRelockTranscriptMaxWords = 96;
  static const int _stuckRelockAfterWaits = 3;
  static const int _relaxedVisibleRelockAfterWaits = 12;
  static const int _appleSilentRestartLimit = 3;
  static const Duration _appleNativeCallbackStaleAfter =
      Duration(seconds: 12);
  static const Duration _appleSilentRestartWindow = Duration(seconds: 70);
  static const Duration _visibleLocaleAssistCooldown =
      Duration(milliseconds: 900);
  static const Duration _visibleLocaleAssistPinDuration =
      Duration(milliseconds: 5000);

  @override
  TeleprompterState build() {
    _disposed = false;
    _stateFailureDiagnosticRecorded = false;
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
      _speechActivityMeterTimer?.cancel();
      _recordDisposeStopFailure(
        _sttService.stop(),
        source: 'teleprompterProvider.disposeSttStop',
      );
      _recordDisposeStopFailure(
        _whisperService.stop(),
        source: 'teleprompterProvider.disposeWhisperStop',
      );
      _recordDisposeStopFailure(
        _remoteControlService.stop(),
        source: 'teleprompterProvider.disposeRemoteStop',
      );
    });
    return const TeleprompterState();
  }

  // v4.0: Remote control features hidden for stable release
  void _setupRemoteCallbacks() {}

  bool _sessionStopped = false;
  // Guard against the race where iOS fires an async 'notListening' status
  // from the previous stop() call after the new session has already started.
  bool _startingSession = false;

  void _recordDisposeStopFailure(
    Future<void> stopFuture, {
    required String source,
  }) {
    unawaited(stopFuture.catchError((Object error, StackTrace stack) {
      LightweightDiagnostics.instance.recordError(error, stack, source: source);
    }));
  }

  void _safeSetState(TeleprompterState Function(TeleprompterState) updater) {
    if (_disposed || _sessionStopped) return;
    try {
      final current = state;
      state = updater(current);
    } catch (e, stack) {
      _recordStateFailureDiagnostic('safeSetState', e, stack);
      _disposed = true;
    }
  }

  /// Writes state guarded only by disposal — used by session-control methods
  /// (start/stop/reset/jump/device refresh) that must apply even after the
  /// session is stopped (e.g. clearing isListening on stop, or moving the
  /// resume point while browsing stopped). Lives in the class so extension
  /// parts never touch the protected `state` member directly.
  void _writeState(TeleprompterState Function(TeleprompterState) updater) {
    if (_disposed) return;
    try {
      state = updater(state);
    } catch (e, stack) {
      _recordStateFailureDiagnostic('writeState', e, stack);
      _disposed = true;
    }
  }

  void _recordStateFailureDiagnostic(
    String source,
    Object error,
    StackTrace stack,
  ) {
    if (_stateFailureDiagnosticRecorded) return;
    _stateFailureDiagnosticRecorded = true;
    LightweightDiagnostics.instance.recordError(
      error,
      stack,
      source: 'teleprompterProvider.$source',
    );
  }

  TeleprompterState get _currentState => state;

  void _addDebugLog(String log) {
    if (_disposed) return;
    try {
      final settings = ref.read(settingsProvider);
      if (!settings.debugMode) return;
    } catch (e, stack) {
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'teleprompterProvider.debugModeRead',
      );
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

  static bool _isEnglishLocale(String locale) =>
      SttRecognitionPolicyService.isEnglishLocale(locale);

  static bool shouldUseWindowsOfflineSpeech({
    required AppSettings settings,
    required String initialLocale,
    required List<String> sectionLocales,
  }) {
    final engine = AppSettings.normalizeSttEngine(settings.sttEngine);
    if (engine == AppSettings.sttEngineWindowsOffline) return true;
    if (engine != AppSettings.sttEngineAuto) return false;
    return _isEnglishLocale(initialLocale) &&
        sectionLocales.isNotEmpty &&
        sectionLocales.every(_isEnglishLocale);
  }

  static List<String> rollingTranscriptWindowsForAlignment(
    String transcript, {
    int windowWords = _sttAlignmentWindowWords,
    int maxWindows = 6,
  }) =>
      SttRecognitionPolicyService.rollingTranscriptWindowsForAlignment(
        transcript,
        windowWords: windowWords,
        maxWindows: maxWindows,
      );

  static List<String> liveTranscriptWindowsForAlignment(
    String transcript, {
    int shortWindowWords = _sttLiveAlignmentWindowWords,
    int longWindowWords = _sttAlignmentWindowWords,
    int maxWindows = 8,
  }) =>
      SttRecognitionPolicyService.liveTranscriptWindowsForAlignment(
        transcript,
        shortWindowWords: shortWindowWords,
        longWindowWords: longWindowWords,
        maxWindows: maxWindows,
      );

  static String capTranscriptForRelock(
    String transcript, {
    int maxWords = _sttRelockTranscriptMaxWords,
  }) =>
      SttRecognitionPolicyService.capTranscriptWords(
        transcript,
        maxWords: maxWords,
      );

  static int resolveAdvanceTarget({
    required int currentIndex,
    required int alignedIndex,
    required int? visibleMaxSkipTargetIndex,
  }) =>
      SttRecognitionPolicyService.resolveAdvanceTarget(
        currentIndex: currentIndex,
        alignedIndex: alignedIndex,
        visibleMaxSkipTargetIndex: visibleMaxSkipTargetIndex,
        maxAdvancePerUpdate: _maxAdvancePerUpdate,
      );

  static bool shouldWaitForLargeSttAdvance({
    required int currentIndex,
    required int targetIndex,
    required bool visibleSkipTargetTrusted,
    required int noProgressCount,
  }) =>
      SttRecognitionPolicyService.shouldWaitForLargeAdvance(
        currentIndex: currentIndex,
        targetIndex: targetIndex,
        visibleSkipTargetTrusted: visibleSkipTargetTrusted,
        noProgressCount: noProgressCount,
        maxLocalAdvanceWithoutWait: _maxLocalSttJumpWithoutWait,
        maxTrustedVisibleAdvanceWithoutWait:
            _maxTrustedVisibleSttJumpWithoutWait,
        forceVisibleAfterWaits: _relaxedVisibleRelockAfterWaits,
      );

  static bool shouldForceSkipAfterNoProgress({
    required bool strictBulletMode,
    required int noProgressCount,
    required int skipThreshold,
  }) =>
      SttRecognitionPolicyService.shouldForceSkipAfterNoProgress(
        strictBulletMode: strictBulletMode,
        noProgressCount: noProgressCount,
        skipThreshold: skipThreshold,
      );

  static bool shouldUseImprovisationNoMatch({
    required bool strictBulletMode,
    required int alignedIndex,
    required int currentIndex,
  }) =>
      SttRecognitionPolicyService.shouldUseImprovisationNoMatch(
        strictBulletMode: strictBulletMode,
        alignedIndex: alignedIndex,
        currentIndex: currentIndex,
      );

  static SttRecognitionPolicy recognitionPolicyForSettings(
    AppSettings settings,
  ) =>
      SttRecognitionPolicyService.recognitionPolicyForSettings(settings);

  static int nextNoProgressCount({
    required int currentCount,
    required bool improvising,
    required int visibleAssistThreshold,
  }) {
    final next = currentCount + 1;
    if (!improvising) return next;
    return next.clamp(0, visibleAssistThreshold).toInt();
  }

  static int? resolveVisibleSkipTarget({
    required bool visibleSkipEnabled,
    required bool strictBulletMode,
    required int? visibleWordStart,
    required int? visibleWordEnd,
  }) {
    if (!visibleSkipEnabled) return null;
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
    return TeleprompterLocaleResolver.visibleTranscriptPlausiblyMatchesLocale(
      words: words,
      sectionLocales: sectionLocales,
      locale: locale,
      transcript: transcript,
      visibleStart: visibleStart,
      visibleEnd: visibleEnd,
      currentIndex: currentIndex,
    );
  }

  static bool shouldBlockLocaleSyncDuringAssistPin({
    required String? pinnedLocale,
    required String? activeLocale,
    required String? scriptLocale,
    required DateTime? pinnedUntil,
    required DateTime now,
  }) {
    return TeleprompterLocaleResolver.shouldBlockLocaleSyncDuringAssistPin(
      pinnedLocale: pinnedLocale,
      activeLocale: activeLocale,
      scriptLocale: scriptLocale,
      pinnedUntil: pinnedUntil,
      now: now,
    );
  }

  static String? _explicitLocaleForWord(ScriptWord word) =>
      TeleprompterLocaleResolver.explicitLocaleForWord(word);

  static String? _strongLocaleForWord(ScriptWord word) =>
      _explicitLocaleForWord(word);

  static bool _wordCarriesLanguage(ScriptWord word) =>
      TeleprompterLocaleResolver.wordCarriesLanguage(word);

  static List<String> resolveSectionLocalesForWords(List<ScriptWord> words) =>
      TeleprompterLocaleResolver.resolveSectionLocalesForWords(words);

  static List<String> resolveSttSectionLocalesForWords(
          List<ScriptWord> words) =>
      resolveSectionLocalesForWords(words);

  static String resolveInitialSttLocale(
    List<ScriptWord> words, {
    int startIndex = 0,
    List<String>? sectionLocales,
  }) {
    return TeleprompterLocaleResolver.resolveInitialSttLocale(
      words,
      startIndex: startIndex,
      sectionLocales: sectionLocales,
    );
  }

  static String resolveInitialSttLocaleForSettings(
    List<ScriptWord> words,
    AppSettings settings, {
    int startIndex = 0,
    List<String>? sectionLocales,
  }) {
    switch (AppSettings.normalizeLanguageMode(settings.languageMode)) {
      case AppSettings.languageModeHebrew:
        return 'he_IL';
      case AppSettings.languageModeEnglish:
        return 'en_US';
      default:
        return resolveInitialSttLocale(
          words,
          startIndex: startIndex,
          sectionLocales: sectionLocales,
        );
    }
  }

  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));

    final words = result.words.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);

      // Voice Commands
      if (words.contains('stop prompt') ||
          words.contains('\u05E2\u05E6\u05D5\u05E8') ||
          words.contains('\u05E2\u05E6\u05D9\u05E8\u05D4')) {
        _addDebugLog('VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') ||
          words.contains('\u05D1\u05D5\u05D0')) {
        _addDebugLog('VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return;
      } else if (words.contains('speed up') ||
          words.contains('\u05DE\u05D4\u05E8')) {
        _addDebugLog('VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') ||
          words.contains('\u05DC\u05D0\u05D8')) {
        _addDebugLog('VOICE COMMAND: SLOWER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'teleprompterProvider.voiceCommandSettings',
      );
    }

    _accumulatedTranscript =
        TeleprompterNotifier.capTranscriptForRelock(result.words);
    final alignmentWindows = _recentTranscriptWindows(_accumulatedTranscript);
    var alignmentTranscript =
        alignmentWindows.isEmpty ? '' : alignmentWindows.first;
    final script = _currentScript!;
    final settings = ref.read(settingsProvider);
    final policy = TeleprompterNotifier.recognitionPolicyForSettings(settings);
    final strictBulletMode = policy.bulletMode;
    final maxSkipTargetIndex = TeleprompterNotifier.resolveVisibleSkipTarget(
      visibleSkipEnabled: policy.visibleSkipEnabled,
      strictBulletMode: false,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );

    AlignmentResult alignWindow(String transcriptWindow) => WordAligner.align(
          script: script.words,
          transcript: transcriptWindow,
          lastConfirmedIndex: _currentState.confirmedWordIndex,
          visibleSkipStartIndex:
              maxSkipTargetIndex == null ? null : _visibleWordStart,
          maxSkipTargetIndex: maxSkipTargetIndex,
          strictBulletMode: strictBulletMode,
          policy: policy,
          readingStandby: _sttReadingStandby,
        );

    var aligned = alignWindow(alignmentTranscript);
    if (!aligned.shouldAdvance &&
        !aligned.shouldEnterStandby &&
        alignmentWindows.length > 1) {
      for (var i = 1; i < alignmentWindows.length; i++) {
        final candidateTranscript = alignmentWindows[i];
        final candidate = alignWindow(candidateTranscript);
        if (candidate.shouldAdvance &&
            candidate.confirmedWordIndex > _currentState.confirmedWordIndex) {
          alignmentTranscript = candidateTranscript;
          aligned = AlignmentResult(
            candidate.confirmedWordIndex,
            candidate.confidence,
            '${candidate.debugInfo} | rollingWindow=${i + 1}/${alignmentWindows.length}',
            candidate.decision,
          );
          break;
        }
      }
    }

    final currentIdx = _currentState.confirmedWordIndex;
    final nextExpected = (currentIdx + 1 < script.words.length)
        ? script.words
            .skip(currentIdx + 1)
            .where((w) => !w.isNewline && w.normalized.isNotEmpty)
            .take(3)
            .map((w) => w.raw)
            .join(' ')
        : '<END>';

    final engineTag = _useWhisper ? '[Whisper]' : '[Speech]';
    if (aligned.shouldEnterStandby) {
      _sttReadingStandby = true;
      _noProgressCount = 0;
      _addDebugLog(
          '$engineTag STANDBY LOCK | ${aligned.debugInfo} | heard: "$alignmentTranscript"');
      LightweightDiagnostics.instance.record(
        'stt',
        'standby lock',
        data: {
          'heard': alignmentTranscript,
          'position': _currentState.confirmedWordIndex,
          'confidence': aligned.confidence,
        },
      );
      return;
    }

    if (aligned.shouldAdvance &&
        aligned.confirmedWordIndex > _currentState.confirmedWordIndex) {
      final advanceFrom = _currentState.confirmedWordIndex;
      final visibleSkipTargetTrusted =
          TeleprompterNotifier.isTrustedVisibleSkipTarget(
        alignedIndex: aligned.confirmedWordIndex,
        visibleWordStart: _visibleWordStart,
        visibleWordEnd: _visibleWordEnd,
      );
      final rawJump = aligned.confirmedWordIndex - advanceFrom;
      final shouldWaitForJump =
          TeleprompterNotifier.shouldWaitForLargeSttAdvance(
        currentIndex: advanceFrom,
        targetIndex: aligned.confirmedWordIndex,
        visibleSkipTargetTrusted: visibleSkipTargetTrusted,
        noProgressCount: _noProgressCount,
      );
      if (shouldWaitForJump) {
        _fluidAdvanceTimer?.cancel();
        _resetSequentialSttStreak();
        if (!strictBulletMode) {
          _sttReadingStandby = false;
        }
        _noProgressCount = TeleprompterNotifier.nextNoProgressCount(
          currentCount: _noProgressCount,
          improvising: false,
          visibleAssistThreshold:
              TeleprompterNotifier._visibleLocaleAssistAfterWaits,
        );
        final scope = visibleSkipTargetTrusted ? 'visible' : 'off-screen';
        _addDebugLog(
          '$engineTag WAIT #$_noProgressCount | blocked $scope advance '
          '+$rawJump ->${aligned.confirmedWordIndex} | heard: "$alignmentTranscript"',
        );
        LightweightDiagnostics.instance.record(
          'stt',
          'blocked $scope advance',
          data: {
            'from': advanceFrom,
            'aligned': aligned.confirmedWordIndex,
            'jump': rawJump,
            'visibleStart': _visibleWordStart,
            'visibleEnd': _visibleWordEnd,
            'heard': alignmentTranscript,
          },
        );
        return;
      }

      _sttReadingStandby = true;
      _noProgressCount = 0;
      _resetVisibleLocaleAssist();
      final target = TeleprompterNotifier.resolveAdvanceTarget(
        currentIndex: advanceFrom,
        alignedIndex: aligned.confirmedWordIndex,
        visibleMaxSkipTargetIndex:
            visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
      );
      final advancedWord =
          target < script.words.length ? script.words[target].raw : '?';
      _addDebugLog(
          '$engineTag ADVANCE -> #$target "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "$alignmentTranscript"');
      LightweightDiagnostics.instance.record(
        'stt',
        'advanced',
        data: {
          'from': _currentState.confirmedWordIndex,
          'to': target,
          'word': advancedWord,
          'confidence': aligned.confidence,
          'heard': alignmentTranscript,
        },
      );

      _applySttAdvanceTarget(target, script);
      _syncLocaleForPosition(script, target + 1, reason: 'advance');
    } else {
      final improvising = TeleprompterNotifier.shouldUseImprovisationNoMatch(
        strictBulletMode: strictBulletMode,
        alignedIndex: aligned.confirmedWordIndex,
        currentIndex: _currentState.confirmedWordIndex,
      );
      if (!strictBulletMode) {
        _sttReadingStandby = false;
      }

      final sequential = _consumeSequentialSttStreak(
        script: script,
        transcript: alignmentTranscript,
        policy: policy,
        strictBulletMode: strictBulletMode,
      );
      if (sequential != null) {
        if (sequential.targetIndex != null &&
            sequential.targetIndex! > _currentState.confirmedWordIndex) {
          final target = sequential.targetIndex!;
          final advancedWord =
              target < script.words.length ? script.words[target].raw : '?';
          _fluidAdvanceTimer?.cancel();
          _noProgressCount = 0;
          _sttReadingStandby = true;
          _resetVisibleLocaleAssist();
          _addDebugLog(
            '$engineTag SEQUENTIAL ADVANCE -> #$target "$advancedWord" | ${sequential.debugInfo}',
          );
          LightweightDiagnostics.instance.record(
            'stt',
            'sequential advanced',
            data: {
              'to': target,
              'word': advancedWord,
              'heard': alignmentTranscript,
              'debug': sequential.debugInfo,
            },
          );
          _applySttAdvanceTarget(target, script);
          _syncLocaleForPosition(script, target + 1, reason: 'sequential');
          return;
        }

        _noProgressCount = 0;
        _sttReadingStandby = true;
        _addDebugLog('$engineTag SEQUENTIAL HOLD | ${sequential.debugInfo}');
        return;
      }

      _noProgressCount = TeleprompterNotifier.nextNoProgressCount(
        currentCount: _noProgressCount,
        improvising: improvising,
        visibleAssistThreshold:
            TeleprompterNotifier._visibleLocaleAssistAfterWaits,
      );
      if (improvising) {
        _addDebugLog(
            '$engineTag IMPROVISING | heard: "$alignmentTranscript" | visible relock waiting');
        LightweightDiagnostics.instance.record(
          'stt',
          'improvising',
          data: {'heard': alignmentTranscript, 'position': currentIdx},
        );
      } else {
        _addDebugLog(
            '$engineTag WAIT #$_noProgressCount | heard: "$alignmentTranscript" | next: "$nextExpected"');
        LightweightDiagnostics.instance.record(
          'stt',
          'waiting',
          data: {
            'heard': alignmentTranscript,
            'next': nextExpected,
            'position': currentIdx,
            'stuckCount': _noProgressCount,
          },
        );
        _checkAndSwitchLocale();
      }

      final relockTranscript = _accumulatedTranscript.trim().isEmpty
          ? alignmentTranscript
          : _accumulatedTranscript;
      final relockTarget = _relockTargetFromTranscript(
        script,
        relockTranscript,
      );
      if (relockTarget != null &&
          relockTarget > _currentState.confirmedWordIndex) {
        final relockFrom = _currentState.confirmedWordIndex;
        final relockVisibleTrusted =
            TeleprompterNotifier.isTrustedVisibleSkipTarget(
          alignedIndex: relockTarget,
          visibleWordStart: _visibleWordStart,
          visibleWordEnd: _visibleWordEnd,
        );
        if (TeleprompterNotifier.shouldWaitForLargeSttAdvance(
          currentIndex: relockFrom,
          targetIndex: relockTarget,
          visibleSkipTargetTrusted: relockVisibleTrusted,
          noProgressCount: _noProgressCount,
        )) {
          _fluidAdvanceTimer?.cancel();
          _resetSequentialSttStreak();
          final relockJump = relockTarget - relockFrom;
          _addDebugLog(
            '$engineTag WAIT #$_noProgressCount | delayed ${_lastRelockScope.toUpperCase()} relock '
            '+$relockJump ->$relockTarget | heard: "$relockTranscript"',
          );
          LightweightDiagnostics.instance.record(
            'stt',
            'delayed relock',
            data: {
              'from': relockFrom,
              'to': relockTarget,
              'jump': relockJump,
              'scope': _lastRelockScope,
              'heard': relockTranscript,
            },
          );
          return;
        }
        final relockedWord = script.words[relockTarget].raw;
        _addDebugLog(
          '$engineTag RELOCK ${_lastRelockScope.toUpperCase()} -> #$relockTarget "$relockedWord" | heard: "$relockTranscript"',
        );
        LightweightDiagnostics.instance.record(
          'stt',
          'relocked',
          data: {
            'from': _currentState.confirmedWordIndex,
            'to': relockTarget,
            'word': relockedWord,
            'scope': _lastRelockScope,
            'heard': relockTranscript,
          },
        );
        _noProgressCount = 0;
        _sttReadingStandby = true;
        _applySttAdvanceTarget(relockTarget, script);
        _syncLocaleForPosition(script, relockTarget + 1, reason: 'relock');
        return;
      }

      if (_maybeAssistVisibleLocale(script, policy, alignmentTranscript)) {
        return;
      }
    }
  }
}

class _SequentialSttProgress {
  final int? targetIndex;
  final String debugInfo;

  const _SequentialSttProgress(this.targetIndex, this.debugInfo);
}

final teleprompterProvider =
    NotifierProvider<TeleprompterNotifier, TeleprompterState>(
        TeleprompterNotifier.new);
