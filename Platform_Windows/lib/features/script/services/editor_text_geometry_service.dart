import 'package:flutter/material.dart';

import '../../../core/extensions/string_extensions.dart';
import 'markup_decoration_service.dart';

typedef RawToVisibleOffset = int Function(String rawText, int rawOffset);
typedef VisibleToRawOffset = int Function(String rawText, int visibleOffset);

class EditorTextGeometryService {
  static String visibleText(String rawText) =>
      MarkupDecorationParser.visibleText(rawText);

  static bool hasVisibleContent(String rawText) =>
      visibleText(rawText).trim().isNotEmpty;

  static bool resolveTextRtl(String rawText) => visibleText(rawText).isHebrew;

  static bool resolveBlockRtl(List<String> rawBlocks, int index) {
    if (index < 0 || index >= rawBlocks.length) return false;
    final current = rawBlocks[index];
    if (hasVisibleContent(current)) return resolveTextRtl(current);

    for (var i = index - 1; i >= 0; i--) {
      if (hasVisibleContent(rawBlocks[i])) return resolveTextRtl(rawBlocks[i]);
    }
    for (var i = index + 1; i < rawBlocks.length; i++) {
      if (hasVisibleContent(rawBlocks[i])) return resolveTextRtl(rawBlocks[i]);
    }
    return false;
  }

  static TextAlign resolveTextAlign(String rawText, {required bool isRtl}) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(rawText)) {
      return TextAlign.center;
    }
    if (RegExp(r'\[(?:align=)?right\]').hasMatch(rawText)) {
      return TextAlign.right;
    }
    if (RegExp(r'\[(?:align=)?left\]').hasMatch(rawText)) {
      return TextAlign.left;
    }
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  static double maxFontSize(String rawText, double defaultSize) {
    var maxSize = defaultSize;
    for (final match
        in RegExp(r'\[size=(\d+(?:\.\d+)?)\]').allMatches(rawText)) {
      final size = double.tryParse(match.group(1)!) ?? defaultSize;
      if (size > maxSize) maxSize = size;
    }
    return maxSize;
  }

  static int? visualHorizontalTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final plainText = painter.text?.toPlainText() ?? '';
    if (rawText.isEmpty || plainText.isEmpty) return 0;
    final visible = visibleText(rawText);
    if (visible.isEmpty) return 0;

    if (painter.textDirection == TextDirection.rtl) {
      return _rtlLogicalHorizontalTargetRawOffset(
        rawText: rawText,
        rawOffset: rawOffset,
        moveLeft: moveLeft,
        plainTextLength: plainText.length,
        visibleLength: visible.length,
        rawToVisibleOffset: rawToVisibleOffset,
        visibleToRawOffset: visibleToRawOffset,
      );
    }

    final currentStop = _currentVisualStop(
      painter: painter,
      rawText: rawText,
      rawOffset: rawOffset,
      plainTextLength: plainText.length,
      visibleLength: visible.length,
      rawToVisibleOffset: rawToVisibleOffset,
      visibleToRawOffset: visibleToRawOffset,
    );
    final rawStops = <int>{};
    for (var visual = 0; visual <= visible.length; visual++) {
      rawStops.add(
        visibleToRawOffset(rawText, visual).clamp(0, plainText.length).toInt(),
      );
    }
    return _targetFromVisualStops(
      painter: painter,
      rawStops: rawStops,
      currentStop: currentStop,
      moveLeft: moveLeft,
    );
  }

  static int? visualWordTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final plainText = painter.text?.toPlainText() ?? '';
    if (rawText.isEmpty || plainText.isEmpty) return 0;
    final visible = visibleText(rawText);
    if (visible.isEmpty) return 0;

    final currentStop = _currentVisualStop(
      painter: painter,
      rawText: rawText,
      rawOffset: rawOffset,
      plainTextLength: plainText.length,
      visibleLength: visible.length,
      rawToVisibleOffset: rawToVisibleOffset,
      visibleToRawOffset: visibleToRawOffset,
    );
    final rawStops = <int>{
      0,
      visibleToRawOffset(rawText, visible.length)
          .clamp(0, plainText.length)
          .toInt(),
      currentStop.raw,
    };
    for (var i = 1; i < visible.length; i++) {
      final beforeWord = _isVisualWordChar(visible[i - 1]);
      final afterWord = _isVisualWordChar(visible[i]);
      if (beforeWord != afterWord) {
        rawStops.add(
          visibleToRawOffset(rawText, i).clamp(0, plainText.length).toInt(),
        );
      }
    }
    return _targetFromVisualStops(
      painter: painter,
      rawStops: rawStops,
      currentStop: currentStop,
      moveLeft: moveLeft,
    );
  }

  static int? visualVerticalTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required int rawOffset,
    required bool moveUp,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final plainText = painter.text?.toPlainText() ?? '';
    if (rawText.isEmpty || plainText.isEmpty) return null;
    final visible = visibleText(rawText);
    if (visible.isEmpty) return null;

    if (painter.textDirection == TextDirection.rtl) {
      return _rtlBoxVerticalTargetRawOffset(
        painter: painter,
        rawText: rawText,
        rawOffset: rawOffset,
        plainTextLength: plainText.length,
        visibleLength: visible.length,
        rawToVisibleOffset: rawToVisibleOffset,
        visibleToRawOffset: visibleToRawOffset,
        moveUp: moveUp,
      );
    }

    final currentStop = _currentVisualStop(
      painter: painter,
      rawText: rawText,
      rawOffset: rawOffset,
      plainTextLength: plainText.length,
      visibleLength: visible.length,
      rawToVisibleOffset: rawToVisibleOffset,
      visibleToRawOffset: visibleToRawOffset,
    );
    final targetLine = currentStop.line + (moveUp ? -1 : 1);
    if (targetLine < 0) return null;

    final rawStops = <int>{};
    for (var visual = 0; visual <= visible.length; visual++) {
      rawStops.add(
        visibleToRawOffset(rawText, visual).clamp(0, plainText.length).toInt(),
      );
    }
    if (rawStops.length < 2) return null;

    final currentLineStops = <_VisualCaretStop>[];
    final targetStops = <_VisualCaretStop>[];
    for (final raw in rawStops) {
      final safe = raw.clamp(0, plainText.length).toInt();
      for (final stop in _caretStopsForOffset(painter, safe)) {
        if (stop.line == currentStop.line) currentLineStops.add(stop);
        if (stop.line != targetLine) continue;
        targetStops.add(stop);
      }
    }
    if (currentLineStops.isEmpty || targetStops.isEmpty) return null;
    _sortVisualStops(painter, currentLineStops);
    _sortVisualStops(painter, targetStops);

    final targetX = _clampedVisualTargetX(
      targetLineStops: targetStops,
      currentX: currentStop.x,
    );
    _VisualCaretStop? best;
    var bestDistance = double.infinity;
    for (final stop in targetStops) {
      final distance = (stop.x - targetX).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = stop;
      }
    }
    return best?.raw;
  }

  static int? _rtlLogicalHorizontalTargetRawOffset({
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
    required int plainTextLength,
    required int visibleLength,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final currentVisible = rawToVisibleOffset(
      rawText,
      rawOffset.clamp(0, rawText.length).toInt(),
    ).clamp(0, visibleLength).toInt();
    final targetVisible = currentVisible + (moveLeft ? 1 : -1);
    if (targetVisible < 0 || targetVisible > visibleLength) return null;
    return visibleToRawOffset(rawText, targetVisible)
        .clamp(0, plainTextLength)
        .toInt();
  }

  static int? _rtlBoxVerticalTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required int rawOffset,
    required int plainTextLength,
    required int visibleLength,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
    required bool moveUp,
  }) {
    final stops = _rtlBoxCaretStops(
      painter: painter,
      rawText: rawText,
      visibleLength: visibleLength,
      plainTextLength: plainTextLength,
      visibleToRawOffset: visibleToRawOffset,
    );
    if (stops.isEmpty) return null;

    final currentVisible = rawToVisibleOffset(
      rawText,
      rawOffset.clamp(0, rawText.length).toInt(),
    ).clamp(0, visibleLength).toInt();
    final currentCandidates =
        stops.where((stop) => stop.visible == currentVisible).toList();
    if (currentCandidates.isEmpty) return null;
    final oldCaret = _bestCaretStopForOffset(
      painter,
      visibleToRawOffset(rawText, currentVisible)
          .clamp(0, plainTextLength)
          .toInt(),
    );
    currentCandidates.sort((a, b) {
      final lineCompare = (a.line - oldCaret.line)
          .abs()
          .compareTo((b.line - oldCaret.line).abs());
      if (lineCompare != 0) return lineCompare;
      return (a.x - oldCaret.x).abs().compareTo((b.x - oldCaret.x).abs());
    });
    final currentStop = currentCandidates.first;
    final targetLine = currentStop.line + (moveUp ? -1 : 1);
    if (targetLine < 0) return null;
    final targetStops = stops.where((stop) => stop.line == targetLine).toList();
    if (targetStops.isEmpty) return null;
    final targetX = currentStop.x.clamp(
      targetStops.map((stop) => stop.x).reduce((a, b) => a < b ? a : b),
      targetStops.map((stop) => stop.x).reduce((a, b) => a > b ? a : b),
    );
    targetStops.sort((a, b) {
      final distanceCompare =
          (a.x - targetX).abs().compareTo((b.x - targetX).abs());
      if (distanceCompare != 0) return distanceCompare;
      return a.visible.compareTo(b.visible);
    });
    return targetStops.first.raw;
  }

  static List<_VisibleCaretStop> _rtlBoxCaretStops({
    required TextPainter painter,
    required String rawText,
    required int visibleLength,
    required int plainTextLength,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final stops = <_VisibleCaretStop>[];
    for (var visible = 0; visible < visibleLength; visible++) {
      final rawStart = visibleToRawOffset(rawText, visible)
          .clamp(0, plainTextLength)
          .toInt();
      final rawEnd = visibleToRawOffset(rawText, visible + 1)
          .clamp(rawStart, plainTextLength)
          .toInt();
      if (rawEnd <= rawStart) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: rawStart, extentOffset: rawEnd),
      );
      if (boxes.isEmpty) continue;
      final box = boxes.reduce((best, next) {
        final bestArea = best.toRect().width * best.toRect().height;
        final nextArea = next.toRect().width * next.toRect().height;
        return nextArea > bestArea ? next : best;
      }).toRect();
      if (box.width <= 0.1 || box.height <= 0.1) continue;
      final line = _lineIndexForCaretY(painter, box.center.dy);
      stops.add(_VisibleCaretStop(
        visible: visible,
        raw: rawStart,
        line: line,
        x: box.right,
      ));
      stops.add(_VisibleCaretStop(
        visible: visible + 1,
        raw: rawEnd,
        line: line,
        x: box.left,
      ));
    }
    stops.sort((a, b) {
      final lineCompare = a.line.compareTo(b.line);
      if (lineCompare != 0) return lineCompare;
      final xCompare = b.x.compareTo(a.x);
      if (xCompare != 0) return xCompare;
      return a.visible.compareTo(b.visible);
    });
    return _dedupeVisibleCaretStops(stops);
  }

  static List<_VisibleCaretStop> _dedupeVisibleCaretStops(
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

  static double _clampedVisualTargetX({
    required List<_VisualCaretStop> targetLineStops,
    required double currentX,
  }) {
    double minX(Iterable<_VisualCaretStop> stops) =>
        stops.map((stop) => stop.x).reduce((a, b) => a < b ? a : b);
    double maxX(Iterable<_VisualCaretStop> stops) =>
        stops.map((stop) => stop.x).reduce((a, b) => a > b ? a : b);
    return currentX.clamp(minX(targetLineStops), maxX(targetLineStops));
  }

  static _VisualCaretStop _currentVisualStop({
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

  static int? _targetFromVisualStops({
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

    var currentIndex = orderedStops
        .indexWhere((candidate) => candidate.raw == currentStop.raw);
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

  static _VisualCaretStop _bestCaretStopForOffset(
    TextPainter painter,
    int offset,
  ) {
    final stops = _caretStopsForOffset(painter, offset);
    if (stops.isEmpty) return _VisualCaretStop(raw: offset, line: 0, x: 0);
    return stops.first;
  }

  static List<_VisualCaretStop> _caretStopsForOffset(
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

  static List<_VisualCaretStop> _dedupeCaretStops(
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

  static int _lineIndexForCaretY(TextPainter painter, double caretY) {
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

  static bool _isVisualWordChar(String value) {
    if (value.isEmpty || value.trim().isEmpty) return false;
    final code = value.codeUnitAt(0);
    final isAsciiLetter =
        (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isHebrew = code >= 0x0590 && code <= 0x05FF;
    return isAsciiLetter || isDigit || isHebrew;
  }

  static int _visualStep({
    required TextPainter painter,
    required bool moveLeft,
  }) {
    final isRtl = painter.textDirection == TextDirection.rtl;
    final moveForward = isRtl ? moveLeft : !moveLeft;
    return moveForward ? 1 : -1;
  }

  static void _sortVisualStops(
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

  static List<_VisualCaretStop> _collapseDuplicateVisualCaretStops(
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
      final sameVisualStop = last.line == stop.line &&
          (last.x - stop.x).abs() <= duplicateTolerance;
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
