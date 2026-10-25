part of 'stt_visible_skip_context_service.dart';

extension _VisibleContextRevisions on SttVisibleSkipContextService {
  /// Two unchanged lexical anchors distinguish a revised tail from a new
  /// numeric shard ("addition started 2" -> "addition started 2000").
  List<_VisibleTranscriptWord>? _replaceAnchoredTail(
    List<_VisibleTranscriptWord> previous,
    List<_VisibleTranscriptWord> current,
  ) {
    if (previous.length < 3 || previous.length != current.length) return null;
    final prefixLength = previous.length - 1;
    if (!_sameWords(
      previous.sublist(0, prefixLength),
      current.sublist(0, prefixLength),
    )) {
      return null;
    }
    final anchors =
        previous
            .take(prefixLength)
            .where(
              (word) =>
                  word.normalized.isNotEmpty &&
                  !RegExp(r'\d').hasMatch(word.normalized),
            )
            .length;
    if (anchors < 2) return null;
    final oldTail = previous.last.normalized;
    final newTail = current.last.normalized;
    if (oldTail.isEmpty || newTail.isEmpty) return null;
    final digits = RegExp(r'^\d+$');
    final numeric = digits.hasMatch(oldTail) && digits.hasMatch(newTail);
    if (!numeric && (oldTail.length < 3 || newTail.length < 3)) return null;
    if (oldTail.startsWith(newTail) || newTail.startsWith(oldTail)) {
      return current;
    }
    return null;
  }

  /// A not-yet-complete integer may retain lexical context, but is NEVER
  /// counted or stripped to authorize movement. Rescue rechecks the full number.
  AlignmentResult? _preserveBeforeNumericTail({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    required int? visibleSkipStartIndex,
    required int? maxSkipTargetIndex,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
  }) {
    if (_hasUnsafeNumericStructure(transcript)) return null;
    final words = _surfaceWords(transcript);
    if (words.length < 3 ||
        !RegExp(r'^\d+[.,!?]?$').hasMatch(words.last.surface)) {
      return null;
    }
    final prefix = words.sublist(0, words.length - 1);
    // Restrict to one plain numeric token: dates/ranges/decimals and a second
    // spoken number must not be laundered into lexical evidence.
    if (SpokenNumberNormalizer.scan(
      prefix.map((w) => w.surface).toList(),
    ).isNotEmpty) {
      return null;
    }
    return preservationAlignment(
      script: script,
      transcript: _joinSurface(prefix),
      lastConfirmedIndex: lastConfirmedIndex,
      visibleSkipStartIndex: visibleSkipStartIndex,
      maxSkipTargetIndex: maxSkipTargetIndex,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
  }
}
