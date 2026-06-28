import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alignment_result.dart';
import '../services/debug_log_formatter.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../services/speech_service.dart';
import '../services/whisper_speech_service_native.dart';
import '../services/stt_movement_policy_service.dart';
import '../services/stt_recognition_policy_service.dart';
import '../services/stt_transcript_buffer_service.dart';
import '../services/stt_tracking_state.dart';
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
part 'teleprompter_provider.relock.dart';
part 'teleprompter_provider.session_watchdog.dart';
part 'teleprompter_provider.stt_callbacks.dart';
part 'teleprompter_provider.apple_quality.dart';
part 'teleprompter_provider.stt_gate.dart';
part 'teleprompter_provider.stt_result.dart';
part 'teleprompter_provider.registration.dart';
part 'teleprompter_provider.transcript_refresh.dart';
part 'teleprompter_provider.stale_partials.dart';

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
  String? _lastNoProgressTranscriptKey;
  int _staleNoProgressTranscriptCount = 0;
  DateTime? _poorAppleRecognitionStartedAt;
  DateTime? _lastPoorAppleRecognitionRestartAt;
  DateTime? _lastManualJumpTranscriptRefreshAt;
  String? _lastSttAdvanceTranscriptKey;
  int? _lastSttAdvanceTargetIndex;
  DateTime? _lastSttAdvanceAt;
  AppleSttHealth? _lastLoggedAppleHealth;
  AppleSttRecoveryAction? _lastLoggedAppleAction;
  DateTime? _appleRetryBurstWindowStart;
  int _appleRetryBurstCount = 0;
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
  bool _lockedOn = false;
  int _transcriptFloor = 0;
  SttEvidenceTrackingState _sttEvidenceTrackingState =
      SttEvidenceTrackingState.locked;
  Timer? _speechActivityMeterTimer;
  int _speechActivityMeterToken = 0;
  bool _stateFailureDiagnosticRecorded = false;
  static const int _maxAdvancePerUpdate = 30;
  static const int _maxLocalSttJumpWithoutWait = 2;
  static const int _visibleLocaleAssistAfterWaits = 2;
  static const int _sttLiveAlignmentWindowWords = 12;
  static const int _sttAlignmentWindowWords = 16;
  static const int _sttRelockTranscriptMaxWords = 18;
  static const int _appleSilentRestartLimit = 3;
  static const Duration _appleNativeCallbackStaleAfter = Duration(seconds: 45);
  static const Duration _appleSilentRestartWindow = Duration(seconds: 70);
  static const Duration _applePoorQualityRestartCooldown =
      Duration(seconds: 45);
  static const Duration _manualBackJumpTranscriptRefreshCooldown =
      Duration(seconds: 2);
  static const Duration _postAdvanceStalePartialWindow =
      Duration(milliseconds: 1800);
  static const String appleSttPreflightVersion = 'apple-stt-reliability-v1';
  static const Duration _visibleLocaleAssistCooldown =
      Duration(milliseconds: 900);
  static const Duration _visibleLocaleAssistPinDuration =
      Duration(milliseconds: 5000);

  void _resetSttTrackingContext({bool clearTranscriptFloor = true}) {
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _lockedOn = false;
    if (clearTranscriptFloor) _transcriptFloor = 0;
    _sttEvidenceTrackingState = SttEvidenceTrackingState.locked;
    _resetSttEvidenceGate();
    _resetStaleNoProgressTracking();
    _resetPostAdvancePartialGuard();
  }

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

  void _setupRemoteCallbacks() {}

  bool _sessionStopped = false;
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
    final normalized = DebugLogFormatter.normalize(log);
    final entry = "[$ts] $normalized";
    final logs = [...state.debugLogs];
    final fingerprint = DebugLogFormatter.coalesceFingerprint(normalized);
    if (fingerprint.isNotEmpty && logs.isNotEmpty) {
      final previous = DebugLogFormatter.coalesceFingerprint(
        DebugLogFormatter.stripTimestamp(logs.last),
      );
      if (previous == fingerprint) {
        logs[logs.length - 1] = entry;
      } else {
        logs.add(entry);
      }
    } else {
      logs.add(entry);
    }
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

  static String debugTranscriptSnippet(String transcript) =>
      SttRecognitionPolicyService.debugTranscriptSnippet(transcript);

  static String sttPostAdvancePartialKey(String transcript) {
    final words = SttRecognitionPolicyService.capTranscriptWords(
      transcript,
      maxWords: 12,
    )
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    return words.join(' ');
  }

  static bool isStalePostAdvancePartial({
    required String currentKey,
    required String? lastAdvanceKey,
  }) {
    if (currentKey.isEmpty ||
        lastAdvanceKey == null ||
        lastAdvanceKey.isEmpty) {
      return false;
    }
    return currentKey == lastAdvanceKey ||
        lastAdvanceKey.endsWith(' $currentKey');
  }

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

  /// Legacy numeric guard retained for focused tests only.
  /// Runtime STT movement must go through SttMovementPolicyService.
  @visibleForTesting
  static bool shouldWaitForLargeSttAdvance({
    required int currentIndex,
    required int targetIndex,
    required bool visibleSkipTargetTrusted,
    required int noProgressCount,
  }) {
    final jump = targetIndex - currentIndex;
    if (jump <= 0) return false;
    if (!visibleSkipTargetTrusted) return jump > _maxLocalSttJumpWithoutWait;
    if (jump <= 3) return false;
    return noProgressCount < 4;
  }

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
}
