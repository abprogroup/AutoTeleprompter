part of 'script_editor_screen.dart';

class _VerticalLayoutInfo {
  final TextPainter painter;
  final TextSelection selection;
  final bool isRtl;
  final double layoutWidth;

  _VerticalLayoutInfo(
    this.painter,
    this.selection, {
    required this.isRtl,
    required this.layoutWidth,
  });

  bool get isAtTop {
    if (!selection.isCollapsed) return false;
    if (painter.text?.toPlainText().isEmpty ?? true) return true;
    return _currentLineIndex <= 0;
  }

  bool get isAtBottom {
    if (!selection.isCollapsed) return false;
    if (painter.text?.toPlainText().isEmpty ?? true) return true;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return true;
    return _currentLineIndex >= lines.length - 1;
  }

  double get currentX {
    final plain = painter.text?.toPlainText() ?? '';
    if (plain.trim().isEmpty) return isRtl ? layoutWidth : 0;
    if (selection.baseOffset < 0) return 0;
    final pos = TextPosition(offset: selection.baseOffset);
    final caret = painter.getOffsetForCaret(pos, Rect.zero);
    return caret.dx;
  }

  double caretXForOffset(int offset) {
    final text = painter.text?.toPlainText() ?? '';
    final safeOffset = offset.clamp(0, text.length).toInt();
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: safeOffset),
      Rect.zero,
    );
    return caret.dx;
  }

  int lineIndexForOffset(int offset) {
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final text = painter.text?.toPlainText() ?? '';
    final safeOffset = offset.clamp(0, text.length).toInt();
    final caretY = painter
        .getOffsetForCaret(TextPosition(offset: safeOffset), Rect.zero)
        .dy;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < lines.length; i++) {
      final center = _lineCenterY(i);
      final distance = (center - caretY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  int get lineCount => painter.computeLineMetrics().length;

  String debugLineMetrics() {
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return '  <none>';
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final top = line.baseline - line.ascent;
      final bottom = line.baseline + line.descent;
      buffer.writeln(
        '  #$i left=${line.left.toStringAsFixed(1)} '
        'width=${line.width.toStringAsFixed(1)} '
        'top=${top.toStringAsFixed(1)} bottom=${bottom.toStringAsFixed(1)} '
        'baseline=${line.baseline.toStringAsFixed(1)}',
      );
    }
    return buffer.toString().trimRight();
  }

  List<String> debugCaretStopsForLine({
    required String rawText,
    required int line,
  }) {
    if (line < 0) return const [];
    final plainTextLength = painter.text?.toPlainText().length ?? 0;
    if (plainTextLength <= 0) return const [];
    final visible = EditorTextGeometryService.visibleText(rawText);
    if (visible.isEmpty) return const [];
    final entries = <_DebugCaretEntry>[];
    for (var visibleOffset = 0;
        visibleOffset <= visible.length;
        visibleOffset++) {
      final raw = MarkupController.visualToRawOffset(rawText, visibleOffset)
          .clamp(0, plainTextLength)
          .toInt();
      for (final affinity in const [
        TextAffinity.downstream,
        TextAffinity.upstream,
      ]) {
        final caret = painter.getOffsetForCaret(
          TextPosition(offset: raw, affinity: affinity),
          Rect.zero,
        );
        final caretLine = _lineIndexForY(caret.dy);
        if (caretLine != line) continue;
        final duplicate = entries.any((entry) =>
            entry.raw == raw &&
            entry.visible == visibleOffset &&
            (entry.x - caret.dx).abs() <= 0.75);
        if (duplicate) continue;
        entries.add(_DebugCaretEntry(
          raw: raw,
          visible: visibleOffset,
          x: caret.dx,
          y: caret.dy,
          affinity: affinity,
          context: _visibleBoundaryContext(visible, visibleOffset),
        ));
      }
    }
    entries.sort((a, b) {
      final xCompare = a.x.compareTo(b.x);
      if (xCompare != 0) return xCompare;
      return a.visible.compareTo(b.visible);
    });
    return entries
        .map((entry) => '  raw=${entry.raw} visible=${entry.visible} '
            'x=${entry.x.toStringAsFixed(1)} y=${entry.y.toStringAsFixed(1)} '
            'affinity=${entry.affinity.name} ${entry.context}')
        .toList(growable: false);
  }

  int _lineIndexForY(double y) {
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < lines.length; i++) {
      final center = _lineCenterY(i);
      final distance = (center - y).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  String _visibleBoundaryContext(String visible, int offset) {
    final safeOffset = offset.clamp(0, visible.length).toInt();
    final before = safeOffset > 0 ? visible[safeOffset - 1] : '^';
    final after = safeOffset < visible.length ? visible[safeOffset] : r'$';
    return '"${_sanitizeDebugChar(before)}|${_sanitizeDebugChar(after)}"';
  }

  String _sanitizeDebugChar(String value) {
    return value.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
  }

  int getPositionAtX(
    double x, {
    required bool fromBottom,
    required String rawText,
  }) {
    if (painter.text?.toPlainText().isEmpty ?? true) return 0;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final targetLine = fromBottom ? lines.length - 1 : 0;
    if (isRtl) {
      final offset = EditorTextGeometryService.visualLineTargetRawOffset(
        painter: painter,
        rawText: rawText,
        x: x,
        fromBottom: fromBottom,
        visibleToRawOffset: MarkupController.visualToRawOffset,
      );
      if (offset != null) return offset;
    }
    final y = _lineCenterY(targetLine);
    return painter.getPositionForOffset(Offset(x, y)).offset;
  }

  int? getPositionOnAdjacentLineAtX(double x, {required bool moveUp}) {
    if (painter.text?.toPlainText().isEmpty ?? true) return null;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return null;
    final targetLine = _currentLineIndex + (moveUp ? -1 : 1);
    if (targetLine < 0 || targetLine >= lines.length) return null;
    return painter
        .getPositionForOffset(
          Offset(x, _lineCenterY(targetLine)),
        )
        .offset;
  }

  int? visualVerticalTargetRawOffset({
    required String rawText,
    required int rawOffset,
    required bool moveUp,
    double? preferredX,
  }) {
    return EditorTextGeometryService.visualVerticalTargetRawOffset(
      painter: painter,
      rawText: rawText,
      rawOffset: rawOffset,
      moveUp: moveUp,
      rawToVisibleOffset: MarkupController.rawToVisualOffset,
      visibleToRawOffset: MarkupController.visualToRawOffset,
      preferredX: preferredX ?? currentX,
    );
  }

  int? visualHorizontalTargetRawOffset({
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
  }) {
    return EditorTextGeometryService.visualHorizontalTargetRawOffset(
      painter: painter,
      rawText: rawText,
      rawOffset: rawOffset,
      moveLeft: moveLeft,
      rawToVisibleOffset: MarkupController.rawToVisualOffset,
      visibleToRawOffset: MarkupController.visualToRawOffset,
    );
  }

  int? visualWordTargetRawOffset({
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
  }) {
    return EditorTextGeometryService.visualWordTargetRawOffset(
      painter: painter,
      rawText: rawText,
      rawOffset: rawOffset,
      moveLeft: moveLeft,
      rawToVisibleOffset: MarkupController.rawToVisualOffset,
      visibleToRawOffset: MarkupController.visualToRawOffset,
    );
  }

  int get _currentLineIndex {
    return lineIndexForOffset(selection.baseOffset);
  }

  double _lineCenterY(int index) {
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final safeIndex = index.clamp(0, lines.length - 1).toInt();
    final line = lines[safeIndex];
    final top = line.baseline - line.ascent;
    final bottom = line.baseline + line.descent;
    return (top + bottom) / 2;
  }
}

class _DebugCaretEntry {
  final int raw;
  final int visible;
  final double x;
  final double y;
  final TextAffinity affinity;
  final String context;

  const _DebugCaretEntry({
    required this.raw,
    required this.visible,
    required this.x,
    required this.y,
    required this.affinity,
    required this.context,
  });
}
