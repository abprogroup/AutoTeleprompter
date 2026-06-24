import '../../settings/models/app_settings.dart';
import 'word_aligner.dart';

enum AppleSttHealth {
  healthy,
  recognizingWrongWords,
  lowVoiceSignal,
  noisyInput,
  engineDropped,
}

enum AppleSttRecoveryAction {
  none,
  coach,
  suggestNoisyRoom,
  suggestManualFallback,
  softRestart,
  fullRestart,
}

class AppleSttHealthAssessment {
  final AppleSttHealth health;
  final AppleSttRecoveryAction action;
  final String message;
  final double quality;

  const AppleSttHealthAssessment({
    required this.health,
    required this.action,
    required this.message,
    required this.quality,
  });

  bool get shouldRestart =>
      action == AppleSttRecoveryAction.softRestart ||
      action == AppleSttRecoveryAction.fullRestart;

  bool get shouldFullRestart => action == AppleSttRecoveryAction.fullRestart;

  String get healthKey => health.name;
}

class SttRecognitionPolicyService {
  static bool isEnglishLocale(String locale) =>
      locale.toLowerCase().replaceAll('_', '-').startsWith('en-') ||
      locale.toLowerCase() == 'en';

  static List<String> _transcriptWords(String transcript) => transcript
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .toList();

  static String capTranscriptWords(
    String transcript, {
    int maxWords = 96,
  }) {
    final words = _transcriptWords(transcript);
    if (words.isEmpty) return '';
    final safeMax = maxWords.clamp(8, 240).toInt();
    if (words.length <= safeMax) return words.join(' ');
    return words.sublist(words.length - safeMax).join(' ');
  }

  static List<String> liveTranscriptWindowsForAlignment(
    String transcript, {
    int shortWindowWords = 10,
    int mediumWindowWords = 14,
    int longWindowWords = 18,
    int maxWindows = 8,
  }) {
    final words = _transcriptWords(transcript);
    if (words.isEmpty) return const [];

    final safeShort = shortWindowWords.clamp(4, 40).toInt();
    final safeMedium = mediumWindowWords.clamp(safeShort, 80).toInt();
    final safeLong = longWindowWords.clamp(safeMedium, 120).toInt();
    if (words.length <= safeShort) return [words.join(' ')];

    final windows = <String>[];
    final seen = <String>{};

    void addWords(List<String> candidate) {
      if (candidate.isEmpty || windows.length >= maxWindows) return;
      final window = candidate.join(' ');
      if (seen.add(window)) windows.add(window);
    }

    void addRange(int rawStart, int rawEnd) {
      final start = rawStart.clamp(0, words.length).toInt();
      final end = rawEnd.clamp(start, words.length).toInt();
      if (end <= start) return;
      addWords(words.sublist(start, end));
    }

    addRange(words.length - safeShort, words.length);
    addRange(words.length - safeMedium, words.length);
    addRange(words.length - safeLong, words.length);

    final sentenceParts = transcript
        .split(RegExp(r'[.!?;:…]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    for (var i = sentenceParts.length - 1;
        i >= 0 && windows.length < maxWindows;
        i--) {
      final sentenceWords = _transcriptWords(sentenceParts[i]);
      if (sentenceWords.isEmpty) continue;
      final start =
          sentenceWords.length > safeLong ? sentenceWords.length - safeLong : 0;
      addWords(sentenceWords.sublist(start));
    }

    for (final window in rollingTranscriptWindowsForAlignment(
      transcript,
      windowWords: safeLong,
      maxWindows: maxWindows,
    )) {
      if (windows.length >= maxWindows) break;
      addWords(_transcriptWords(window));
    }

    return windows.take(maxWindows).toList(growable: false);
  }

  static List<String> rollingTranscriptWindowsForAlignment(
    String transcript, {
    required int windowWords,
    int maxWindows = 6,
  }) {
    final words = _transcriptWords(transcript);
    if (words.isEmpty) return const [];
    final safeWindow = windowWords.clamp(4, 80).toInt();
    if (words.length <= safeWindow) return [words.join(' ')];

    final windows = <String>[];
    final seen = <String>{};

    void addWindow(int rawStart, int rawEnd) {
      final start = rawStart.clamp(0, words.length).toInt();
      final end = rawEnd.clamp(start, words.length).toInt();
      if (end <= start) return;
      final window = words.sublist(start, end).join(' ');
      if (seen.add(window)) windows.add(window);
    }

    addWindow(words.length - safeWindow, words.length);

    final step = (safeWindow / 2).round().clamp(3, safeWindow).toInt();
    for (var end = words.length - step;
        end > 0 && windows.length < maxWindows - 1;
        end -= step) {
      addWindow(end - safeWindow, end);
    }

    addWindow(0, safeWindow);
    return windows.take(maxWindows).toList(growable: false);
  }

  static int resolveAdvanceTarget({
    required int currentIndex,
    required int alignedIndex,
    required int? visibleMaxSkipTargetIndex,
    required int maxAdvancePerUpdate,
  }) {
    if (visibleMaxSkipTargetIndex != null &&
        alignedIndex <= visibleMaxSkipTargetIndex) {
      return alignedIndex;
    }
    return alignedIndex
        .clamp(currentIndex, currentIndex + maxAdvancePerUpdate)
        .toInt();
  }

  static bool shouldWaitForLargeAdvance({
    required int currentIndex,
    required int targetIndex,
    required bool visibleSkipTargetTrusted,
    required int noProgressCount,
    required int maxLocalAdvanceWithoutWait,
    required int maxTrustedVisibleAdvanceWithoutWait,
    required int forceVisibleAfterWaits,
  }) {
    final jump = targetIndex - currentIndex;
    if (jump <= 0) return false;
    if (!visibleSkipTargetTrusted) {
      return jump > maxLocalAdvanceWithoutWait;
    }
    if (jump <= maxTrustedVisibleAdvanceWithoutWait) return false;
    return noProgressCount < forceVisibleAfterWaits;
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
    AppSettings settings,
  ) {
    final noisyRoom =
        settings.sttReliabilityMode == AppSettings.sttReliabilityNoisyRoom;
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
          manualVisibleEnabled
              ? (noisyRoom
                  ? manualVisibleSmall.clamp(5, 8).toInt()
                  : manualVisibleSmall)
              : (noisyRoom ? 5 : 4),
          manualVisibleEnabled
              ? (noisyRoom
                  ? manualVisibleBig.clamp(4, 8).toInt()
                  : manualVisibleBig)
              : (noisyRoom ? 4 : 3),
          bigWordMinLetters,
        ),
      );
    }

    final visibleSkipEnabled = settings.sttVisibleSkipEnabled;
    return SttRecognitionPolicy(
      bulletMode: settings.sttStrictBulletMode,
      visibleSkipEnabled: visibleSkipEnabled,
      hardVisibleSkipEnabled: visibleSkipEnabled &&
          (settings.sttHardVisibleSkipEnabled || noisyRoom),
    );
  }

  static AppleSttHealthAssessment classifyAppleSttHealth({
    required String reliabilityMode,
    required bool shouldBeListening,
    required bool listening,
    required bool startingSession,
    required bool canRestart,
    required DateTime now,
    required DateTime? sessionStart,
    required DateTime? lastNativeCallback,
    required double soundLevel,
    required String transcript,
    required bool matchedScript,
    required int noProgressCount,
    required int repeatedTranscriptCount,
    required Duration poorQualityDuration,
    int retryBurstCount = 0,
    Duration noNativeCallbacksAfter = const Duration(seconds: 25),
  }) {
    if (!shouldBeListening) {
      return const AppleSttHealthAssessment(
        health: AppleSttHealth.healthy,
        action: AppleSttRecoveryAction.none,
        message: '',
        quality: 1.0,
      );
    }

    final droppedReason = appleWatchdogRestartReason(
      now: now,
      shouldBeListening: shouldBeListening,
      listening: listening,
      startingSession: startingSession,
      canRestart: canRestart,
      sessionStart: sessionStart,
      lastNativeCallback: lastNativeCallback,
      noNativeCallbacksAfter: noNativeCallbacksAfter,
    );
    final retryBurstDropped = retryBurstCount >= 3 && canRestart;
    if ((!listening && !startingSession && canRestart) ||
        retryBurstDropped ||
        droppedReason != null) {
      return const AppleSttHealthAssessment(
        health: AppleSttHealth.engineDropped,
        action: AppleSttRecoveryAction.fullRestart,
        message: 'Speech recognizer stopped responding. Recovering listener...',
        quality: 0.0,
      );
    }

    if (matchedScript) {
      return const AppleSttHealthAssessment(
        health: AppleSttHealth.healthy,
        action: AppleSttRecoveryAction.none,
        message: '',
        quality: 1.0,
      );
    }

    final words = transcript
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;
    final normalizedSound = soundLevel.clamp(0.0, 1.0).toDouble();
    final noisyRoom = reliabilityMode == AppSettings.sttReliabilityNoisyRoom;
    final sustainedPoor = noProgressCount >= 3 ||
        repeatedTranscriptCount >= 2 ||
        poorQualityDuration >= const Duration(seconds: 6);
    final shouldSuggestManual =
        poorQualityDuration >= const Duration(seconds: 30);

    if (noProgressCount >= 2 && normalizedSound <= 0.08 && words == 0) {
      return AppleSttHealthAssessment(
        health: AppleSttHealth.lowVoiceSignal,
        action: shouldSuggestManual
            ? AppleSttRecoveryAction.suggestManualFallback
            : AppleSttRecoveryAction.coach,
        message:
            'Mic signal is low. Move closer to the microphone, choose a closer input, or use an external mic.',
        quality: 0.20,
      );
    }

    final shortWrongFragment = words > 0 && words <= 2 && noProgressCount >= 1;
    if (shortWrongFragment || repeatedTranscriptCount >= 2) {
      return AppleSttHealthAssessment(
        health: AppleSttHealth.recognizingWrongWords,
        action: shouldSuggestManual
            ? AppleSttRecoveryAction.suggestManualFallback
            : (!noisyRoom && sustainedPoor
                ? AppleSttRecoveryAction.suggestNoisyRoom
                : AppleSttRecoveryAction.coach),
        message:
            'Mic signal is active, but Apple Speech is hearing words that do not match the script. Move the mic closer or reduce room noise.',
        quality: 0.36,
      );
    }

    if (sustainedPoor && normalizedSound >= 0.18) {
      return AppleSttHealthAssessment(
        health: AppleSttHealth.noisyInput,
        action: shouldSuggestManual
            ? AppleSttRecoveryAction.suggestManualFallback
            : (!noisyRoom
                ? AppleSttRecoveryAction.suggestNoisyRoom
                : AppleSttRecoveryAction.coach),
        message:
            'Mic signal is active, but Apple Speech is not finding clear script words. Try Noisy room mode or reduce room noise.',
        quality: 0.45,
      );
    }

    return const AppleSttHealthAssessment(
      health: AppleSttHealth.healthy,
      action: AppleSttRecoveryAction.none,
      message: '',
      quality: 0.75,
    );
  }

  static bool shouldSoftRestartPoorAppleRecognition({
    required String reliabilityMode,
    required int noProgressCount,
    required int repeatedTranscriptCount,
    required Duration poorQualityDuration,
    required DateTime now,
    required DateTime? lastRestartAt,
    Duration cooldown = const Duration(seconds: 45),
  }) {
    if (lastRestartAt != null && now.difference(lastRestartAt) < cooldown) {
      return false;
    }
    final noisyRoom = reliabilityMode == AppSettings.sttReliabilityNoisyRoom;
    final minimumDuration =
        noisyRoom ? const Duration(seconds: 30) : const Duration(seconds: 15);
    final minimumWaits = noisyRoom ? 14 : 10;
    final minimumRepeats = noisyRoom ? 4 : 3;
    return poorQualityDuration >= minimumDuration &&
        noProgressCount >= minimumWaits &&
        repeatedTranscriptCount >= minimumRepeats;
  }

  static String? browserRecoveryReason({
    required DateTime now,
    required DateTime? sessionStart,
    required DateTime? lastHeartbeat,
    required DateTime? lastRecoverableError,
    required int recoverableErrorCount,
    Duration missingInitialHeartbeatAfter = const Duration(seconds: 18),
    Duration staleHeartbeatAfter = const Duration(seconds: 18),
    Duration recoverableErrorWindow = const Duration(seconds: 30),
    int recoverableErrorThreshold = 3,
  }) {
    if (lastHeartbeat == null) {
      final start = sessionStart;
      if (start != null &&
          now.difference(start) > missingInitialHeartbeatAfter) {
        return 'missing browser heartbeat';
      }
    } else if (now.difference(lastHeartbeat) > staleHeartbeatAfter) {
      return 'stale browser heartbeat';
    }

    if (lastRecoverableError != null &&
        now.difference(lastRecoverableError) < recoverableErrorWindow &&
        recoverableErrorCount >= recoverableErrorThreshold) {
      return 'recoverable browser errors';
    }

    return null;
  }

  static String? appleWatchdogRestartReason({
    required DateTime now,
    required bool shouldBeListening,
    required bool listening,
    required bool startingSession,
    required bool canRestart,
    required DateTime? sessionStart,
    required DateTime? lastNativeCallback,
    Duration noNativeCallbacksAfter = const Duration(seconds: 25),
  }) {
    if (!shouldBeListening || !listening || startingSession || !canRestart) {
      return null;
    }

    final nativeBaseline = lastNativeCallback ?? sessionStart;
    final silentFor =
        nativeBaseline == null ? Duration.zero : now.difference(nativeBaseline);
    if (silentFor >= noNativeCallbacksAfter) {
      return 'no speech callbacks for ${silentFor.inSeconds}s';
    }
    return null;
  }

  static bool shouldRestartDroppedListener({
    required bool shouldBeListening,
    required bool listening,
    required bool startingSession,
    required bool canRestart,
  }) {
    return shouldBeListening && !listening && !startingSession && canRestart;
  }
}
