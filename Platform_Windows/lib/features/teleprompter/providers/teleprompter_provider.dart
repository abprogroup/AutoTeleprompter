import 'dart:async';
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
import '../services/stt_visible_skip_context_service.dart';
import '../services/teleprompter_locale_resolver.dart';
import '../services/word_aligner.dart';
import '../../script/models/script.dart';
import '../../script/models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../core/extensions/string_extensions.dart';

import '../../../platform/stt/stt_service_factory.dart';
part 'teleprompter_provider.heartbeat.dart';
part 'teleprompter_provider.locale.dart';
part 'teleprompter_provider.relock.dart';
part 'teleprompter_provider.stt_callbacks.dart';
part 'teleprompter_provider.stt.dart';

class TeleprompterNotifier extends Notifier<TeleprompterState> {
  late AbstractSttService _sttService;
  late final AbstractSttService _browserSttService;
  late final AbstractSttService _desktopSttService;
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
  bool _sttReadingStandby = false;
  bool _activeSttCanSwitchLocale = true;
  String _activeSttEngineLabel = 'Browser Online';
  bool _lockedOn = false;
  int _transcriptFloor = 0;
  int? _pendingStartEvidenceTargetIndex;
  String _pendingVisibleSkipTranscript = '';
  int? _pendingVisibleSkipOriginIndex;
  int? _pendingVisibleSkipStartIndex;
  int? _pendingVisibleSkipEndIndex;
  SttEvidenceTrackingState _sttEvidenceTrackingState =
      SttEvidenceTrackingState.locked;
  String? _lastNoProgressTranscriptKey;
  int _staleNoProgressTranscriptCount = 0;
  DateTime? _lastBrowserHeartbeatAt;
  DateTime? _lastRecoverableSttErrorAt;
  int _recoverableSttErrorCount = 0;
  bool _sttRecoveryInFlight = false;
  bool _stateFailureDiagnosticRecorded = false;

  // STT tuning
  static const int _maxAdvancePerUpdate = 30;
  static const int _maxLocalSttJumpWithoutWait = 2;
  static const int _visibleLocaleAssistAfterWaits = 2;
  static const int _sttLiveAlignmentWindowWords = 10;
  static const int _sttAlignmentWindowWords = 18;
  static const int _sttRelockTranscriptMaxWords = 96;
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
    _pendingStartEvidenceTargetIndex = null;
    _clearPendingVisibleSkipEvidence();
    _sttEvidenceTrackingState = SttEvidenceTrackingState.locked;
    _resetStaleNoProgressTracking();
  }

  void _resetStaleNoProgressTracking() {
    _lastNoProgressTranscriptKey = null;
    _staleNoProgressTranscriptCount = 0;
  }

  void _clearPendingVisibleSkipEvidence() {
    _pendingVisibleSkipTranscript = '';
    _pendingVisibleSkipOriginIndex = null;
    _pendingVisibleSkipStartIndex = null;
    _pendingVisibleSkipEndIndex = null;
  }

  int _currentSttAdvanceGuardIndex(int confirmedIndex) =>
      _fluidAdvanceTimer?.isActive == true && _fluidTarget > confirmedIndex
          ? _fluidTarget
          : confirmedIndex;

  String _noProgressTranscriptKey(String transcript) {
    final words = transcript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '';
    final start = words.length > 8 ? words.length - 8 : 0;
    return words.sublist(start).join(' ');
  }

  @override
  TeleprompterState build() {
    _disposed = false;
    _stateFailureDiagnosticRecorded = false;
    _browserSttService = SttServiceFactory.createWindowsBrowser();
    _desktopSttService = SttServiceFactory.createWindowsDesktop();
    _sttService = _browserSttService;
    _whisperService = WhisperSpeechService();
    _remoteControlService = ref.read(remoteControlProvider);
    _setupRemoteCallbacks();
    _setupSttCallbacks(_browserSttService);
    _setupSttCallbacks(_desktopSttService);
    _setupWhisperCallbacks();
    ref.onDispose(() {
      _disposed = true;
      _heartbeatTimer?.cancel();
      _browserSttService.stop();
      _desktopSttService.stop();
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
    } catch (e, stack) {
      _recordStateFailureDiagnostic('safeSetState', e, stack);
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

  /// Common handler for STT results - shared between Google and Whisper.
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

  static bool _wordCarriesLanguage(ScriptWord word) =>
      TeleprompterLocaleResolver.wordCarriesLanguage(word);

  static List<String> resolveSectionLocalesForWords(List<ScriptWord> words) =>
      TeleprompterLocaleResolver.resolveSectionLocalesForWords(words);

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

  Future<void> startSession(Script script) async {
    final pendingStop = _stopInFlight;
    if (pendingStop != null) await pendingStop;
    if (_disposed) return;

    final token = ++_sessionToken;
    // Compare by sessionId rather than object identity. _startPresenting()
    // always rebuilds the Script object, so identical() always returns false
    // causing the resume position to reset to 0 on every re-entry. Using
    // sessionId (stable across editor edits of the same session) lets us
    // distinguish "re-entered same session" from "loaded a different script".
    final sameScript = _currentScript != null &&
        _currentScript!.sessionId.isNotEmpty &&
        _currentScript!.sessionId == script.sessionId;
    _currentScript = script;
    _resetSttTrackingContext();
    _sessionStopped = false;
    _sessionStartTime = DateTime.now();
    _silentWarningFired = false;
    _lastVolLog = null;
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _resetVisibleLocaleAssist();
    _precomputeSectionLocales(script);
    final settings = ref.read(settingsProvider);
    final sttEngine = settings.sttEngine;
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
        'SESSION START | ${script.words.where((w) => !w.isNewline).length} words | pos=$startIndex');
    _addDebugLog(
      'STT SETTINGS: engine=${settings.sttEngine} language=${settings.languageMode}',
    );
    LightweightDiagnostics.instance.record(
      'session',
      'presentation session started',
      data: {
        'title': script.title,
        'sessionId': script.sessionId,
        'sourceType': script.sourceType,
        'wordCount': script.words.where((w) => !w.isNewline).length,
        'startIndex': startIndex,
      },
    );
    final localeId = resolveInitialSttLocaleForSettings(
      script.words,
      settings,
      startIndex: startIndex,
      sectionLocales: _sectionLocales,
    );
    _scriptLanguageLocale = localeId;
    _activeLocale = localeId;
    if (!_useWhisper) {
      _lastBrowserHeartbeatAt = null;
      _lastRecoverableSttErrorAt = null;
      _recoverableSttErrorCount = 0;
      _sttRecoveryInFlight = false;
      _sttService = _resolveWindowsSpeechService(settings, localeId);
      await (_sttService == _browserSttService
          ? _desktopSttService.stop()
          : _browserSttService.stop());
    }

    // v4.2: Detect starting locale focusing ONLY on the immediate first words.
    // This prevents a long Hebrew document from forcing English start-text into Hebrew STT.
    if (script.words.isNotEmpty) {
      final initialLocale = localeId;

      final realWords = script.words.where(_wordCarriesLanguage).toList();
      final hebrewCount =
          realWords.where((w) => _explicitLocaleForWord(w) == 'he_IL').length;
      final ratio = realWords.isEmpty ? 0 : hebrewCount / realWords.length;
      _addDebugLog(
          'LANG: ${initialLocale == "he_IL" ? "Hebrew" : "English"} start (${(ratio * 100).round()}% Hebrew language words)');
      _addDebugLog(
          'STT START LOCALE: $localeId | sections=${_sectionLocales.toSet().length}');
    }

    _startSessionHeartbeat(script);

    if (_useWhisper) {
      final model = whisperModelFromEngine(sttEngine);
      _addDebugLog('Starting Whisper STT ($sttEngine) offline...');
      await _whisperService.start(localeId: localeId, model: model);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _whisperService.stop();
        return;
      }
    } else {
      var platform = _activeSttEngineLabel;
      final selectedMicId = settings.sttInputDeviceId.trim();
      final selectedMicLabel = settings.sttInputDeviceLabel.trim();
      _sttService.setAudioInputDevice(
        selectedMicId.isEmpty ? null : selectedMicId,
        label: selectedMicLabel.isEmpty
            ? 'System default microphone'
            : selectedMicLabel,
      );
      _addDebugLog('[$platform] Starting STT locale=$localeId...');
      _addDebugLog(selectedMicId.isEmpty
          ? '[$platform] Microphone: system default input'
          : '[$platform] Microphone: $selectedMicLabel');
      var result = await _sttService.start(localeId: localeId);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _sttService.stop();
        return;
      }

      if (!result.success &&
          settings.sttEngine == AppSettings.sttEngineAuto &&
          _sttService == _desktopSttService) {
        _addDebugLog(
          '[Windows built-in speech-to-text] unavailable for English, '
          'falling back to Browser online speech-to-text.',
        );
        await _desktopSttService.stop();
        _sttService = _browserSttService;
        _activeSttCanSwitchLocale = true;
        _activeSttEngineLabel = 'Browser online speech-to-text';
        platform = _activeSttEngineLabel;
        _sttService.setAudioInputDevice(
          selectedMicId.isEmpty ? null : selectedMicId,
          label: selectedMicLabel.isEmpty
              ? 'System default microphone'
              : selectedMicLabel,
        );
        result = await _sttService.start(localeId: localeId);
        if (_disposed || _sessionStopped || token != _sessionToken) {
          await _sttService.stop();
          return;
        }
      }

      if (!result.success) {
        _addDebugLog('[$platform] STT FAILED: ${result.message}');
        LightweightDiagnostics.instance.record(
          'stt',
          'STT start failed',
          data: {'platform': platform, 'message': result.message},
        );
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
            '[$platform] LANG MISSING: ${result.missingLanguageName} - using ${result.actualLocale}');
        _safeSetState(
            (s) => s.copyWith(missingLanguage: result.missingLanguageName));
      } else {
        _addDebugLog('[$platform] STT using locale: ${result.actualLocale}');
        LightweightDiagnostics.instance.record(
          'stt',
          'STT started',
          data: {'platform': platform, 'locale': result.actualLocale},
        );
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
    LightweightDiagnostics.instance.record(
      'session',
      'presentation session stopped',
      data: {'position': state.confirmedWordIndex},
    );
    _startingSession = false;
    _heartbeatTimer?.cancel();
    _fluidAdvanceTimer?.cancel();
    _resetSttTrackingContext();
    _lastVolLog = null;
    _scriptLanguageLocale = null;
    _activeLocale = null;
    _sectionLocales = [];
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _resetVisibleLocaleAssist();

    // Stop all engines - Whisper may have been auto-started via fallback.
    final stopFuture = Future.wait([
      _browserSttService.stop(),
      _desktopSttService.stop(),
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
      } catch (e, stack) {
        _recordStateFailureDiagnostic('stopListening.finalState', e, stack);
      }
    }
  }

  void resetPosition() {
    _resetSttTrackingContext();
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog('POSITION RESET -> 0');
    LightweightDiagnostics.instance.record('position', 'position reset');
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
    _resetSttTrackingContext();
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog(
        'POSITION JUMP -> #$target "${activeScript.words[target].raw}"');
    LightweightDiagnostics.instance.record(
      'position',
      'position jumped',
      data: {'target': target, 'word': activeScript.words[target].raw},
    );
    try {
      state = state.copyWith(confirmedWordIndex: target);
    } catch (e, stack) {
      _recordStateFailureDiagnostic('jumpToPosition', e, stack);
      _disposed = true;
      return;
    }
    if (!_sessionStopped && state.isListening) {
      _syncLocaleForPosition(activeScript, target, reason: 'manual jump');
    }
  }

  Future<void> refreshAudioInputDevices() async {
    final devices = await _sttService.refreshAudioInputDevices();
    if (!_disposed) {
      state = state.copyWith(audioInputDevices: devices);
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
    unawaited(refreshAudioInputDevices());
    _addDebugLog(normalizedId.isEmpty
        ? 'Microphone input set to system default'
        : 'Microphone input set to $normalizedLabel');
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
