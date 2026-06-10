part of 'teleprompter_screen.dart';

class _PresenterDecorationPainter extends CustomPainter {
  final GlobalKey contentKey;
  final List<GlobalKey> wordKeys;
  final List<ScriptWord> words;
  final int confirmedWordIndex;
  final bool isManualMode;
  final MarkupDecorationType type;
  final double gapTolerance;
  final Color underlineColor;

  const _PresenterDecorationPainter({
    required this.contentKey,
    required this.wordKeys,
    required this.words,
    required this.confirmedWordIndex,
    required this.isManualMode,
    required this.type,
    required this.gapTolerance,
    this.underlineColor = const Color(0xFFFFFFFF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final contentContext = contentKey.currentContext;
    final contentBox = contentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null || !contentBox.attached) return;

    if (type == MarkupDecorationType.background) {
      // Paint each highlight run on its own. A run's wrapped lines connect into
      // one rounded block, but two separate highlights that share a color and
      // sit on adjacent lines stay distinct (so spacing reads evenly).
      final runs = _highlightRuns();
      final sharedLanes = _highlightLanesForRuns(runs, size, contentBox);
      for (final run in runs) {
        _paintHighlightSegments(canvas, size, contentBox, run, sharedLanes);
      }
      return;
    }

    final underlineRects = <Rect>[];
    for (final word in words) {
      if (word.isNewline ||
          !word.isUnderline ||
          word.index >= wordKeys.length) {
        continue;
      }
      final rect = _rectForWord(word.index, contentBox);
      if (rect != null) underlineRects.add(rect);
    }
    final paint = Paint()
      ..color = underlineColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final rect in MarkupDecorationBoxMerger.merge(
      underlineRects,
      rowTolerance: 8,
      gapTolerance: gapTolerance,
    )) {
      final y = rect.bottom - (paint.strokeWidth * 0.5);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  void _paintHighlightSegments(
    Canvas canvas,
    Size size,
    RenderBox contentBox,
    List<ScriptWord> run,
    List<Rect> sharedLanes,
  ) {
    final paintedWords = <({Color color, Rect rect})>[];
    for (final word in run) {
      final highlight = word.highlight;
      if (highlight == null) continue;
      final rect = _rectForWord(word.index, contentBox);
      if (rect == null) continue;
      paintedWords
          .add((color: _effectiveHighlightColor(word, highlight), rect: rect));
    }
    if (paintedWords.isEmpty) return;
    final runMerged = MarkupDecorationBoxMerger.merge(
      [for (final word in paintedWords) word.rect],
      rowTolerance: 8,
      gapTolerance: gapTolerance,
    );
    final runBands = _applyRowLanes(runMerged, sharedLanes);

    Color? segmentColor;
    final segmentRects = <Rect>[];

    void flushSegment() {
      final color = segmentColor;
      if (color == null || color.a <= 0 || segmentRects.isEmpty) {
        segmentRects.clear();
        segmentColor = null;
        return;
      }
      final merged = MarkupDecorationBoxMerger.merge(
        segmentRects,
        rowTolerance: 8,
        gapTolerance: gapTolerance,
      );
      final bands = _applyRowLanes(merged, sharedLanes);
      HighlightBandPainter.paintConnectedRegion(
        canvas,
        bands,
        color,
        size,
        radius: HighlightBandPainter.suggestedRadius(bands),
        connectorGapRatio: 0.95,
        maxConnectorGap: _maxPresenterConnectorGap(bands),
      );
      segmentRects.clear();
      segmentColor = null;
    }

    for (final word in paintedWords) {
      final color = word.color;
      if (segmentColor != null && segmentColor != color) {
        flushSegment();
      }
      segmentColor = color;
      segmentRects.add(word.rect);
    }
    flushSegment();
    _paintRunSeams(canvas, runBands, paintedWords);
  }

  List<Rect> _highlightLanesForRuns(
    List<List<ScriptWord>> runs,
    Size size,
    RenderBox contentBox,
  ) {
    final rects = <Rect>[];
    for (final run in runs) {
      for (final word in run) {
        final rect = _rectForWord(word.index, contentBox);
        if (rect != null) rects.add(rect);
      }
    }
    if (rects.isEmpty) return const [];
    final merged = MarkupDecorationBoxMerger.merge(
      rects,
      rowTolerance: 8,
      gapTolerance: gapTolerance,
    );
    return _presenterBackgroundBands(merged, size);
  }

  Color _effectiveHighlightColor(ScriptWord word, Color highlight) {
    if (!isManualMode && word.index < confirmedWordIndex) {
      return highlight.withValues(alpha: highlight.a * 0.15);
    }
    return highlight;
  }

  /// Groups consecutive highlighted words into runs. Plain newlines do not
  /// break a run because a highlighted paragraph can wrap through block
  /// boundaries; real non-highlighted words still break the run.
  List<List<ScriptWord>> _highlightRuns() {
    final runs = <List<ScriptWord>>[];
    List<ScriptWord>? current;
    int? prevIndex;
    Color? prevColor;
    for (final word in words) {
      if (word.isNewline) continue;
      final color = word.highlight;
      if (word.index >= wordKeys.length) {
        current = null;
        prevIndex = null;
        prevColor = null;
        continue;
      }
      if (color == null) {
        if (current != null &&
            HighlightBandPainter.isIgnorableHighlightSeparator(
              raw: word.raw,
              normalized: word.normalized,
            )) {
          continue;
        }
        current = null;
        prevIndex = null;
        prevColor = null;
        continue;
      }
      final contiguous =
          prevIndex != null && word.index > prevIndex && prevColor == color;
      if (current == null || !contiguous) {
        current = <ScriptWord>[];
        runs.add(current);
      }
      current.add(word);
      prevIndex = word.index;
      prevColor = color;
    }
    return runs;
  }

  List<Rect> _presenterBackgroundBands(List<Rect> bands, Size size) {
    final sorted =
        bands.where((band) => band.width > 0 && band.height > 0).toList()
          ..sort((a, b) {
            final top = a.top.compareTo(b.top);
            return top != 0 ? top : a.left.compareTo(b.left);
          });
    if (sorted.isEmpty) return const [];

    return HighlightBandPainter.textLaneBands(
      sorted,
      size,
      topPaddingRatio: 0.15,
      bottomPaddingRatio: 0.15,
      minHeight: 8.0,
      maxHeight: 240.0,
    );
  }

  List<Rect> _applyRowLanes(List<Rect> bands, List<Rect> lanes) {
    if (bands.isEmpty || lanes.isEmpty) return const [];
    return [
      for (final band in bands)
        Rect.fromLTRB(
          band.left,
          _laneForBand(band, lanes).top,
          band.right,
          _laneForBand(band, lanes).bottom,
        ),
    ];
  }

  void _paintRunSeams(
    Canvas canvas,
    List<Rect> bands,
    List<({Color color, Rect rect})> paintedWords,
  ) {
    if (bands.length < 2 || paintedWords.isEmpty) return;
    final sorted = [...bands]..sort((a, b) => a.top.compareTo(b.top));
    final medianHeight = HighlightBandPainter.medianBandHeight(sorted);
    final maxGap = (medianHeight * 0.95)
        .clamp(2.0, _maxPresenterConnectorGap(sorted))
        .toDouble();
    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];
      final gap = next.top - current.bottom;
      if (gap <= 0 || gap > maxGap) continue;
      final left = current.left > next.left ? current.left : next.left;
      final right = current.right < next.right ? current.right : next.right;
      if (right - left <= 3.0) continue;
      final top = current.bottom.floorToDouble();
      final bottom = next.top.ceilToDouble();
      if (bottom <= top) continue;
      final currentColor = _colorForBand(current, paintedWords);
      final nextColor = _colorForBand(next, paintedWords);
      final seamColor =
          nextColor.a >= currentColor.a ? nextColor : currentColor;
      if (seamColor.a <= 0) continue;
      canvas.drawRect(
        Rect.fromLTRB(left.floorToDouble(), top, right.ceilToDouble(), bottom),
        Paint()..color = seamColor,
      );
    }
  }

  double _maxPresenterConnectorGap(List<Rect> bands) {
    if (bands.isEmpty) return 18.0;
    final medianHeight = HighlightBandPainter.medianBandHeight(bands);
    return (medianHeight * 1.1).clamp(18.0, 96.0).toDouble();
  }

  Color _colorForBand(Rect band, List<({Color color, Rect rect})> words) {
    var best = words.first;
    var bestScore = double.negativeInfinity;
    for (final word in words) {
      final overlapTop = band.top > word.rect.top ? band.top : word.rect.top;
      final overlapBottom =
          band.bottom < word.rect.bottom ? band.bottom : word.rect.bottom;
      final overlap =
          overlapBottom > overlapTop ? overlapBottom - overlapTop : 0.0;
      final centerDistance = (band.center.dy - word.rect.center.dy).abs();
      final score = (overlap * 1000.0) - centerDistance;
      if (score > bestScore) {
        bestScore = score;
        best = word;
      }
    }
    return best.color;
  }

  Rect _laneForBand(Rect band, List<Rect> lanes) {
    var bestLane = lanes.first;
    var bestScore = double.negativeInfinity;
    for (final lane in lanes) {
      final overlapTop = band.top > lane.top ? band.top : lane.top;
      final overlapBottom =
          band.bottom < lane.bottom ? band.bottom : lane.bottom;
      final overlap =
          overlapBottom > overlapTop ? overlapBottom - overlapTop : 0.0;
      final centerDistance = (band.center.dy - lane.center.dy).abs();
      final score = (overlap * 1000.0) - centerDistance;
      if (score > bestScore) {
        bestScore = score;
        bestLane = lane;
      }
    }
    return bestLane;
  }

  Rect? _rectForWord(int index, RenderBox contentBox) {
    final context = wordKeys[index].currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: contentBox);
    return topLeft & box.size;
  }

  @override
  bool shouldRepaint(covariant _PresenterDecorationPainter oldDelegate) => true;
}
