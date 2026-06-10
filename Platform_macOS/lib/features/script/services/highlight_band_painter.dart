import 'dart:ui';

class HighlightBand {
  final Rect rect;

  const HighlightBand(this.rect);
}

class HighlightConnector {
  final Rect rect;

  const HighlightConnector(this.rect);
}

class HighlightRegion {
  final List<HighlightBand> bands;
  final List<HighlightConnector> connectors;

  const HighlightRegion({
    required this.bands,
    required this.connectors,
  });

  bool get isEmpty => bands.isEmpty;
}

class HighlightBandPainter {
  const HighlightBandPainter._();

  static List<Rect> textLaneBands(
    List<Rect> bands,
    Size size, {
    double topPaddingRatio = 0.08,
    double bottomPaddingRatio = 0.18,
    double minHeight = 6.0,
    double maxHeight = 240.0,
  }) {
    final rows =
        bands.where((band) => band.width > 0 && band.height > 0).toList()
          ..sort((a, b) {
            final top = a.center.dy.compareTo(b.center.dy);
            return top != 0 ? top : a.left.compareTo(b.left);
          });
    if (rows.isEmpty) return const [];

    final medianHeight = _medianHeight(rows);
    final topPad = medianHeight * topPaddingRatio;
    final bottomPad = medianHeight * bottomPaddingRatio;
    final desiredMin = minHeight.clamp(0.0, maxHeight).toDouble();
    final normalized = <Rect>[];
    for (final row in rows) {
      var top = row.top - topPad;
      var bottom = row.bottom + bottomPad;
      final center = row.center.dy;
      var height = (bottom - top).clamp(desiredMin, maxHeight).toDouble();
      if (bottom - top != height) {
        top = center - height * 0.46;
        bottom = top + height;
      }
      normalized.add(
        Rect.fromLTRB(
          row.left.clamp(0.0, size.width).toDouble(),
          top.clamp(0.0, size.height).toDouble(),
          row.right.clamp(0.0, size.width).toDouble(),
          bottom.clamp(0.0, size.height).toDouble(),
        ),
      );
    }

    for (var i = 0; i < normalized.length - 1; i++) {
      final current = normalized[i];
      final next = normalized[i + 1];
      if (next.center.dy <= current.center.dy || current.bottom <= next.top) {
        continue;
      }
      final boundary = ((current.center.dy + next.center.dy) / 2.0)
          .roundToDouble()
          .clamp(0.0, size.height)
          .toDouble();
      normalized[i] = Rect.fromLTRB(
        current.left,
        current.top,
        current.right,
        boundary > current.top ? boundary : current.bottom,
      );
      normalized[i + 1] = Rect.fromLTRB(
        next.left,
        boundary < next.bottom ? boundary : next.top,
        next.right,
        next.bottom,
      );
    }

    return normalized
        .where((row) => row.width > 0 && row.height > 0)
        .toList(growable: false);
  }

  static HighlightRegion computeConnectedRegion(
    List<Rect> bands,
    Size size, {
    bool connectRows = true,
    double connectorGapRatio = 0.45,
    double maxConnectorGap = 18.0,
  }) {
    final rows = bands
        .where((band) => band.width > 0 && band.height > 0)
        .map((band) => _pixelRect(band, size))
        .where((band) => band.width > 0 && band.height > 0)
        .toList()
      ..sort((a, b) {
        final top = a.top.compareTo(b.top);
        return top != 0 ? top : a.left.compareTo(b.left);
      });
    if (rows.isEmpty) {
      return const HighlightRegion(bands: [], connectors: []);
    }

    final connectors = <HighlightConnector>[];
    if (connectRows) {
      final medianHeight = _medianHeight(rows);
      for (var i = 0; i < rows.length - 1; i++) {
        final current = rows[i];
        final next = rows[i + 1];
        final centerDistance = next.center.dy - current.center.dy;
        if (centerDistance <= 0) {
          continue;
        }
        final verticalGap = next.top - current.bottom;
        final maxAdjacentGap =
            (medianHeight * connectorGapRatio).clamp(2.0, maxConnectorGap);
        if (verticalGap > maxAdjacentGap) {
          continue;
        }

        final overlapLeft =
            (current.left > next.left ? current.left : next.left)
                .clamp(0.0, size.width)
                .toDouble();
        final overlapRight =
            (current.right < next.right ? current.right : next.right)
                .clamp(0.0, size.width)
                .toDouble();
        if (overlapRight - overlapLeft <= 3.0) continue;

        final left = overlapLeft.floorToDouble();
        final right = overlapRight.ceilToDouble();
        final bridgeTop = current.bottom < next.top ? current.bottom : next.top;
        final bridgeBottom =
            current.bottom > next.top ? current.bottom : next.top;
        var top = bridgeTop.clamp(0.0, size.height).toDouble().floorToDouble();
        var bottom =
            bridgeBottom.clamp(0.0, size.height).toDouble().ceilToDouble();
        if (bottom <= top) {
          final seam = current.bottom.clamp(0.0, size.height).toDouble();
          top = (seam - 0.5).clamp(0.0, size.height).toDouble().floorToDouble();
          bottom =
              (seam + 0.5).clamp(0.0, size.height).toDouble().ceilToDouble();
        }
        if (right <= left || bottom <= top) continue;
        connectors.add(
          HighlightConnector(Rect.fromLTRB(left, top, right, bottom)),
        );
      }
    }

    return HighlightRegion(
      bands: [for (final row in rows) HighlightBand(row)],
      connectors: connectors,
    );
  }

  static void paintConnectedRegion(
    Canvas canvas,
    List<Rect> bands,
    Color color,
    Size size, {
    double radius = 6.0,
    bool connectRows = true,
    double connectorGapRatio = 0.45,
    double maxConnectorGap = 18.0,
  }) {
    if (color.a <= 0 || bands.isEmpty) return;
    final region = computeConnectedRegion(
      bands,
      size,
      connectRows: connectRows,
      connectorGapRatio: connectorGapRatio,
      maxConnectorGap: maxConnectorGap,
    );
    if (region.isEmpty) return;

    final path = _pathForRegion(region, radius);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = radius > 0,
    );
  }

  static void paintRoundedConnectedRegion(
    Canvas canvas,
    List<Rect> bands,
    Color color,
    Size size, {
    double radius = 6.0,
    bool connectRows = true,
  }) {
    paintConnectedRegion(
      canvas,
      bands,
      color,
      size,
      radius: radius,
      connectRows: connectRows,
    );
  }

  static String describeConnectedRegion(
    List<Rect> bands,
    Size size, {
    bool connectRows = true,
  }) {
    final region = computeConnectedRegion(
      bands,
      size,
      connectRows: connectRows,
    );
    return [
      'rows=${_formatRects([for (final band in region.bands) band.rect])}',
      'connectors=${_formatRects([
            for (final connector in region.connectors) connector.rect
          ])}',
    ].join(' ');
  }

  static double suggestedRadius(List<Rect> bands) {
    final sorted = bands.where((band) => band.height > 0).toList();
    if (sorted.isEmpty) return 0.0;
    final median = _medianHeight(sorted);
    return (median * 0.22).clamp(3.0, 9.0).toDouble();
  }

  static double medianBandHeight(List<Rect> bands) => _medianHeight(bands);

  static bool isIgnorableHighlightSeparator({
    required String raw,
    required String normalized,
  }) {
    if (normalized.trim().isEmpty) return true;
    final text = raw.trim();
    if (text.isEmpty) return true;
    return !RegExp(r'[A-Za-z0-9\u0590-\u05FF]').hasMatch(text);
  }

  static Path? _pathForRegion(HighlightRegion region, double radius) {
    final rects = <Rect>[
      for (final band in region.bands) band.rect,
      for (final connector in region.connectors) connector.rect,
    ].where((rect) => rect.width > 0 && rect.height > 0).toList();
    if (rects.isEmpty) return null;

    final roundedCorners = _roundedCornerPoints(region);
    final loops = _boundaryLoops(rects);
    if (loops.isEmpty) return null;

    final path = Path()..fillType = PathFillType.nonZero;
    for (final loop in loops) {
      _addLoop(path, loop, roundedCorners, radius);
    }
    return path;
  }

  static Set<_PointKey> _roundedCornerPoints(HighlightRegion region) {
    final connectors =
        region.connectors.map((connector) => connector.rect).toList();
    final points = <_PointKey>{};
    for (final band in region.bands) {
      final rect = band.rect;
      final hasTopConnector = connectors.any(
        (connector) => _connectorTouchesTop(rect, connector),
      );
      final hasBottomConnector = connectors.any(
        (connector) => _connectorTouchesBottom(rect, connector),
      );
      if (!hasTopConnector) {
        points.add(_PointKey(rect.left.round(), rect.top.round()));
        points.add(_PointKey(rect.right.round(), rect.top.round()));
      }
      if (!hasBottomConnector) {
        points.add(_PointKey(rect.left.round(), rect.bottom.round()));
        points.add(_PointKey(rect.right.round(), rect.bottom.round()));
      }
    }
    return points;
  }

  static List<List<_PointKey>> _boundaryLoops(List<Rect> rects) {
    final xs = <int>{};
    final ys = <int>{};
    for (final rect in rects) {
      xs
        ..add(rect.left.round())
        ..add(rect.right.round());
      ys
        ..add(rect.top.round())
        ..add(rect.bottom.round());
    }
    final sortedX = xs.toList()..sort();
    final sortedY = ys.toList()..sort();
    if (sortedX.length < 2 || sortedY.length < 2) return const [];

    final filled = <String>{};
    for (var xi = 0; xi < sortedX.length - 1; xi++) {
      for (var yi = 0; yi < sortedY.length - 1; yi++) {
        final left = sortedX[xi].toDouble();
        final right = sortedX[xi + 1].toDouble();
        final top = sortedY[yi].toDouble();
        final bottom = sortedY[yi + 1].toDouble();
        if (right <= left || bottom <= top) continue;
        final center = Offset((left + right) / 2.0, (top + bottom) / 2.0);
        if (rects.any((rect) => rect.contains(center))) {
          filled.add('$xi:$yi');
        }
      }
    }

    final edges = <_EdgeKey, _Edge>{};
    void toggle(_PointKey start, _PointKey end) {
      final reverse = _EdgeKey(end, start);
      if (edges.remove(reverse) == null) {
        edges[_EdgeKey(start, end)] = _Edge(start, end);
      }
    }

    for (final key in filled) {
      final parts = key.split(':');
      final xi = int.parse(parts[0]);
      final yi = int.parse(parts[1]);
      final topLeft = _PointKey(sortedX[xi], sortedY[yi]);
      final topRight = _PointKey(sortedX[xi + 1], sortedY[yi]);
      final bottomRight = _PointKey(sortedX[xi + 1], sortedY[yi + 1]);
      final bottomLeft = _PointKey(sortedX[xi], sortedY[yi + 1]);
      toggle(topLeft, topRight);
      toggle(topRight, bottomRight);
      toggle(bottomRight, bottomLeft);
      toggle(bottomLeft, topLeft);
    }

    final outgoing = <_PointKey, List<_Edge>>{};
    for (final edge in edges.values) {
      outgoing.putIfAbsent(edge.start, () => <_Edge>[]).add(edge);
    }
    final remaining = edges.keys.toSet();
    final loops = <List<_PointKey>>[];
    while (remaining.isNotEmpty) {
      final firstKey = remaining.first;
      final first = edges[firstKey]!;
      remaining.remove(firstKey);
      final loop = <_PointKey>[first.start];
      var current = first.end;
      var guard = 0;
      while (current != first.start && guard++ < edges.length + 8) {
        loop.add(current);
        final candidates = outgoing[current] ?? const <_Edge>[];
        _Edge? next;
        for (final candidate in candidates) {
          final candidateKey = _EdgeKey(candidate.start, candidate.end);
          if (remaining.contains(candidateKey)) {
            next = candidate;
            remaining.remove(candidateKey);
            break;
          }
        }
        if (next == null) break;
        current = next.end;
      }
      if (current == first.start && loop.length >= 4) {
        loops.add(_simplifyLoop(loop));
      }
    }
    return loops;
  }

  static List<_PointKey> _simplifyLoop(List<_PointKey> loop) {
    var simplified = loop;
    var changed = true;
    while (changed && simplified.length > 3) {
      changed = false;
      final next = <_PointKey>[];
      for (var i = 0; i < simplified.length; i++) {
        final prev =
            simplified[(i - 1 + simplified.length) % simplified.length];
        final point = simplified[i];
        final after = simplified[(i + 1) % simplified.length];
        final collinear = (prev.x == point.x && point.x == after.x) ||
            (prev.y == point.y && point.y == after.y);
        if (collinear) {
          changed = true;
          continue;
        }
        next.add(point);
      }
      simplified = next;
    }
    return simplified;
  }

  static void _addLoop(
    Path path,
    List<_PointKey> loop,
    Set<_PointKey> roundedCorners,
    double radius,
  ) {
    if (loop.length < 3) return;
    final first = loop.first;
    final firstEntry = _cornerEntry(
      first,
      loop.last,
      loop[1],
      roundedCorners,
      radius,
    );
    path.moveTo(firstEntry.dx, firstEntry.dy);
    for (var i = 0; i < loop.length; i++) {
      final prev = loop[(i - 1 + loop.length) % loop.length];
      final point = loop[i];
      final next = loop[(i + 1) % loop.length];
      final r = _cornerRadius(point, prev, next, roundedCorners, radius);
      if (r <= 0) {
        path.lineTo(point.x.toDouble(), point.y.toDouble());
        continue;
      }
      final entry = _axisPointToward(point, prev, r);
      final exit = _axisPointToward(point, next, r);
      path.lineTo(entry.dx, entry.dy);
      path.quadraticBezierTo(
        point.x.toDouble(),
        point.y.toDouble(),
        exit.dx,
        exit.dy,
      );
    }
    path.close();
  }

  static Offset _cornerEntry(
    _PointKey point,
    _PointKey prev,
    _PointKey next,
    Set<_PointKey> roundedCorners,
    double radius,
  ) {
    final r = _cornerRadius(point, prev, next, roundedCorners, radius);
    return r <= 0
        ? Offset(point.x.toDouble(), point.y.toDouble())
        : _axisPointToward(point, prev, r);
  }

  static double _cornerRadius(
    _PointKey point,
    _PointKey prev,
    _PointKey next,
    Set<_PointKey> roundedCorners,
    double radius,
  ) {
    if (radius <= 0 || !roundedCorners.contains(point)) return 0.0;
    final prevLength =
        ((point.x - prev.x).abs() + (point.y - prev.y).abs()).toDouble();
    final nextLength =
        ((point.x - next.x).abs() + (point.y - next.y).abs()).toDouble();
    final maxRadius =
        ((prevLength < nextLength ? prevLength : nextLength) / 2.0 - 0.5)
            .clamp(0.0, double.infinity)
            .toDouble();
    return radius.clamp(0.0, maxRadius).toDouble();
  }

  static Offset _axisPointToward(_PointKey from, _PointKey toward, double by) {
    final dx = toward.x.compareTo(from.x).toDouble();
    final dy = toward.y.compareTo(from.y).toDouble();
    return Offset(from.x + dx * by, from.y + dy * by);
  }

  static bool _connectorTouchesTop(Rect rect, Rect connector) {
    return connector.bottom >= rect.top &&
        connector.top <= rect.top &&
        connector.right > rect.left &&
        connector.left < rect.right;
  }

  static bool _connectorTouchesBottom(Rect rect, Rect connector) {
    return connector.top <= rect.bottom &&
        connector.bottom >= rect.bottom &&
        connector.right > rect.left &&
        connector.left < rect.right;
  }

  static double _medianHeight(List<Rect> rects) {
    final heights = rects.map((rect) => rect.height).toList()..sort();
    if (heights.isEmpty) return 1.0;
    return heights[heights.length ~/ 2].clamp(1.0, double.infinity).toDouble();
  }

  static Rect _pixelRect(Rect rect, Size size) {
    return Rect.fromLTRB(
      rect.left.clamp(0.0, size.width).toDouble().floorToDouble(),
      rect.top.clamp(0.0, size.height).toDouble().floorToDouble(),
      rect.right.clamp(0.0, size.width).toDouble().ceilToDouble(),
      rect.bottom.clamp(0.0, size.height).toDouble().ceilToDouble(),
    );
  }

  static String _formatRects(List<Rect> rects) {
    if (rects.isEmpty) return '[]';
    return rects
        .map((rect) =>
            '(${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)} '
            '${rect.right.toStringAsFixed(1)},${rect.bottom.toStringAsFixed(1)})')
        .join(' ');
  }
}

class _PointKey {
  final int x;
  final int y;

  const _PointKey(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is _PointKey && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

class _EdgeKey {
  final _PointKey start;
  final _PointKey end;

  const _EdgeKey(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is _EdgeKey && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

class _Edge {
  final _PointKey start;
  final _PointKey end;

  const _Edge(this.start, this.end);
}
