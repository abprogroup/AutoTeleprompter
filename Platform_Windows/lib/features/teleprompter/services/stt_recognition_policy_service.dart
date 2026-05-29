import '../../settings/models/app_settings.dart';
import 'word_aligner.dart';

class SttRecognitionPolicyService {
  static bool isEnglishLocale(String locale) =>
      locale.toLowerCase().replaceAll('_', '-').startsWith('en-') ||
      locale.toLowerCase() == 'en';

  static List<String> rollingTranscriptWindowsForAlignment(
    String transcript, {
    required int windowWords,
    int maxWindows = 6,
  }) {
    final words = transcript
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
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
}
