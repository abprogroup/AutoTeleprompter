import '../../settings/models/app_settings.dart';
import 'word_aligner.dart';

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
