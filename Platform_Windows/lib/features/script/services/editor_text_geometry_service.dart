import 'package:flutter/material.dart';

import '../../../core/extensions/string_extensions.dart';
import 'markup_decoration_service.dart';

part 'editor_text_geometry_helpers.dart';

typedef RawToVisibleOffset = int Function(String rawText, int rawOffset);
typedef VisibleToRawOffset = int Function(String rawText, int visibleOffset);

class EditorTextGeometryService {
  static String visibleText(String rawText) =>
      MarkupDecorationParser.visibleText(rawText);

  static bool hasVisibleContent(String rawText) =>
      visibleText(rawText).trim().isNotEmpty;

  static String? explicitTextDirection(String rawText) {
    String? direction;
    for (final match in RegExp(r'\[(rtl|ltr)\]').allMatches(rawText)) {
      final value = match.group(1);
      if (value == null) continue;
      final close = rawText.indexOf('[/$value]', match.end);
      if (close == -1 || close >= match.end) direction = value;
    }
    return direction;
  }

  static bool resolveTextRtl(String rawText) {
    final explicit = explicitTextDirection(rawText);
    if (explicit != null) return explicit == 'rtl';
    return visibleText(rawText).isHebrew;
  }

  static bool resolveBlockRtl(List<String> rawBlocks, int index) {
    if (index < 0 || index >= rawBlocks.length) return false;
    final current = rawBlocks[index];
    final explicit = explicitTextDirection(current);
    if (explicit != null) return explicit == 'rtl';
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
      return _bidiHorizontalTargetRawOffset(
        painter: painter,
        rawText: rawText,
        rawOffset: rawOffset,
        moveLeft: moveLeft,
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

    if (painter.textDirection == TextDirection.rtl) {
      return _bidiWordTargetRawOffset(
        rawText: rawText,
        rawOffset: rawOffset,
        moveLeft: moveLeft,
        plainTextLength: plainText.length,
        visible: visible,
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
    final rawStops = <int>{
      0,
      visibleToRawOffset(rawText, visible.length)
          .clamp(0, plainText.length)
          .toInt(),
      currentStop.raw,
    };
    for (final boundary in _visualWordBoundaries(visible)) {
      rawStops.add(
        visibleToRawOffset(rawText, boundary)
            .clamp(0, plainText.length)
            .toInt(),
      );
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
    double? preferredX,
  }) {
    final plainText = painter.text?.toPlainText() ?? '';
    if (rawText.isEmpty || plainText.isEmpty) return null;
    final visible = visibleText(rawText);
    if (visible.isEmpty) return null;

    if (painter.textDirection == TextDirection.rtl) {
      return _bidiVerticalTargetRawOffset(
        painter: painter,
        rawText: rawText,
        rawOffset: rawOffset,
        plainTextLength: plainText.length,
        visible: visible,
        rawToVisibleOffset: rawToVisibleOffset,
        visibleToRawOffset: visibleToRawOffset,
        moveUp: moveUp,
        preferredX: preferredX,
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
      currentX: preferredX ?? currentStop.x,
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

  static int? visualLineTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required double x,
    required bool fromBottom,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final plainTextLength = painter.text?.toPlainText().length ?? 0;
    if (rawText.isEmpty || plainTextLength <= 0) return 0;
    final visible = visibleText(rawText);
    if (visible.isEmpty) return 0;
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return 0;
    final targetLine = fromBottom ? lines.length - 1 : 0;
    if (painter.textDirection != TextDirection.rtl) {
      return painter
          .getPositionForOffset(Offset(x, _lineCenterY(painter, targetLine)))
          .offset
          .clamp(0, plainTextLength)
          .toInt();
    }

    final stops = _bidiCaretStops(
      painter: painter,
      rawText: rawText,
      visible: visible,
      plainTextLength: plainTextLength,
      visibleToRawOffset: visibleToRawOffset,
    ).where((stop) => stop.line == targetLine).toList();
    if (stops.isEmpty) return null;
    final minX = stops.map((stop) => stop.x).reduce((a, b) => a < b ? a : b);
    final maxX = stops.map((stop) => stop.x).reduce((a, b) => a > b ? a : b);
    final targetX = x.clamp(minX, maxX);
    stops.sort((a, b) {
      final distanceCompare =
          (a.x - targetX).abs().compareTo((b.x - targetX).abs());
      if (distanceCompare != 0) return distanceCompare;
      return a.visible.compareTo(b.visible);
    });
    return stops.first.raw;
  }

  static int? _bidiHorizontalTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final plainTextLength = painter.text?.toPlainText().length ?? 0;
    final visible = visibleText(rawText);
    final stops = _bidiCaretStops(
      painter: painter,
      rawText: rawText,
      visible: visible,
      plainTextLength: plainTextLength,
      visibleToRawOffset: visibleToRawOffset,
    );
    if (stops.isEmpty) return null;
    final currentVisible = rawToVisibleOffset(
      rawText,
      rawOffset.clamp(0, rawText.length).toInt(),
    ).clamp(0, visible.length).toInt();
    final ltrRun = _ltrRunContainingBoundary(visible, currentVisible);
    if (ltrRun != null) {
      final targetVisible = !moveLeft && currentVisible < ltrRun.end
          ? currentVisible + 1
          : moveLeft && currentVisible > ltrRun.start
              ? currentVisible - 1
              : null;
      if (targetVisible != null) {
        return visibleToRawOffset(rawText, targetVisible)
            .clamp(0, plainTextLength)
            .toInt();
      }
    }
    return _targetFromVisibleStops(
      stops: stops,
      currentVisible: currentVisible,
      moveLeft: moveLeft,
    )?.raw;
  }

  static int? _bidiWordTargetRawOffset({
    required String rawText,
    required int rawOffset,
    required bool moveLeft,
    required int plainTextLength,
    required String visible,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final currentVisible = rawToVisibleOffset(
      rawText,
      rawOffset.clamp(0, rawText.length).toInt(),
    ).clamp(0, visible.length).toInt();
    final ltrRun = _ltrRunContainingBoundary(visible, currentVisible);
    if (ltrRun != null) {
      final targetVisible = !moveLeft
          ? _nextVisualWordBoundary(visible, ltrRun.start) ?? ltrRun.end
          : ltrRun.start;
      if (targetVisible != currentVisible) {
        return visibleToRawOffset(rawText, targetVisible)
            .clamp(0, plainTextLength)
            .toInt();
      }
    }
    final flow = _flowNearVisibleBoundary(
      visible,
      currentVisible,
      paragraphRtl: true,
    );
    final moveForward = flow == _TextFlow.rtl ? moveLeft : !moveLeft;
    final targetVisible = moveForward
        ? _nextVisualWordBoundary(visible, currentVisible)
        : _previousVisualWordBoundary(visible, currentVisible);
    if (targetVisible == null || targetVisible == currentVisible) return null;
    return visibleToRawOffset(rawText, targetVisible)
        .clamp(0, plainTextLength)
        .toInt();
  }

  static int? _bidiVerticalTargetRawOffset({
    required TextPainter painter,
    required String rawText,
    required int rawOffset,
    required int plainTextLength,
    required String visible,
    required RawToVisibleOffset rawToVisibleOffset,
    required VisibleToRawOffset visibleToRawOffset,
    required bool moveUp,
    double? preferredX,
  }) {
    final stops = _bidiCaretStops(
      painter: painter,
      rawText: rawText,
      visible: visible,
      plainTextLength: plainTextLength,
      visibleToRawOffset: visibleToRawOffset,
    );
    if (stops.isEmpty) return null;

    final currentVisible = rawToVisibleOffset(
      rawText,
      rawOffset.clamp(0, rawText.length).toInt(),
    ).clamp(0, visible.length).toInt();
    final currentCaret = _bestCaretStopForOffset(
      painter,
      visibleToRawOffset(rawText, currentVisible)
          .clamp(0, plainTextLength)
          .toInt(),
    );
    final targetLine = currentCaret.line + (moveUp ? -1 : 1);
    if (targetLine < 0) return null;
    final targetStops = stops.where((stop) => stop.line == targetLine).toList();
    if (targetStops.isEmpty) return null;
    final targetX = (preferredX ?? currentCaret.x).clamp(
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

  static List<_VisibleCaretStop> _bidiCaretStops({
    required TextPainter painter,
    required String rawText,
    required String visible,
    required int plainTextLength,
    required VisibleToRawOffset visibleToRawOffset,
  }) {
    final stops = <_VisibleCaretStop>[];
    final visibleLength = visible.length;
    for (var index = 0; index < visibleLength; index++) {
      final rawStart =
          visibleToRawOffset(rawText, index).clamp(0, plainTextLength).toInt();
      final rawEnd = visibleToRawOffset(rawText, index + 1)
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
      final flow = _flowForVisibleChar(
        visible,
        index,
        paragraphRtl: true,
      );
      final startX = flow == _TextFlow.ltr ? box.left : box.right;
      final endX = flow == _TextFlow.ltr ? box.right : box.left;
      stops.add(_VisibleCaretStop(
        visible: index,
        raw: rawStart,
        line: line,
        x: startX,
      ));
      stops.add(_VisibleCaretStop(
        visible: index + 1,
        raw: rawEnd,
        line: line,
        x: endX,
      ));
    }
    stops.sort((a, b) {
      final lineCompare = a.line.compareTo(b.line);
      if (lineCompare != 0) return lineCompare;
      final xCompare = a.x.compareTo(b.x);
      if (xCompare != 0) return xCompare;
      return a.visible.compareTo(b.visible);
    });
    return _dedupeVisibleCaretStops(stops);
  }

  static _VisibleCaretStop? _targetFromVisibleStops({
    required List<_VisibleCaretStop> stops,
    required int currentVisible,
    required bool moveLeft,
  }) {
    final candidates =
        stops.where((stop) => stop.visible == currentVisible).toList();
    if (candidates.isEmpty) return null;

    _VisibleCaretStop? bestTarget;
    var bestDistance = double.infinity;
    for (final candidate in candidates) {
      final lineStops =
          stops.where((stop) => stop.line == candidate.line).toList()
            ..sort((a, b) {
              final xCompare = a.x.compareTo(b.x);
              if (xCompare != 0) return xCompare;
              return a.visible.compareTo(b.visible);
            });
      final index = lineStops.indexWhere((stop) =>
          stop.visible == candidate.visible &&
          stop.raw == candidate.raw &&
          (stop.x - candidate.x).abs() <= 0.75);
      if (index < 0) continue;
      final step = moveLeft ? -1 : 1;
      var targetIndex = index + step;
      while (targetIndex >= 0 && targetIndex < lineStops.length) {
        final target = lineStops[targetIndex];
        if (target.visible != currentVisible) {
          final distance = (target.x - candidate.x).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            bestTarget = target;
          }
          break;
        }
        targetIndex += step;
      }
    }
    return bestTarget;
  }
}
