part of 'editor_text_geometry_service.dart';

int? _nextVisualWordBoundary(String visible, int current) {
  final boundaries = _visualWordBoundaries(visible);
  for (final boundary in boundaries) {
    if (boundary > current) return boundary;
  }
  return null;
}

int? _previousVisualWordBoundary(String visible, int current) {
  final boundaries = _visualWordBoundaries(visible);
  for (var i = boundaries.length - 1; i >= 0; i--) {
    final boundary = boundaries[i];
    if (boundary < current) return boundary;
  }
  return null;
}

List<int> _visualWordBoundaries(String visible) {
  final boundaries = <int>{0, visible.length};
  for (var i = 1; i < visible.length; i++) {
    final beforeWord = _isVisualWordChar(visible[i - 1]);
    final afterWord = _isVisualWordChar(visible[i]);
    if (beforeWord != afterWord) boundaries.add(i);
  }
  final sorted = boundaries.toList()..sort();
  return sorted;
}

({int start, int end})? _ltrRunContainingBoundary(
  String visible,
  int boundary,
) {
  var start = boundary;
  while (start > 0 && _isLtrIslandCodeUnit(visible.codeUnitAt(start - 1))) {
    start--;
  }
  var end = boundary;
  while (
      end < visible.length && _isLtrIslandCodeUnit(visible.codeUnitAt(end))) {
    end++;
  }
  if (end <= start) return null;
  var hasAsciiLetter = false;
  for (var i = start; i < end; i++) {
    if (_isAsciiLetter(visible.codeUnitAt(i))) {
      hasAsciiLetter = true;
      break;
    }
  }
  if (!hasAsciiLetter) return null;
  if (boundary < start || boundary > end) return null;
  return (start: start, end: end);
}

bool _isAsciiLetterOrDigit(int codeUnit) {
  final isAsciiLetter = _isAsciiLetter(codeUnit);
  final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
  return isAsciiLetter || isDigit;
}

bool _isAsciiLetter(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

bool _isLtrIslandCodeUnit(int codeUnit) {
  if (_isAsciiLetterOrDigit(codeUnit)) return true;
  return codeUnit == 0x0021 || // !
      codeUnit == 0x0022 || // "
      codeUnit == 0x0027 || // '
      codeUnit == 0x0028 || // (
      codeUnit == 0x0029 || // )
      codeUnit == 0x002C || // ,
      codeUnit == 0x002D || // -
      codeUnit == 0x002E || // .
      codeUnit == 0x002F || // /
      codeUnit == 0x003A || // :
      codeUnit == 0x003B || // ;
      codeUnit == 0x003F; // ?
}

_TextFlow _flowForVisibleChar(
  String visible,
  int index, {
  required bool paragraphRtl,
}) {
  if (index < 0 || index >= visible.length) {
    return paragraphRtl ? _TextFlow.rtl : _TextFlow.ltr;
  }
  final strong = _strongFlowForCodeUnit(visible.codeUnitAt(index));
  if (strong != null) return strong;
  return _flowNearVisibleBoundary(
    visible,
    index,
    paragraphRtl: paragraphRtl,
  );
}

_TextFlow _flowNearVisibleBoundary(
  String visible,
  int boundary, {
  required bool paragraphRtl,
}) {
  _TextFlow? before;
  _TextFlow? after;
  for (var i = boundary - 1; i >= 0; i--) {
    before = _strongFlowForCodeUnit(visible.codeUnitAt(i));
    if (before != null) break;
  }
  for (var i = boundary; i < visible.length; i++) {
    after = _strongFlowForCodeUnit(visible.codeUnitAt(i));
    if (after != null) break;
  }
  if (before != null && after != null && before == after) return before;
  return before ?? after ?? (paragraphRtl ? _TextFlow.rtl : _TextFlow.ltr);
}

_TextFlow? _strongFlowForCodeUnit(int codeUnit) {
  final isHebrew = codeUnit >= 0x0590 && codeUnit <= 0x05FF;
  if (isHebrew) return _TextFlow.rtl;
  final isAsciiLetter = (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
  if (isAsciiLetter) return _TextFlow.ltr;
  return null;
}

List<_VisibleCaretStop> _dedupeVisibleCaretStops(
  List<_VisibleCaretStop> stops,
) {
  const tolerance = 0.75;
  final deduped = <_VisibleCaretStop>[];
  for (final stop in stops) {
    final duplicate = deduped.any((existing) =>
        existing.visible == stop.visible &&
        existing.line == stop.line &&
        (existing.x - stop.x).abs() <= tolerance);
    if (!duplicate) deduped.add(stop);
  }
  return deduped;
}

double _clampedVisualTargetX({
  required List<_VisualCaretStop> targetLineStops,
  required double currentX,
}) {
  double minX(Iterable<_VisualCaretStop> stops) =>
      stops.map((stop) => stop.x).reduce((a, b) => a < b ? a : b);
  double maxX(Iterable<_VisualCaretStop> stops) =>
      stops.map((stop) => stop.x).reduce((a, b) => a > b ? a : b);
  return currentX.clamp(minX(targetLineStops), maxX(targetLineStops));
}

_VisualCaretStop _currentVisualStop({
  required TextPainter painter,
  required String rawText,
  required int rawOffset,
  required int plainTextLength,
  required int visibleLength,
  required RawToVisibleOffset rawToVisibleOffset,
  required VisibleToRawOffset visibleToRawOffset,
}) {
  final currentVisible = rawToVisibleOffset(
    rawText,
    rawOffset.clamp(0, rawText.length).toInt(),
  ).clamp(0, visibleLength).toInt();
  final currentRaw = visibleToRawOffset(rawText, currentVisible)
      .clamp(0, plainTextLength)
      .toInt();
  return _bestCaretStopForOffset(painter, currentRaw);
}

int? _targetFromVisualStops({
  required TextPainter painter,
  required Set<int> rawStops,
  required _VisualCaretStop currentStop,
  required bool moveLeft,
}) {
  if (rawStops.length < 2) return null;
  final plainLength = painter.text?.toPlainText().length ?? 0;
  final stops = <_VisualCaretStop>[];
  for (final raw in rawStops) {
    final safe = raw.clamp(0, plainLength).toInt();
    stops.addAll(_caretStopsForOffset(painter, safe));
  }
  _sortVisualStops(painter, stops);
  final orderedStops = _collapseDuplicateVisualCaretStops(
    stops,
    currentStop: currentStop,
  );
  if (orderedStops.length < 2) return null;

  var currentIndex =
      orderedStops.indexWhere((candidate) => candidate.raw == currentStop.raw);
  if (currentIndex < 0) {
    var bestDistance = double.infinity;
    for (var i = 0; i < orderedStops.length; i++) {
      final candidate = orderedStops[i];
      final linePenalty = candidate.line == currentStop.line ? 0.0 : 10000.0;
      final distance = linePenalty + (candidate.x - currentStop.x).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        currentIndex = i;
      }
    }
  }
  if (currentIndex < 0) return null;

  final step = _visualStep(painter: painter, moveLeft: moveLeft);
  var targetIndex = currentIndex + step;
  while (targetIndex >= 0 &&
      targetIndex < orderedStops.length &&
      orderedStops[targetIndex].raw == currentStop.raw) {
    targetIndex += step;
  }
  if (targetIndex < 0 || targetIndex >= orderedStops.length) return null;
  return orderedStops[targetIndex].raw;
}

_VisualCaretStop _bestCaretStopForOffset(
  TextPainter painter,
  int offset,
) {
  final stops = _caretStopsForOffset(painter, offset);
  if (stops.isEmpty) return _VisualCaretStop(raw: offset, line: 0, x: 0);
  return stops.first;
}

List<_VisualCaretStop> _caretStopsForOffset(
  TextPainter painter,
  int offset,
) {
  final text = painter.text?.toPlainText() ?? '';
  final safeOffset = offset.clamp(0, text.length).toInt();
  if (painter.textDirection != TextDirection.rtl) {
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: safeOffset),
      Rect.zero,
    );
    return [
      _VisualCaretStop(
        raw: safeOffset,
        line: _lineIndexForCaretY(painter, caret.dy),
        x: caret.dx,
      ),
    ];
  }
  final stops = <_VisualCaretStop>[];
  for (final affinity in const [
    TextAffinity.downstream,
    TextAffinity.upstream,
  ]) {
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: safeOffset, affinity: affinity),
      Rect.zero,
    );
    stops.add(_VisualCaretStop(
      raw: safeOffset,
      line: _lineIndexForCaretY(painter, caret.dy),
      x: caret.dx,
    ));
  }
  return _dedupeCaretStops(stops);
}

List<_VisualCaretStop> _dedupeCaretStops(
  List<_VisualCaretStop> stops,
) {
  const tolerance = 0.75;
  final deduped = <_VisualCaretStop>[];
  for (final stop in stops) {
    final duplicate = deduped.any((existing) =>
        existing.raw == stop.raw &&
        existing.line == stop.line &&
        (existing.x - stop.x).abs() <= tolerance);
    if (!duplicate) deduped.add(stop);
  }
  return deduped;
}

int _lineIndexForCaretY(TextPainter painter, double caretY) {
  final lines = painter.computeLineMetrics();
  if (lines.isEmpty) return 0;
  var bestIndex = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final top = line.baseline - line.ascent;
    final bottom = line.baseline + line.descent;
    final center = (top + bottom) / 2;
    final distance = (center - caretY).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
    }
  }
  return bestIndex;
}

double _lineCenterY(TextPainter painter, int index) {
  final lines = painter.computeLineMetrics();
  if (lines.isEmpty) return 0;
  final safeIndex = index.clamp(0, lines.length - 1).toInt();
  final line = lines[safeIndex];
  final top = line.baseline - line.ascent;
  final bottom = line.baseline + line.descent;
  return (top + bottom) / 2;
}

bool _isVisualWordChar(String value) {
  if (value.isEmpty || value.trim().isEmpty) return false;
  final code = value.codeUnitAt(0);
  final isAsciiLetter =
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  final isDigit = code >= 0x30 && code <= 0x39;
  final isHebrew = code >= 0x0590 && code <= 0x05FF;
  return isAsciiLetter || isDigit || isHebrew;
}

int _visualStep({
  required TextPainter painter,
  required bool moveLeft,
}) {
  final isRtl = painter.textDirection == TextDirection.rtl;
  final moveForward = isRtl ? moveLeft : !moveLeft;
  return moveForward ? 1 : -1;
}

void _sortVisualStops(
  TextPainter painter,
  List<_VisualCaretStop> stops,
) {
  final isRtl = painter.textDirection == TextDirection.rtl;
  stops.sort((a, b) {
    final lineCompare = a.line.compareTo(b.line);
    if (lineCompare != 0) return lineCompare;
    final xCompare = isRtl ? b.x.compareTo(a.x) : a.x.compareTo(b.x);
    if (xCompare != 0) return xCompare;
    return isRtl ? b.raw.compareTo(a.raw) : a.raw.compareTo(b.raw);
  });
}

List<_VisualCaretStop> _collapseDuplicateVisualCaretStops(
  List<_VisualCaretStop> stops, {
  required _VisualCaretStop currentStop,
}) {
  const duplicateTolerance = 0.75;
  final collapsed = <_VisualCaretStop>[];
  for (final stop in stops) {
    if (collapsed.isEmpty) {
      collapsed.add(stop);
      continue;
    }
    final last = collapsed.last;
    final sameVisualStop =
        last.line == stop.line && (last.x - stop.x).abs() <= duplicateTolerance;
    if (!sameVisualStop) {
      collapsed.add(stop);
      continue;
    }
    final keepLast = (last.raw - currentStop.raw).abs() <=
        (stop.raw - currentStop.raw).abs();
    collapsed[collapsed.length - 1] = keepLast ? last : stop;
  }
  return collapsed;
}

class _VisualCaretStop {
  final int raw;
  final int line;
  final double x;

  const _VisualCaretStop({
    required this.raw,
    required this.line,
    required this.x,
  });
}

class _VisibleCaretStop {
  final int visible;
  final int raw;
  final int line;
  final double x;

  const _VisibleCaretStop({
    required this.visible,
    required this.raw,
    required this.line,
    required this.x,
  });
}

enum _TextFlow { ltr, rtl }
