import 'dart:math' as math;

/// Pure horizontal column-margin and left/right lens-offset calculation
/// shared by Present mode and Content Creator mode.
class PresenterHorizontalMargins {
  static const double defaultBaseMarginFraction = 0.05;
  static const double minEdgeFraction = 0.02;
  static const double minColumnWidthFraction = 0.20;

  static const double minSideMargin = 0.0;
  static const double maxSideMargin = 0.35;

  static const double minHorizontalOffset = -0.30;
  static const double maxHorizontalOffset = 0.30;

  final double left;
  final double right;

  const PresenterHorizontalMargins({required this.left, required this.right});

  static double normalizeSideMargin(double? value) {
    if (value == null || !value.isFinite) return minSideMargin;
    return value.clamp(minSideMargin, maxSideMargin).toDouble();
  }

  static double normalizeHorizontalOffset(double? value) {
    if (value == null || !value.isFinite) return 0.0;
    return value.clamp(minHorizontalOffset, maxHorizontalOffset).toDouble();
  }

  /// Resolves pixel left/right padding for [viewportWidth] while preserving a
  /// minimum readable column width ([minColumnWidthFraction]) and safe edge
  /// inset ([minEdgeFraction]) at every slider combination.
  static PresenterHorizontalMargins resolve({
    required double viewportWidth,
    required double sideMargin,
    required double horizontalOffset,
  }) {
    if (!viewportWidth.isFinite || viewportWidth <= 0) {
      return const PresenterHorizontalMargins(left: 0, right: 0);
    }
    final margin = normalizeSideMargin(sideMargin);
    final offset = normalizeHorizontalOffset(horizontalOffset);
    final basePad = defaultBaseMarginFraction + margin;
    const maxCombinedPad = 1.0 - minColumnWidthFraction;

    var leftFrac = math.max(minEdgeFraction, basePad + offset);
    var rightFrac = math.max(minEdgeFraction, basePad - offset);
    final total = leftFrac + rightFrac;
    if (total > maxCombinedPad) {
      final excess = total - maxCombinedPad;
      if (offset >= 0) {
        leftFrac = math.max(minEdgeFraction, leftFrac - excess);
      } else {
        rightFrac = math.max(minEdgeFraction, rightFrac - excess);
      }
    }
    return PresenterHorizontalMargins(
      left: viewportWidth * leftFrac,
      right: viewportWidth * rightFrac,
    );
  }

  static String formatHorizontalOffsetLabel(double offset) {
    final pct = (normalizeHorizontalOffset(offset) * 100).round();
    if (pct == 0) return 'Center';
    if (pct < 0) return 'Left ${pct.abs()}%';
    return 'Right $pct%';
  }
}
