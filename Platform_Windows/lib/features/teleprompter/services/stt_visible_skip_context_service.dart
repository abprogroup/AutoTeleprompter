import '../../../core/extensions/string_extensions.dart';
import '../../script/models/script_word.dart';
import 'spoken_number_normalizer.dart';
import 'word_aligner.dart';

class SttVisibleSkipContextService {
  const SttVisibleSkipContextService();

  String mergePendingTranscript({
    required String pendingTranscript,
    required String transcript,
    int maxWords = 18,
  }) {
    final pendingWords = _surfaceWords(pendingTranscript);
    final currentWords = _surfaceWords(transcript);
    if (currentWords.isEmpty) return _joinSurface(pendingWords);
    if (pendingWords.isEmpty) {
      return _joinSurface(_capWords(currentWords, maxWords));
    }
    final numericRevision = _replaceTrailingNumberRevision(
      pendingWords,
      currentWords,
    );
    if (numericRevision != null) {
      return _joinSurface(_capWords(numericRevision, maxWords));
    }
    if (_endsWith(pendingWords, currentWords)) {
      return _joinSurface(_capWords(pendingWords, maxWords));
    }
    if (_endsWith(currentWords, pendingWords)) {
      return _joinSurface(_capWords(currentWords, maxWords));
    }

    var overlap = 0;
    final maxOverlap =
        pendingWords.length < currentWords.length
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

    return _joinSurface(
      _capWords([...pendingWords, ...currentWords.sublist(overlap)], maxWords),
    );
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
    final yearPairAlternative = _crossShardYearPairAlternative(
      pendingTranscript: pendingTranscript,
      transcript: transcript,
      normallyMerged: merged,
    );
    final candidates = <({String transcript, bool requiresExactYearPair})>[
      if (yearPairAlternative != null)
        (transcript: yearPairAlternative, requiresExactYearPair: true),
      (transcript: merged, requiresExactYearPair: false),
    ];
    for (final candidate in candidates) {
      if (candidate.transcript.trim().isEmpty ||
          candidate.transcript == transcript.trim()) {
        continue;
      }
      final aligned = WordAligner.align(
        script: script,
        transcript: candidate.transcript,
        lastConfirmedIndex: lastConfirmedIndex,
        visibleSkipStartIndex: visibleSkipStartIndex,
        maxSkipTargetIndex: maxSkipTargetIndex,
        strictBulletMode: strictBulletMode,
        policy: policy,
        readingStandby: true,
      );
      if (!aligned.shouldAdvance ||
          aligned.confirmedWordIndex <= lastConfirmedIndex) {
        continue;
      }
      if (candidate.requiresExactYearPair &&
          aligned.kind != SttAlignmentKind.numberPhrase) {
        continue;
      }
      if (aligned.thresholdFamily != SttThresholdFamily.visibleSkip &&
          aligned.kind != SttAlignmentKind.visiblePhrase &&
          aligned.kind != SttAlignmentKind.sentenceRecovery) {
        continue;
      }
      final evidenceWords =
          aligned.kind == SttAlignmentKind.numberMismatchRecovery ||
                  aligned.kind == SttAlignmentKind.numberPhrase
              ? aligned.evidenceWords
              : _normalizedWords(candidate.transcript);
      if (!policy.visibleSkip.passes(evidenceWords)) continue;
      return aligned.copyWith(
        debugInfo: 'VISIBLE_SKIP_ACCUMULATED | ${aligned.debugInfo}',
        evidenceWords: evidenceWords,
      );
    }
    return _fragmentedYearRescueAlignment(
      script: script,
      transcript: merged,
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      policy: policy,
      strictBulletMode: strictBulletMode,
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
  }) =>
      preservationAlignment(
        script: script,
        transcript: transcript,
        lastConfirmedIndex: lastConfirmedIndex,
        visibleSkipStartIndex: visibleSkipStartIndex,
        maxSkipTargetIndex: maxSkipTargetIndex,
        policy: policy,
        strictBulletMode: strictBulletMode,
      ) !=
      null;

  AlignmentResult? preservationAlignment({
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
      return null;
    }
    final rawWords = _normalizedWords(transcript);
    final fragmentedYear = fragmentedYearPreservationAlignment(
      script: script,
      transcript: transcript,
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    if (policy.visibleSkip.evidenceScore(rawWords) < 2) {
      return fragmentedYear;
    }

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
      return null;
    }
    final preservable =
        relaxed.thresholdFamily == SttThresholdFamily.visibleSkip ||
        relaxed.kind == SttAlignmentKind.visiblePhrase ||
        relaxed.kind == SttAlignmentKind.sentenceRecovery;
    return preservable ? relaxed : fragmentedYear;
  }

  /// Preserves short browser-STT shards only when every lexical token belongs
  /// to one unambiguous, currently visible year phrase. Numeric fragments are
  /// deliberately excluded from evidence until they equal the written year.
  AlignmentResult? fragmentedYearPreservationAlignment({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    required int? visibleSkipStartIndex,
    required int? maxSkipTargetIndex,
    required SttRecognitionPolicy policy,
    bool strictBulletMode = false,
  }) {
    if (!policy.visibleSkipEnabled ||
        visibleSkipStartIndex == null ||
        maxSkipTargetIndex == null) {
      return null;
    }
    final match = _fragmentedYearMatch(
      script: script,
      transcript: transcript,
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: strictBulletMode,
    );
    if (match == null) return null;
    return match.toAlignment(
      decision: SttAlignmentDecision.wait,
      debugInfo: 'FRAGMENTED_YEAR_CONTEXT_WAITING',
    );
  }

  AlignmentResult? _fragmentedYearRescueAlignment({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    required int? visibleSkipStartIndex,
    required int? maxSkipTargetIndex,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
  }) {
    if (!policy.visibleSkipEnabled ||
        visibleSkipStartIndex == null ||
        maxSkipTargetIndex == null) {
      return null;
    }
    final match = _fragmentedYearMatch(
      script: script,
      transcript: transcript,
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: strictBulletMode,
    );
    if (match == null || !match.hasSpokenNumber) return null;
    if (!policy.visibleSkip.passes(match.evidenceWords)) return null;
    if (!match.numberIsExact &&
        (!match.hasSuffixEvidence ||
            !policy.safetyRecovery.passes(match.suffixEvidenceWords))) {
      return null;
    }
    return match.toAlignment(
      decision: SttAlignmentDecision.advance,
      debugInfo:
          match.numberIsExact
              ? 'FRAGMENTED_YEAR_EXACT_RECOVERY'
              : 'FRAGMENTED_YEAR_MISMATCH_RECOVERY',
    );
  }

  _FragmentedYearMatch? _fragmentedYearMatch({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    required int visibleSkipStartIndex,
    required int maxSkipTargetIndex,
    required bool strictBulletMode,
  }) {
    if (script.isEmpty ||
        transcript.trim().isEmpty ||
        _hasUnsafeNumericStructure(transcript)) {
      return null;
    }
    final visibleStart =
        visibleSkipStartIndex > lastConfirmedIndex
            ? visibleSkipStartIndex
            : lastConfirmedIndex + 1;
    final visibleEnd = maxSkipTargetIndex.clamp(0, script.length - 1).toInt();
    if (visibleStart > visibleEnd) return null;

    final spoken = _surfaceWords(transcript);
    final spokenSpans = SpokenNumberNormalizer.scan(
      spoken.map((word) => word.surface).toList(growable: false),
      allowYearPairs: true,
    );
    if (spokenSpans.length > 1) return null;
    final spokenNumber = spokenSpans.isEmpty ? null : spokenSpans.single;
    if (_hasUnparsedDigits(spoken, spokenNumber)) return null;

    final prefixWords = _lexicalWords(
      spoken.take(spokenNumber?.start ?? spoken.length),
    );
    final suffixWords =
        spokenNumber == null
            ? const <_VisibleTranscriptWord>[]
            : _lexicalWords(spoken.skip(spokenNumber.endExclusive));
    if (prefixWords.isEmpty) return null;

    final visibleScript = script.sublist(visibleStart, visibleEnd + 1);
    final scriptSpans = SpokenNumberNormalizer.scan(
      visibleScript.map((word) => word.raw).toList(growable: false),
      allowYearPairs: true,
    );
    final matches = <_FragmentedYearMatch>[];
    for (final year in scriptSpans) {
      if (year.value.integer < 1000 || year.value.integer > 2999) continue;
      final yearStart = visibleStart + year.start;
      final yearEndExclusive = visibleStart + year.endExclusive;
      final cueIndex = yearStart - 1;
      if (cueIndex < visibleStart || !_isYearCue(script[cueIndex].normalized)) {
        continue;
      }
      final contextStart = _yearContextStart(script, cueIndex, visibleStart);
      final contextEnd = _yearContextEnd(script, yearEndExclusive, visibleEnd);
      final prefix = _matchOrderedWords(
        spoken: prefixWords,
        script: script,
        startIndex: contextStart,
        endIndex: cueIndex,
        strictBulletMode: strictBulletMode,
      );
      if (prefix == null || prefix.indices.isEmpty) continue;
      final suffix = _matchOrderedWords(
        spoken: suffixWords,
        script: script,
        startIndex: yearEndExclusive,
        endIndex: contextEnd,
        strictBulletMode: strictBulletMode,
      );
      if (suffix == null) continue;
      final numberIsExact =
          spokenNumber != null && spokenNumber.value.equivalentTo(year.value);
      matches.add(
        _FragmentedYearMatch(
          prefix: prefix,
          suffix: suffix,
          yearStartIndex: yearStart,
          yearEndExclusive: yearEndExclusive,
          contextStartIndex: contextStart,
          contextEndIndex: contextEnd,
          hasSpokenNumber: spokenNumber != null,
          numberIsExact: numberIsExact,
        ),
      );
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final evidence = b.evidenceWords.length.compareTo(a.evidenceWords.length);
      if (evidence != 0) return evidence;
      return b.quality.compareTo(a.quality);
    });
    if (matches.length > 1 && matches[0].isAmbiguousWith(matches[1])) {
      return null;
    }
    return matches.first;
  }

  _OrderedWordMatch? _matchOrderedWords({
    required List<_VisibleTranscriptWord> spoken,
    required List<ScriptWord> script,
    required int startIndex,
    required int endIndex,
    required bool strictBulletMode,
  }) {
    if (spoken.isEmpty) return const _OrderedWordMatch([], [], 0);
    if (startIndex > endIndex) return null;
    final indices = <int>[];
    final evidence = <String>[];
    var quality = 0.0;
    var cursor = startIndex;
    for (final spokenWord in spoken) {
      var bestIndex = -1;
      var bestSimilarity = 0.0;
      for (var i = cursor; i <= endIndex; i++) {
        final scriptWord = script[i];
        if (scriptWord.isNewline || scriptWord.normalized.isEmpty) continue;
        final similarity = WordAligner.spokenWordSimilarity(
          spokenWord.normalized,
          scriptWord,
        );
        final threshold = strictBulletMode ? 0.82 : 0.72;
        if (similarity >= threshold && similarity > bestSimilarity) {
          bestIndex = i;
          bestSimilarity = similarity;
          if (similarity >= 0.999) break;
        }
      }
      if (bestIndex < 0) return null;
      indices.add(bestIndex);
      evidence.add(spokenWord.normalized);
      quality += bestSimilarity;
      cursor = bestIndex + 1;
    }
    return _OrderedWordMatch(indices, evidence, quality);
  }

  List<_VisibleTranscriptWord> _lexicalWords(
    Iterable<_VisibleTranscriptWord> words,
  ) =>
      words.where((word) => word.normalized.isNotEmpty).toList(growable: false);

  bool _hasUnparsedDigits(
    List<_VisibleTranscriptWord> words,
    SpokenNumberSpan? parsed,
  ) {
    for (var i = 0; i < words.length; i++) {
      if (!RegExp(r'\d').hasMatch(words[i].surface)) continue;
      if (parsed == null || i < parsed.start || i >= parsed.endExclusive) {
        return true;
      }
    }
    return false;
  }

  bool _hasUnsafeNumericStructure(String transcript) {
    if (RegExp(r'[:/\\%$₪]').hasMatch(transcript)) return true;
    if (RegExp(r'\s[-–—−]\s').hasMatch(transcript)) return true;
    return RegExp(r'\d\s*[-–—−]\s*\d').hasMatch(transcript);
  }

  bool _isYearCue(String normalized) => const {
    'בשנת',
    'שנת',
    'לשנת',
    'משנת',
    'בשנה',
    'שנה',
    'year',
  }.contains(normalized);

  int _yearContextStart(
    List<ScriptWord> script,
    int cueIndex,
    int visibleStart,
  ) {
    var start = cueIndex;
    var words = 0;
    for (var i = cueIndex - 1; i >= visibleStart && words < 6; i--) {
      if (script[i].isNewline || _isHardBoundary(script[i].raw)) break;
      if (script[i].normalized.isNotEmpty) words++;
      start = i;
    }
    return start;
  }

  int _yearContextEnd(
    List<ScriptWord> script,
    int yearEndExclusive,
    int visibleEnd,
  ) {
    var end = yearEndExclusive - 1;
    var words = 0;
    for (var i = yearEndExclusive; i <= visibleEnd && words < 6; i++) {
      if (script[i].isNewline) break;
      end = i;
      if (script[i].normalized.isNotEmpty) words++;
      if (_isHardBoundary(script[i].raw)) break;
    }
    return end;
  }

  bool _isHardBoundary(String raw) => RegExp(r'[.!?;:]$').hasMatch(raw.trim());

  List<_VisibleTranscriptWord> _surfaceWords(String transcript) {
    final words = <_VisibleTranscriptWord>[];
    for (final raw in transcript.split(RegExp(r'\s+'))) {
      final surface = raw.trim();
      if (surface.isEmpty) continue;
      final normalized = surface.normalizeForMatching();
      final comparisonKey =
          normalized.isNotEmpty
              ? 'word:$normalized'
              : 'surface:${surface.toLowerCase()}';
      words.add(
        _VisibleTranscriptWord(
          surface: surface,
          comparisonKey: comparisonKey,
          normalized: normalized,
        ),
      );
    }
    return words;
  }

  List<String> _normalizedWords(String transcript) => _surfaceWords(transcript)
      .map((word) => word.normalized)
      .where((word) => word.isNotEmpty)
      .toList(growable: false);

  String _joinSurface(List<_VisibleTranscriptWord> words) =>
      words.map((word) => word.surface).join(' ');

  List<_VisibleTranscriptWord> _capWords(
    List<_VisibleTranscriptWord> words,
    int maxWords,
  ) {
    final safeMax = maxWords.clamp(4, 40).toInt();
    if (words.length <= safeMax) return words;
    return words.sublist(words.length - safeMax);
  }

  List<_VisibleTranscriptWord>? _replaceTrailingNumberRevision(
    List<_VisibleTranscriptWord> pendingWords,
    List<_VisibleTranscriptWord> currentWords,
  ) {
    final pendingSpans = SpokenNumberNormalizer.scan(
      pendingWords.map((word) => word.surface).toList(growable: false),
    );
    final currentSpans = SpokenNumberNormalizer.scan(
      currentWords.map((word) => word.surface).toList(growable: false),
    );
    if (pendingSpans.isEmpty || currentSpans.length != 1) return null;
    final pendingTail = pendingSpans.last;
    final currentNumber = currentSpans.single;
    if (pendingTail.endExclusive != pendingWords.length ||
        currentNumber.start != 0 ||
        currentNumber.endExclusive != currentWords.length ||
        !_isPlausibleNumericRevision(pendingTail, currentNumber)) {
      return null;
    }
    return [...pendingWords.take(pendingTail.start), ...currentWords];
  }

  String? _crossShardYearPairAlternative({
    required String pendingTranscript,
    required String transcript,
    required String normallyMerged,
    int maxWords = 18,
  }) {
    final pendingWords = _surfaceWords(pendingTranscript);
    final currentWords = _surfaceWords(transcript);
    if (pendingWords.isEmpty || currentWords.isEmpty) return null;

    final normalSpans = SpokenNumberNormalizer.scan(
      _surfaceWords(
        normallyMerged,
      ).map((word) => word.surface).toList(growable: false),
      allowYearPairs: true,
    );
    if (normalSpans.any(
      (span) => span.value.kind == SpokenNumberKind.yearPair,
    )) {
      return null;
    }

    final directWords = _capWords([...pendingWords, ...currentWords], maxWords);
    if (currentWords.length >= directWords.length) return null;
    final boundary = directWords.length - currentWords.length;
    final directSpans = SpokenNumberNormalizer.scan(
      directWords.map((word) => word.surface).toList(growable: false),
      allowYearPairs: true,
    );
    final crossingPairs = directSpans
        .where(
          (span) =>
              span.value.kind == SpokenNumberKind.yearPair &&
              span.start < boundary &&
              span.endExclusive > boundary,
        )
        .toList(growable: false);
    if (crossingPairs.length != 1) return null;
    return _joinSurface(directWords);
  }

  bool _isPlausibleNumericRevision(
    SpokenNumberSpan pending,
    SpokenNumberSpan current,
  ) {
    if (pending.value.equivalentTo(current.value)) return true;
    if (pending.source != SpokenNumberSource.digits ||
        current.source != SpokenNumberSource.digits) {
      return false;
    }
    final pendingDigits = pending.value.exactDigits;
    final currentDigits = current.value.exactDigits;
    if (pendingDigits == null || currentDigits == null) return false;
    final shorter =
        pendingDigits.length < currentDigits.length
            ? pendingDigits
            : currentDigits;
    if (shorter.length < 2) return false;
    return pendingDigits.startsWith(shorter) &&
        currentDigits.startsWith(shorter);
  }

  bool _endsWith(
    List<_VisibleTranscriptWord> source,
    List<_VisibleTranscriptWord> suffix,
  ) {
    if (suffix.isEmpty || suffix.length > source.length) return false;
    return _sameWords(source.sublist(source.length - suffix.length), suffix);
  }

  bool _sameWords(
    List<_VisibleTranscriptWord> a,
    List<_VisibleTranscriptWord> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].comparisonKey != b[i].comparisonKey) return false;
    }
    return true;
  }
}

class _VisibleTranscriptWord {
  final String surface;
  final String comparisonKey;
  final String normalized;

  const _VisibleTranscriptWord({
    required this.surface,
    required this.comparisonKey,
    required this.normalized,
  });
}

class _OrderedWordMatch {
  final List<int> indices;
  final List<String> evidenceWords;
  final double quality;

  const _OrderedWordMatch(this.indices, this.evidenceWords, this.quality);
}

class _FragmentedYearMatch {
  final _OrderedWordMatch prefix;
  final _OrderedWordMatch suffix;
  final int yearStartIndex;
  final int yearEndExclusive;
  final int contextStartIndex;
  final int contextEndIndex;
  final bool hasSpokenNumber;
  final bool numberIsExact;

  const _FragmentedYearMatch({
    required this.prefix,
    required this.suffix,
    required this.yearStartIndex,
    required this.yearEndExclusive,
    required this.contextStartIndex,
    required this.contextEndIndex,
    required this.hasSpokenNumber,
    required this.numberIsExact,
  });

  List<String> get evidenceWords => [
    ...prefix.evidenceWords,
    if (numberIsExact) 'num',
    ...suffix.evidenceWords,
  ];

  List<String> get suffixEvidenceWords => suffix.evidenceWords;
  bool get hasSuffixEvidence => suffix.evidenceWords.isNotEmpty;
  double get quality =>
      prefix.quality + suffix.quality + (numberIsExact ? 1 : 0);

  bool isAmbiguousWith(_FragmentedYearMatch other) =>
      evidenceWords.length == other.evidenceWords.length &&
      (quality - other.quality).abs() <= 0.08;

  AlignmentResult toAlignment({
    required SttAlignmentDecision decision,
    required String debugInfo,
  }) {
    final matched = <int>[
      ...prefix.indices,
      if (numberIsExact)
        for (var i = yearStartIndex; i < yearEndExclusive; i++) i,
      ...suffix.indices,
    ];
    final target =
        matched.isEmpty
            ? contextStartIndex
            : matched.reduce((a, b) => a > b ? a : b);
    final confidence =
        evidenceWords.isEmpty
            ? 0.0
            : (quality / evidenceWords.length).clamp(0.0, 1.0).toDouble();
    return AlignmentResult(
      target,
      confidence,
      debugInfo,
      decision,
      numberIsExact
          ? SttAlignmentKind.numberPhrase
          : SttAlignmentKind.numberMismatchRecovery,
      SttThresholdFamily.visibleSkip,
      matched,
      evidenceWords,
      contextStartIndex,
      contextEndIndex,
    );
  }
}
