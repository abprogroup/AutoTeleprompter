part of 'word_aligner.dart';

bool _shouldPreserveSlowContext({
  required List<ScriptWord> script,
  required String transcript,
  required int lastConfirmedIndex,
  required SttRecognitionPolicy policy,
  required bool strictBulletMode,
  required int lookBackWords,
  required int lookAheadWords,
}) {
  if (script.isEmpty || transcript.trim().isEmpty) return false;
  final rawWords =
      transcript
          .split(RegExp(r'\s+'))
          .map((word) => word.trim().normalizeForMatching())
          .where((word) => word.isNotEmpty)
          .toList();
  final transcriptWords = _collapseAbbreviations(rawWords);
  if (transcriptWords.isEmpty) return false;

  final context = _slowContextIndices(
    script,
    lastConfirmedIndex,
    lookBackWords: lookBackWords,
    lookAheadWords: lookAheadWords,
  );
  if (context.isEmpty) return false;

  var currentOrAheadScore = 0.0;
  var offPathScore = 0.0;
  final evidenceThreshold = policy.safetyRecovery;
  final recentWords =
      transcriptWords.length > 10
          ? transcriptWords.sublist(transcriptWords.length - 10)
          : transcriptWords;

  for (final spoken in recentWords) {
    final match = _bestSlowContextMatch(
      script,
      context,
      spoken,
      strictBulletMode: strictBulletMode,
    );
    if (match == null) {
      offPathScore += evidenceThreshold.evidenceCost(spoken);
      continue;
    }
    if (match >= lastConfirmedIndex) {
      currentOrAheadScore += evidenceThreshold.evidenceCost(
        script[match].normalized,
      );
    }
  }

  return currentOrAheadScore > 0 &&
      offPathScore <= evidenceThreshold.smallWords;
}

List<int> _slowContextIndices(
  List<ScriptWord> script,
  int lastConfirmedIndex, {
  required int lookBackWords,
  required int lookAheadWords,
}) {
  final indices = <int>[];
  var before = 0;
  for (
    var i = lastConfirmedIndex.clamp(0, script.length - 1).toInt();
    i >= 0 && before < lookBackWords;
    i--
  ) {
    if (script[i].isNewline || _isUnspeakable(script[i])) continue;
    indices.add(i);
    before++;
  }

  var after = 0;
  for (
    var i = lastConfirmedIndex + 1;
    i < script.length && after < lookAheadWords;
    i++
  ) {
    if (script[i].isNewline || _isUnspeakable(script[i])) continue;
    indices.add(i);
    after++;
  }
  return indices;
}

int? _bestSlowContextMatch(
  List<ScriptWord> script,
  List<int> contextIndices,
  String spoken, {
  required bool strictBulletMode,
}) {
  var bestIndex = -1;
  var bestScore = 0.0;
  for (final index in contextIndices) {
    final word = script[index];
    if (word.normalized.isEmpty) continue;
    final score = _wordSimilarity(spoken, word.normalized, word.isRtl);
    final threshold =
        strictBulletMode
            ? WordAligner._strictPhraseThreshold
            : (word.isRtl
                ? WordAligner._hebrewMatchThreshold
                : WordAligner._matchThreshold);
    if (score < threshold || score <= bestScore) continue;
    bestScore = score;
    bestIndex = index;
  }
  if (bestIndex < 0) return null;
  return bestIndex;
}
