part of 'teleprompter_screen.dart';

class _PresenterDecorationPainter extends CustomPainter {
  final GlobalKey contentKey;
  final List<GlobalKey> wordKeys;
  final List<ScriptWord> words;
  final int confirmedWordIndex;
  final bool isManualMode;
  final MarkupDecorationType type;
  final double gapTolerance;

  const _PresenterDecorationPainter({
    required this.contentKey,
    required this.wordKeys,
    required this.words,
    required this.confirmedWordIndex,
    required this.isManualMode,
    required this.type,
    required this.gapTolerance,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final contentContext = contentKey.currentContext;
    final contentBox = contentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null || !contentBox.attached) return;

    if (type == MarkupDecorationType.background) {
      final rectsByColor = <Color, List<Rect>>{};
      for (final word in words) {
        if (word.isNewline || word.index >= wordKeys.length) continue;
        final highlight = word.highlight;
        if (highlight == null) continue;
        final color = !isManualMode && word.index < confirmedWordIndex
            ? highlight.withValues(alpha: highlight.a * 0.15)
            : highlight;
        final rect = _rectForWord(word.index, contentBox);
        if (rect == null) continue;
        rectsByColor.putIfAbsent(color, () => <Rect>[]).add(rect);
      }
      final paint = Paint()..style = PaintingStyle.fill;
      for (final entry in rectsByColor.entries) {
        if (entry.key.a <= 0) continue;
        paint.color = entry.key;
        final merged = MarkupDecorationBoxMerger.merge(
          entry.value,
          rowTolerance: 8,
          gapTolerance: gapTolerance,
        );
        for (final rect in _presenterBackgroundBands(merged, size)) {
          final radius = Radius.circular((rect.height * 0.10).clamp(2.0, 8.0));
          canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
        }
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
      ..color = Colors.white
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

  List<Rect> _presenterBackgroundBands(List<Rect> bands, Size size) {
    final sorted = bands
        .where((band) => band.width > 0 && band.height > 0)
        .toList()
      ..sort((a, b) {
        final top = a.top.compareTo(b.top);
        return top != 0 ? top : a.left.compareTo(b.left);
      });
    if (sorted.isEmpty) return const [];

    final medianHeight = _medianHeight(sorted);
    final pad = (medianHeight * 0.07).clamp(3.0, 8.0).toDouble();
    final overlap = (medianHeight * 0.035).clamp(1.5, 4.0).toDouble();
    final maxAdjacentDistance = medianHeight * 1.75;
    final bridgeGapLimit = medianHeight * 0.65;
    final painted = [
      for (final band in sorted)
        Rect.fromLTRB(
          band.left,
          (band.top - pad).clamp(0.0, size.height).toDouble(),
          band.right,
          (band.bottom + pad).clamp(0.0, size.height).toDouble(),
        ),
    ];

    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];
      final centerDistance = next.center.dy - current.center.dy;
      if (centerDistance <= medianHeight * 0.25 ||
          centerDistance > maxAdjacentDistance) {
        continue;
      }
      final rowGap = next.top - current.bottom;
      if (rowGap > bridgeGapLimit) continue;

      final boundary = (current.bottom + next.top) / 2.0;
      if (boundary <= painted[i].top || boundary >= painted[i + 1].bottom) {
        continue;
      }
      painted[i] = Rect.fromLTRB(
        painted[i].left,
        painted[i].top,
        painted[i].right,
        (boundary + overlap).clamp(0.0, size.height).toDouble(),
      );
      painted[i + 1] = Rect.fromLTRB(
        painted[i + 1].left,
        (boundary - overlap).clamp(0.0, size.height).toDouble(),
        painted[i + 1].right,
        painted[i + 1].bottom,
      );
    }

    return painted;
  }

  double _medianHeight(List<Rect> rects) {
    final heights = rects.map((rect) => rect.height).toList()..sort();
    if (heights.isEmpty) return 1.0;
    return heights[heights.length ~/ 2].clamp(1.0, double.infinity).toDouble();
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
