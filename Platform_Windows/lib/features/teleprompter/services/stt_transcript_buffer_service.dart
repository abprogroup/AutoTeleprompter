import '../../../core/extensions/string_extensions.dart';

class SttTranscriptBuffer {
  final int transcriptFloor;
  final List<String> spokenWords;
  final List<String> freshWords;
  final String recentTranscript;
  final bool resetFloor;

  const SttTranscriptBuffer({
    required this.transcriptFloor,
    required this.spokenWords,
    required this.freshWords,
    required this.recentTranscript,
    required this.resetFloor,
  });

  bool get hasFreshSpeech => freshWords.isNotEmpty;
}

class SttTranscriptBufferService {
  const SttTranscriptBufferService();

  SttTranscriptBuffer update({
    required String rawTranscript,
    required int transcriptFloor,
    int recentWordWindow = 12,
    bool cumulativeReplacement = false,
    List<String> cumulativeBaselineWords = const <String>[],
    bool cumulativeFinal = false,
  }) {
    final spokenWords = rawTranscript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    // Browser result shards may legitimately start a new phrase. Whisper
    // partials are full revisable replacements, so their consumed boundary is
    // remapped through anchored token edits instead of trusting a raw index.
    final resetFloor =
        !cumulativeReplacement && spokenWords.length < transcriptFloor;
    final safeFloor =
        resetFloor
            ? 0
            : cumulativeReplacement
            ? _remapCumulativeFloor(
              cumulativeBaselineWords,
              spokenWords,
              transcriptFloor,
              finalSnapshot: cumulativeFinal,
            )
            : transcriptFloor;
    final freshWords =
        safeFloor > spokenWords.length
            ? const <String>[]
            : safeFloor > 0
            ? spokenWords.sublist(safeFloor)
            : spokenWords;
    final safeWindow = recentWordWindow.clamp(1, 240).toInt();
    final recentWords =
        freshWords.length > safeWindow
            ? freshWords.sublist(freshWords.length - safeWindow)
            : freshWords;
    final recentTranscript = recentWords.join(' ');
    return SttTranscriptBuffer(
      transcriptFloor: safeFloor,
      spokenWords: spokenWords,
      freshWords: freshWords,
      recentTranscript: recentTranscript,
      resetFloor: resetFloor,
    );
  }

  int _remapCumulativeFloor(
    List<String> previous,
    List<String> current,
    int rawFloor, {
    required bool finalSnapshot,
  }) {
    final floor = rawFloor.clamp(0, previous.length).toInt();
    if (previous.isEmpty || floor == 0) {
      return floor.clamp(0, current.length).toInt();
    }

    var commonPrefix = 0;
    final shortest =
        previous.length < current.length ? previous.length : current.length;
    while (commonPrefix < shortest &&
        previous[commonPrefix] == current[commonPrefix]) {
      commonPrefix++;
    }

    var commonSuffix = 0;
    while (commonSuffix < previous.length - commonPrefix &&
        commonSuffix < current.length - commonPrefix &&
        previous[previous.length - 1 - commonSuffix] ==
            current[current.length - 1 - commonSuffix]) {
      commonSuffix++;
    }

    final previousChangeEnd = previous.length - commonSuffix;
    final currentChangeEnd = current.length - commonSuffix;
    if (floor <= commonPrefix) return floor.clamp(0, current.length).toInt();
    if (finalSnapshot &&
        commonSuffix == 0 &&
        commonPrefix < floor &&
        floor >= previousChangeEnd) {
      // A final phrase boundary resolves an otherwise ambiguous rewritten
      // tail. Keep the stable prefix consumed and expose the settled tail.
      return commonPrefix.clamp(0, current.length).toInt();
    }
    if (floor >= previousChangeEnd) {
      final shifted = floor + currentChangeEnd - previousChangeEnd;
      return shifted.clamp(commonPrefix, current.length).toInt();
    }

    final consumedChange = previous.sublist(commonPrefix, floor);
    final currentChange = current.sublist(commonPrefix, currentChangeEnd);
    if (consumedChange.length > 96 || currentChange.length > 96) {
      // An unbounded or unanchored rewrite is ambiguous. Consume this snapshot
      // and wait for the next stable append instead of replaying old speech.
      final boundary = finalSnapshot ? commonPrefix : currentChangeEnd;
      return boundary.clamp(commonPrefix, current.length).toInt();
    }

    final mappedEnd = _lastLcsMatchEnd(consumedChange, currentChange);
    if (mappedEnd == null) {
      final boundary = finalSnapshot ? commonPrefix : currentChangeEnd;
      return boundary.clamp(commonPrefix, current.length).toInt();
    }
    return (commonPrefix + mappedEnd).clamp(0, current.length).toInt();
  }

  int? _lastLcsMatchEnd(List<String> previous, List<String> current) {
    if (previous.isEmpty || current.isEmpty) return null;
    final lengths = List<List<int>>.generate(
      previous.length + 1,
      (_) => List<int>.filled(current.length + 1, 0),
    );
    for (var oldIndex = previous.length - 1; oldIndex >= 0; oldIndex--) {
      for (var newIndex = current.length - 1; newIndex >= 0; newIndex--) {
        lengths[oldIndex][newIndex] =
            previous[oldIndex] == current[newIndex]
                ? lengths[oldIndex + 1][newIndex + 1] + 1
                : lengths[oldIndex + 1][newIndex] >=
                    lengths[oldIndex][newIndex + 1]
                ? lengths[oldIndex + 1][newIndex]
                : lengths[oldIndex][newIndex + 1];
      }
    }
    if (lengths[0][0] == 0) return null;

    var oldIndex = 0;
    var newIndex = 0;
    int? lastMatchEnd;
    while (oldIndex < previous.length && newIndex < current.length) {
      if (previous[oldIndex] == current[newIndex] &&
          lengths[oldIndex][newIndex] ==
              lengths[oldIndex + 1][newIndex + 1] + 1) {
        lastMatchEnd = newIndex + 1;
        oldIndex++;
        newIndex++;
      } else if (lengths[oldIndex + 1][newIndex] >=
          lengths[oldIndex][newIndex + 1]) {
        oldIndex++;
      } else {
        // Prefer earlier positions in the new snapshot when words repeat.
        newIndex++;
      }
    }
    return lastMatchEnd;
  }
}
