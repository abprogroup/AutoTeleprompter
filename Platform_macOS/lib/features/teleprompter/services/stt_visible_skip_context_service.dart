import '../../../core/extensions/string_extensions.dart';
import '../../script/models/script_word.dart';
import 'word_aligner.dart';

class SttVisibleSkipContextService {
  const SttVisibleSkipContextService();

  String mergePendingTranscript({
    required String pendingTranscript,
    required String transcript,
    int maxWords = 18,
  }) {
    final pendingWords = _normalizedWords(pendingTranscript);
    final currentWords = _normalizedWords(transcript);
    if (currentWords.isEmpty) return pendingWords.join(' ');
    if (pendingWords.isEmpty) {
      return _capWords(currentWords, maxWords).join(' ');
    }
    if (_endsWith(pendingWords, currentWords)) {
      return _capWords(pendingWords, maxWords).join(' ');
    }
    if (_endsWith(currentWords, pendingWords)) {
      return _capWords(currentWords, maxWords).join(' ');
    }

    var overlap = 0;
    final maxOverlap = pendingWords.length < currentWords.length
        ? pendingWords.length
        : currentWords.length;
    for (var size = maxOverlap; size > 0; size--) {
      final pendingTail = pendingWords.sublist(pendingWords.length - size);
      final currentHead = currentWords.sublist(0, size);
      if (_sameWords(pendingTail, currentHead)) {
        overlap = size;
        break;
      }
    }

    return _capWords(
      [...pendingWords, ...currentWords.sublist(overlap)],
      maxWords,
    ).join(' ');
  }

  AlignmentResult? rescueAlignment({
    required List<ScriptWord> script,
    required String pendingTranscript,
    required String transcript,
    required int lastConfirmedIndex,
    required int? visibleSkipStartIndex,
    required int? maxSkipTargetIndex,
    required SttRecognitionPolicy policy,
    bool strictBulletMode = false,
  }) {
    if (pendingTranscript.trim().isEmpty) return null;
    final merged = mergePendingTranscript(
      pendingTranscript: pendingTranscript,
      transcript: transcript,
    );
    if (merged.trim().isEmpty || merged == transcript.trim()) return null;
    final aligned = WordAligner.align(
      script: script,
      transcript: merged,
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: strictBulletMode,
      policy: policy,
      readingStandby: true,
    );
    if (!aligned.shouldAdvance ||
        aligned.confirmedWordIndex <= lastConfirmedIndex) {
      return null;
    }
    if (aligned.thresholdFamily != SttThresholdFamily.visibleSkip &&
        aligned.kind != SttAlignmentKind.visiblePhrase &&
        aligned.kind != SttAlignmentKind.sentenceRecovery) {
      return null;
    }
    return aligned.copyWith(
      debugInfo: 'VISIBLE_SKIP_ACCUMULATED | ${aligned.debugInfo}',
      evidenceWords: _normalizedWords(merged),
    );
  }

  bool shouldPreserve({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    required int? visibleSkipStartIndex,
    required int? maxSkipTargetIndex,
    required SttRecognitionPolicy policy,
    bool strictBulletMode = false,
  }) {
    if (!policy.visibleSkipEnabled ||
        maxSkipTargetIndex == null ||
        script.isEmpty ||
        transcript.trim().isEmpty) {
      return false;
    }
    final rawWords = _normalizedWords(transcript);
    if (policy.visibleSkip.evidenceScore(rawWords) < 2) return false;

    final relaxed = WordAligner.align(
      script: script,
      transcript: transcript,
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: strictBulletMode,
      policy: SttRecognitionPolicy(
        bulletMode: policy.bulletMode,
        visibleSkipEnabled: true,
        hardVisibleSkipEnabled: false,
        startAdvance: policy.startAdvance,
        safetyRecovery: policy.safetyRecovery,
        bulletAdvance: policy.bulletAdvance,
        visibleSkip: SttEvidenceThreshold(
          2,
          1,
          policy.visibleSkip.bigWordMinLetters,
        ),
      ),
      readingStandby: true,
    );
    if (!relaxed.shouldAdvance ||
        relaxed.confirmedWordIndex <= lastConfirmedIndex) {
      return false;
    }
    return relaxed.thresholdFamily == SttThresholdFamily.visibleSkip ||
        relaxed.kind == SttAlignmentKind.visiblePhrase ||
        relaxed.kind == SttAlignmentKind.sentenceRecovery;
  }

  List<String> _normalizedWords(String transcript) => transcript
      .split(RegExp(r'\s+'))
      .map((word) => word.trim().normalizeForMatching())
      .where((word) => word.isNotEmpty)
      .toList(growable: false);

  List<String> _capWords(List<String> words, int maxWords) {
    final safeMax = maxWords.clamp(4, 40).toInt();
    if (words.length <= safeMax) return words;
    return words.sublist(words.length - safeMax);
  }

  bool _endsWith(List<String> source, List<String> suffix) {
    if (suffix.isEmpty || suffix.length > source.length) return false;
    return _sameWords(source.sublist(source.length - suffix.length), suffix);
  }

  bool _sameWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
