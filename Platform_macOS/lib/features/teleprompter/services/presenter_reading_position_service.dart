import 'dart:math' as math;

class PresenterReadingWordBounds {
  const PresenterReadingWordBounds({
    required this.index,
    required this.leading,
    required this.trailing,
  });

  final int index;
  final double leading;
  final double trailing;

  double get center => (leading + trailing) / 2.0;
  double get extent => (trailing - leading).abs();
}

class PresenterReadingPositionService {
  const PresenterReadingPositionService._();

  /// Selects the first script word in the visual row at the reading line.
  ///
  /// Reading progress is a row decision. A nearest-pixel selector can skip
  /// several rows when a large RTL row or highlight block has a closer edge.
  static int? wordIndexAtReadingLine({
    required Iterable<PresenterReadingWordBounds> words,
    required double readingLine,
  }) {
    final candidates = words
        .where((word) =>
            word.index >= 0 &&
            word.leading.isFinite &&
            word.trailing.isFinite &&
            word.trailing >= word.leading)
        .toList();
    if (candidates.isEmpty) return null;

    final crossing = candidates
        .where((word) =>
            word.leading <= readingLine && word.trailing >= readingLine)
        .toList();
    if (crossing.isNotEmpty) {
      final seed = crossing.reduce((best, word) {
        final bestDistance = (best.center - readingLine).abs();
        final wordDistance = (word.center - readingLine).abs();
        return wordDistance < bestDistance ? word : best;
      });
      return _firstWordIndexInVisualRow(candidates, seed);
    }

    final after = candidates.where((word) => word.leading > readingLine);
    if (after.isNotEmpty) {
      final seed = after.reduce(
        (best, word) => word.leading < best.leading ? word : best,
      );
      return _firstWordIndexInVisualRow(candidates, seed);
    }

    final before = candidates.where((word) => word.trailing < readingLine);
    if (before.isEmpty) return null;
    final seed = before.reduce(
      (best, word) => word.trailing > best.trailing ? word : best,
    );
    return _firstWordIndexInVisualRow(candidates, seed);
  }

  static int _firstWordIndexInVisualRow(
    List<PresenterReadingWordBounds> candidates,
    PresenterReadingWordBounds seed,
  ) {
    final rowTolerance = math.max(18.0, seed.extent * 0.65);
    var first = seed.index;
    for (final word in candidates) {
      if ((word.center - seed.center).abs() <= rowTolerance &&
          word.index < first) {
        first = word.index;
      }
    }
    return first;
  }
}
