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

  /// Finds a geometry anchor near [axis] without walking the full script.
  ///
  /// Presenter words are laid out in script order, so their normalized axis
  /// bounds are monotonic even when the presenter is rotated or mirrored. A
  /// small null-probe radius tolerates newline/layout gaps while keeping work
  /// bounded for long scripts.
  static int? anchorIndexNearAxis({
    required int wordCount,
    required double axis,
    required PresenterReadingWordBounds? Function(int index) boundsAt,
    int maxNullProbeDistance = 12,
  }) {
    if (wordCount <= 0 || !axis.isFinite || maxNullProbeDistance < 0) {
      return null;
    }

    var low = 0;
    var high = wordCount - 1;
    int? firstAtOrAfter;
    int? lastBefore;

    while (low <= high) {
      final midpoint = low + ((high - low) ~/ 2);
      final probe = _nearestAvailableBounds(
        midpoint: midpoint,
        low: low,
        high: high,
        maxDistance: maxNullProbeDistance,
        boundsAt: boundsAt,
      );
      if (probe == null) break;

      final position = probe.position;
      final bounds = probe.bounds;
      if (bounds.trailing < axis) {
        lastBefore = position;
        low = position + 1;
      } else {
        firstAtOrAfter = position;
        high = position - 1;
      }
    }

    return firstAtOrAfter ?? lastBefore;
  }

  /// Returns a half-open local scan range centered on [anchorIndex].
  static ({int start, int end}) boundedRangeAround({
    required int wordCount,
    required int anchorIndex,
    int padding = 120,
  }) {
    if (wordCount <= 0) return (start: 0, end: 0);
    final safePadding = math.max(0, padding);
    final anchor = anchorIndex.clamp(0, wordCount - 1);
    return (
      start: math.max(0, anchor - safePadding),
      end: math.min(wordCount, anchor + safePadding + 1),
    );
  }

  /// Selects the first script word in the visual row at the reading line.
  ///
  /// Reading progress is a row decision. A nearest-pixel selector can skip
  /// several rows when a large RTL row or highlight block has a closer edge.
  static int? wordIndexAtReadingLine({
    required Iterable<PresenterReadingWordBounds> words,
    required double readingLine,
  }) {
    final candidates =
        words
            .where(
              (word) =>
                  word.index >= 0 &&
                  word.leading.isFinite &&
                  word.trailing.isFinite &&
                  word.trailing >= word.leading,
            )
            .toList();
    if (candidates.isEmpty) return null;

    final crossing =
        candidates
            .where(
              (word) =>
                  word.leading <= readingLine && word.trailing >= readingLine,
            )
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

  static ({int position, PresenterReadingWordBounds bounds})?
  _nearestAvailableBounds({
    required int midpoint,
    required int low,
    required int high,
    required int maxDistance,
    required PresenterReadingWordBounds? Function(int index) boundsAt,
  }) {
    for (var distance = 0; distance <= maxDistance; distance++) {
      final forward = midpoint + distance;
      if (forward <= high) {
        final bounds = boundsAt(forward);
        if (_isValidBounds(bounds)) {
          return (position: forward, bounds: bounds!);
        }
      }

      if (distance == 0) continue;
      final backward = midpoint - distance;
      if (backward >= low) {
        final bounds = boundsAt(backward);
        if (_isValidBounds(bounds)) {
          return (position: backward, bounds: bounds!);
        }
      }
    }
    return null;
  }

  static bool _isValidBounds(PresenterReadingWordBounds? bounds) {
    return bounds != null &&
        bounds.leading.isFinite &&
        bounds.trailing.isFinite &&
        bounds.trailing >= bounds.leading;
  }
}
