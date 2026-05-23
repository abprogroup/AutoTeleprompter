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
part 'teleprompter_provider.stt.dart';

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
  bool _sttReadingStandby = false;

  // â”€â”€ STT tuning â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  TeleprompterState get _currentState => state;

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
    return false;
  }

  static bool shouldUseImprovisationNoMatch({
    required bool strictBulletMode,
    required int alignedIndex,
    required int currentIndex,
  }) {
    return strictBulletMode && alignedIndex <= currentIndex;
  }

  static SttRecognitionPolicy recognitionPolicyForSettings(
      AppSettings settings) {
    if (settings.sttManualProfileEnabled) {
      final manualVisibleSmall = settings.sttManualVisibleSkipSmallWords;
      final manualVisibleBig = settings.sttManualVisibleSkipBigWords;
      final manualVisibleEnabled =
          manualVisibleSmall > 0 && manualVisibleBig > 0;
      final bigWordMinLetters = settings.sttManualBigWordMinLetters;
      return SttRecognitionPolicy(
        bulletMode: false,
        visibleSkipEnabled: manualVisibleEnabled,
        hardVisibleSkipEnabled: false,
        startAdvance: SttEvidenceThreshold(
          settings.sttManualStartAdvanceSmallWords,
          settings.sttManualStartAdvanceBigWords,
          bigWordMinLetters,
        ),
        safetyRecovery: SttEvidenceThreshold(
          settings.sttManualSafetySmallWords,
          settings.sttManualSafetyBigWords,
          bigWordMinLetters,
        ),
        visibleSkip: SttEvidenceThreshold(
          manualVisibleEnabled ? manualVisibleSmall : 4,
          manualVisibleEnabled ? manualVisibleBig : 3,
          bigWordMinLetters,
        ),
      );
    }

    final visibleSkipEnabled = settings.sttVisibleSkipEnabled;
    return SttRecognitionPolicy(
      bulletMode: settings.sttStrictBulletMode,
      visibleSkipEnabled: visibleSkipEnabled,
      hardVisibleSkipEnabled:
          visibleSkipEnabled && settings.sttHardVisibleSkipEnabled,
    );
  }

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
    if (words.isEmpty || sectionLocales.length != words.length) return false;
    final start = visibleStart.clamp(0, words.length - 1).toInt();
    final end = visibleEnd.clamp(start, words.length - 1).toInt();
    final minIndex = (currentIndex + 1).clamp(0, end).toInt();
    final scanStart = start < minIndex ? minIndex : start;
    if (scanStart > end) return false;

    final visible = <String>[];
    for (var i = scanStart; i <= end; i++) {
      final word = words[i];
      if (!_wordCarriesLanguage(word)) continue;
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

  static String? _explicitLocaleForWord(ScriptWord word) {
    if (word.isNewline) return null;
    final text = '${word.raw} ${word.normalized}';
    if (RegExp(r'[\u0590-\u05FF]').hasMatch(text)) return 'he_IL';
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en_US';
    return null;
  }

  static bool _wordCarriesLanguage(ScriptWord word) =>
      _explicitLocaleForWord(word) != null;

  static String _inheritLocaleForNeutralWord(
    List<ScriptWord> words,
    Map<int, String> explicitLocales,
    int index,
  ) {
    String? scan(int step, {required bool stopAtNewline}) {
      var i = index + step;
      while (i >= 0 && i < words.length) {
        if (stopAtNewline && words[i].isNewline) return null;
        final locale = explicitLocales[i];
        if (locale != null) return locale;
        i += step;
      }
      return null;
    }

    final previousInParagraph = scan(-1, stopAtNewline: true);
    final nextInParagraph = scan(1, stopAtNewline: true);
    if (previousInParagraph != null) return previousInParagraph;
    if (nextInParagraph != null) return nextInParagraph;

    return scan(-1, stopAtNewline: false) ??
        scan(1, stopAtNewline: false) ??
        'en_US';
  }

  static List<String> resolveSectionLocalesForWords(List<ScriptWord> words) {
    const minSectionWords = 2;

    final languageEntries = <({int index, String locale})>[];
    for (var i = 0; i < words.length; i++) {
      final locale = _explicitLocaleForWord(words[i]);
      if (locale != null) languageEntries.add((index: i, locale: locale));
    }

    if (words.isEmpty) return [];
    if (languageEntries.isEmpty) {
      return List<String>.filled(words.length, 'en_US');
    }

    final smoothed = [for (final entry in languageEntries) entry.locale];
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

    final explicitLocales = <int, String>{
      for (var i = 0; i < languageEntries.length; i++)
        languageEntries[i].index: smoothed[i],
    };

    return [
      for (var i = 0; i < words.length; i++)
        explicitLocales[i] ??
            _inheritLocaleForNeutralWord(words, explicitLocales, i),
    ];
  }

  static String resolveInitialSttLocale(
    List<ScriptWord> words, {
    int startIndex = 0,
    List<String>? sectionLocales,
  }) {
    if (words.isEmpty) return 'en_US';

    final safeStart = startIndex.clamp(0, words.length - 1).toInt();
    var hebrew = 0;
    var english = 0;
    String? firstLocale;

    for (var i = safeStart; i < words.length && hebrew + english < 5; i++) {
      final locale = _explicitLocaleForWord(words[i]);
      if (locale == null) continue;
      firstLocale ??= locale;
      if (locale == 'he_IL') {
        hebrew++;
      } else {
        english++;
      }
    }

    if (hebrew > english) return 'he_IL';
    if (english > hebrew) return 'en_US';
    if (firstLocale != null) return firstLocale;

    if (sectionLocales != null && sectionLocales.isNotEmpty) {
      return sectionLocales[safeStart.clamp(0, sectionLocales.length - 1)];
    }
    return 'en_US';
  }

  Future<void> startSession(Script script) async {
    final pendingStop = _stopInFlight;
    if (pendingStop != null) await pendingStop;
    if (_disposed) return;

    final token = ++_sessionToken;
    // Compare by sessionId rather than object identity. _startPresenting()
    // always rebuilds the Script object, so identical() always returns false
    // â€” causing the resume position to reset to 0 on every re-entry. Using
    // sessionId (stable across editor edits of the same session) lets us
    // distinguish "re-entered same session" from "loaded a different script".
    final sameScript = _currentScript != null &&
        _currentScript!.sessionId.isNotEmpty &&
        _currentScript!.sessionId == script.sessionId;
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _sessionStopped = false;
    _sessionStartTime = DateTime.now();
    _silentWarningFired = false;
    _lastVolLog = null;
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _resetVisibleLocaleAssist();
    _precomputeSectionLocales(script);
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
        'ðŸš€ SESSION START | ${script.words.where((w) => !w.isNewline).length} words | pos=$startIndex');
    final localeId = resolveInitialSttLocale(
      script.words,
      startIndex: startIndex,
      sectionLocales: _sectionLocales,
    );
    _scriptLanguageLocale = localeId;
    _activeLocale = localeId;

    // v4.2: Detect starting locale focusing ONLY on the immediate first words.
    // This prevents a long Hebrew document from forcing English start-text into Hebrew STT.
    if (script.words.isNotEmpty) {
      final initialLocale = localeId;

      final realWords = script.words.where(_wordCarriesLanguage).toList();
      final hebrewCount =
          realWords.where((w) => _explicitLocaleForWord(w) == 'he_IL').length;
      final ratio = realWords.isEmpty ? 0 : hebrewCount / realWords.length;
      _addDebugLog(
          'ðŸŒ LANG: ${initialLocale == "he_IL" ? "Hebrew" : "English"} start (${(ratio * 100).round()}% Hebrew language words)');
      _addDebugLog(
          'STT START LOCALE: $localeId | sections=${_sectionLocales.toSet().length}');
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
            'ðŸ’“ HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');

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
                'ðŸš¨ SILENT LISTENING: engine is active but receiving NO audio for ${elapsed.inSeconds}s.');
            _addDebugLog(
                'ðŸ‘‰ FIX: Ensure "Online Speech Recognition" is ON in Privacy Settings or install the Hebrew Offline Pack.');
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
          final policy =
              recognitionPolicyForSettings(ref.read(settingsProvider));
          if (policy.bulletMode && _noProgressCount > 0) return;
          _syncLocaleForPosition(_currentScript!, state.confirmedWordIndex + 1,
              reason: 'heartbeat');
        }
      });
    }

    if (_useWhisper) {
      final model = whisperModelFromEngine(sttEngine);
      _addDebugLog('ðŸ¤– Starting Whisper STT ($sttEngine) offline...');
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
      _addDebugLog('ðŸŽ¤ [$platform] Starting STT locale=$localeId...');
      _addDebugLog(selectedMicId.isEmpty
          ? 'ðŸŽ™ï¸ [$platform] Microphone: system default input'
          : 'ðŸŽ™ï¸ [$platform] Microphone: $selectedMicLabel');
      final result = await _sttService.start(localeId: localeId);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _sttService.stop();
        return;
      }

      if (!result.success) {
        _addDebugLog('ðŸŽ¤ [$platform] STT FAILED: ${result.message}');
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
            'âš ï¸ [$platform] LANG MISSING: ${result.missingLanguageName} â€” using ${result.actualLocale}');
        _safeSetState(
            (s) => s.copyWith(missingLanguage: result.missingLanguageName));
      } else {
        _addDebugLog(
            'ðŸŽ¤ [$platform] STT using locale: ${result.actualLocale}');
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
    _lastVolLog = null;
    _scriptLanguageLocale = null;
    _activeLocale = null;
    _sectionLocales = [];
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _resetVisibleLocaleAssist();

    // Stop all engines â€” Whisper may have been auto-started via fallback
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
    _sttReadingStandby = false;
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog('ðŸ”„ POSITION RESET â†’ 0');
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
    _sttReadingStandby = false;
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog(
        'ðŸ“ POSITION JUMP â†’ #$target "${activeScript.words[target].raw}"');
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
        ? 'ðŸŽ™ï¸ Microphone input set to system default'
        : 'ðŸŽ™ï¸ Microphone input set to $normalizedLabel');
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
