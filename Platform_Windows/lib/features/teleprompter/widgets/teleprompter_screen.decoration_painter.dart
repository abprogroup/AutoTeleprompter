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
        for (final rect in MarkupDecorationBoxMerger.merge(
          entry.value,
          rowTolerance: 8,
          gapTolerance: gapTolerance,
        )) {
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
