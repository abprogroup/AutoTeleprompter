import '../../settings/models/app_settings.dart';
import 'spoken_number_normalizer.dart';
import 'word_aligner.dart';

class SttRecognitionPolicyService {
  static bool isEnglishLocale(String locale) =>
      locale.toLowerCase().replaceAll('_', '-').startsWith('en-') ||
      locale.toLowerCase() == 'en';

  /// Treats a browser adapter as listening only after its host handshake is
  /// complete. The adapter becomes active when its loopback server starts,
  /// which is earlier than microphone and recognizer readiness.
  static bool heartbeatListeningState({
    required bool serviceListening,
    required bool browserServiceActive,
    required bool browserHostReadinessComplete,
    required bool browserHostTransitionInFlight,
  }) {
    if (!serviceListening) return false;
    if (!browserServiceActive) return true;
    return browserHostReadinessComplete && !browserHostTransitionInFlight;
  }

  static List<String> _transcriptWords(String transcript) =>
      transcript
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.trim().isNotEmpty)
          .toList();

  static String capTranscriptWords(String transcript, {int maxWords = 96}) {
    final words = _transcriptWords(transcript);
    if (words.isEmpty) return '';
    final safeMax = maxWords.clamp(8, 240).toInt();
    if (words.length <= safeMax) return words.join(' ');
    final range = SpokenNumberNormalizer.expandSurfaceWindow(
      words,
      words.length - safeMax,
      words.length,
    );
    return words.sublist(range.start, range.endExclusive).join(' ');
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
      final range = SpokenNumberNormalizer.expandSurfaceWindow(
        words,
        start,
        end,
      );
      addWords(words.sublist(range.start, range.endExclusive));
    }

    addRange(words.length - safeShort, words.length);
    addRange(words.length - safeMedium, words.length);
    addRange(words.length - safeLong, words.length);

    final sentenceParts = _sentencePartsPreservingStructuredNumbers(transcript)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    for (
      var i = sentenceParts.length - 1;
      i >= 0 && windows.length < maxWindows;
      i--
    ) {
      final sentenceWords = _transcriptWords(sentenceParts[i]);
      if (sentenceWords.isEmpty) continue;
      final start =
          sentenceWords.length > safeLong ? sentenceWords.length - safeLong : 0;
      final range = SpokenNumberNormalizer.expandSurfaceWindow(
        sentenceWords,
        start,
        sentenceWords.length,
      );
      addWords(sentenceWords.sublist(range.start, range.endExclusive));
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

  static List<String> _sentencePartsPreservingStructuredNumbers(String text) {
    final parts = <String>[];
    final current = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      final isSeparator = '.!?;:…'.contains(char);
      var previous = index - 1;
      while (previous >= 0 && text[previous].trim().isEmpty) {
        previous--;
      }
      var next = index + 1;
      while (next < text.length && text[next].trim().isEmpty) {
        next++;
      }
      final betweenNumbers =
          (char == '.' || char == ':' || char == ';') &&
          previous >= 0 &&
          next < text.length &&
          _surfaceTokenIsNumber(_tokenBefore(text, index)) &&
          _surfaceTokenIsNumber(_tokenAfter(text, index));
      if (isSeparator && !betweenNumbers) {
        final part = current.toString();
        if (part.trim().isNotEmpty) parts.add(part);
        current.clear();
        continue;
      }
      current.write(char);
    }
    final tail = current.toString();
    if (tail.trim().isNotEmpty) parts.add(tail);
    return parts;
  }

  static String _tokenBefore(String text, int boundary) {
    var end = boundary;
    while (end > 0 && text[end - 1].trim().isEmpty) {
      end--;
    }
    var start = end - 1;
    while (start >= 0 && text[start].trim().isNotEmpty) {
      start--;
    }
    return text.substring(start + 1, end).trim();
  }

  static String _tokenAfter(String text, int boundary) {
    var start = boundary + 1;
    while (start < text.length && text[start].trim().isEmpty) {
      start++;
    }
    var end = start;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    return text.substring(start, end).trim();
  }

  static bool _surfaceTokenIsNumber(String surface) {
    if (surface.isEmpty) return false;
    return SpokenNumberNormalizer.hasTailNumericIntent([surface]);
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
      final range = SpokenNumberNormalizer.expandSurfaceWindow(
        words,
        start,
        end,
      );
      final window = words.sublist(range.start, range.endExclusive).join(' ');
      if (seen.add(window)) windows.add(window);
    }

    addWindow(words.length - safeWindow, words.length);

    final step = (safeWindow / 2).round().clamp(3, safeWindow).toInt();
    for (
      var end = words.length - step;
      end > 0 && windows.length < maxWindows - 1;
      end -= step
    ) {
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
      final manualVisibleThresholdsEnabled =
          manualVisibleSmall > 0 && manualVisibleBig > 0;
      final manualVisibleEnabled =
          settings.sttVisibleSkipEnabled && manualVisibleThresholdsEnabled;
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
      hardVisibleSkipEnabled:
          visibleSkipEnabled &&
          (settings.sttHardVisibleSkipEnabled || noisyRoom),
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
}
