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

    final currentLineStops = <({int raw, int line, double x})>[];
    final targetStops = <({int raw, int line, double x})>[];
    for (final raw in rawStops) {
      final safe = raw.clamp(0, plainText.length).toInt();
      final line = _lineIndexForOffset(painter, safe);
      final stop = (
        raw: safe,
        line: line,
        x: _caretXForOffset(painter, safe),
      );
      if (line == currentStop.line) currentLineStops.add(stop);
      if (line != targetLine) continue;
      targetStops.add(stop);
    }
    if (currentLineStops.isEmpty || targetStops.isEmpty) return null;
    _sortVisualStops(painter, currentLineStops);
    _sortVisualStops(painter, targetStops);

    final targetX = _clampedVisualTargetX(
      targetLineStops: targetStops,
      currentX: currentStop.x,
    );
    ({int raw, int line, double x})? best;
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

  static double _clampedVisualTargetX({
    required List<({int raw, int line, double x})> targetLineStops,
    required double currentX,
  }) {
    double minX(Iterable<({int raw, int line, double x})> stops) =>
        stops.map((stop) => stop.x).reduce((a, b) => a < b ? a : b);
    double maxX(Iterable<({int raw, int line, double x})> stops) =>
        stops.map((stop) => stop.x).reduce((a, b) => a > b ? a : b);
    return currentX.clamp(minX(targetLineStops), maxX(targetLineStops));
  }

  static ({int raw, int line, double x}) _currentVisualStop({
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
    return (
      raw: currentRaw,
      line: _lineIndexForOffset(painter, currentRaw),
      x: _caretXForOffset(painter, currentRaw),
    );
  }

  static int? _targetFromVisualStops({
    required TextPainter painter,
    required Set<int> rawStops,
    required ({int raw, int line, double x}) currentStop,
    required bool moveLeft,
  }) {
    if (rawStops.length < 2) return null;
    final plainLength = painter.text?.toPlainText().length ?? 0;
    final stops = <({int raw, int line, double x})>[];
    for (final raw in rawStops) {
      final safe = raw.clamp(0, plainLength).toInt();
      stops.add((
        raw: safe,
        line: _lineIndexForOffset(painter, safe),
        x: _caretXForOffset(painter, safe),
      ));
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

    final targetIndex =
        currentIndex + _visualStep(painter: painter, moveLeft: moveLeft);
    if (targetIndex < 0 || targetIndex >= orderedStops.length) return null;
    return orderedStops[targetIndex].raw;
  }

  static double _caretXForOffset(TextPainter painter, int offset) {
    final text = painter.text?.toPlainText() ?? '';
    final safeOffset = offset.clamp(0, text.length).toInt();
    return painter
        .getOffsetForCaret(TextPosition(offset: safeOffset), Rect.zero)
        .dx;
  }

  static int _lineIndexForOffset(TextPainter painter, int offset) {
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
    List<({int raw, int line, double x})> stops,
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

  static List<({int raw, int line, double x})>
      _collapseDuplicateVisualCaretStops(
    List<({int raw, int line, double x})> stops, {
    required ({int raw, int line, double x}) currentStop,
  }) {
    const duplicateTolerance = 0.75;
    final collapsed = <({int raw, int line, double x})>[];
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
