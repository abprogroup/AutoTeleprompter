import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef WalkthroughTargetResolver = Rect? Function(BuildContext overlayContext);

class StableWalkthroughTarget {
  final GlobalKey? key;
  final WalkthroughTargetResolver? resolver;
  final double padding;
  final BorderRadius borderRadius;

  const StableWalkthroughTarget({
    this.key,
    this.resolver,
    this.padding = 0,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  }) : assert(key != null || resolver != null);

  Rect? resolve(BuildContext overlayContext) {
    final custom = resolver;
    if (custom != null) {
      final rect = custom(overlayContext);
      return rect?.inflate(padding);
    }
    final targetKey = key;
    if (targetKey == null) return null;
    return rectForKey(
      overlayContext: overlayContext,
      targetKey: targetKey,
      padding: padding,
    );
  }

  void ensureVisible() {
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    final scrollable = Scrollable.maybeOf(targetContext);
    if (scrollable == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  static Rect? rectForKey({
    required BuildContext overlayContext,
    required GlobalKey targetKey,
    double padding = 0,
  }) {
    final overlayBox = overlayContext.findRenderObject();
    final targetContext = targetKey.currentContext;
    if (overlayBox is! RenderBox || !overlayBox.hasSize) return null;
    if (targetContext == null) return null;
    final targetObject = targetContext.findRenderObject();
    if (targetObject is! RenderBox || !targetObject.hasSize) return null;
    final topLeft = overlayBox.globalToLocal(
      targetObject.localToGlobal(Offset.zero),
    );
    final bottomRight = overlayBox.globalToLocal(
      targetObject.localToGlobal(
        Offset(targetObject.size.width, targetObject.size.height),
      ),
    );
    return Rect.fromPoints(topLeft, bottomRight).inflate(padding);
  }
}

class StableWalkthroughOverlay extends StatefulWidget {
  final String stepId;
  final StableWalkthroughTarget? target;
  final Widget Function(
    BuildContext context,
    Rect? targetRect,
    BoxConstraints constraints,
  ) cardBuilder;
  final VoidCallback onClose;
  final Color dimColor;
  final Color accentColor;
  final double minStableDelta;
  final int maxMeasurePasses;

  const StableWalkthroughOverlay({
    super.key,
    required this.stepId,
    required this.target,
    required this.cardBuilder,
    required this.onClose,
    this.dimColor = const Color(0xAD000000),
    this.accentColor = const Color(0xFFFFBF00),
    this.minStableDelta = 1,
    this.maxMeasurePasses = 12,
  });

  @override
  State<StableWalkthroughOverlay> createState() =>
      _StableWalkthroughOverlayState();
}

class _StableWalkthroughOverlayState extends State<StableWalkthroughOverlay> {
  Rect? _lastMeasuredRect;
  Rect? _stableRect;
  Size? _lastOverlaySize;
  int _measurePass = 0;
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    _resetMeasurement();
  }

  @override
  void didUpdateWidget(covariant StableWalkthroughOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepId != widget.stepId ||
        oldWidget.target != widget.target ||
        oldWidget.minStableDelta != widget.minStableDelta) {
      _resetMeasurement();
    }
  }

  void _resetMeasurement() {
    _lastMeasuredRect = null;
    _stableRect = null;
    _measurePass = 0;
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      _measureTarget();
    });
  }

  void _measureTarget() {
    final overlayObject = context.findRenderObject();
    final overlaySize = overlayObject is RenderBox && overlayObject.hasSize
        ? overlayObject.size
        : null;
    if (overlaySize != null && overlaySize != _lastOverlaySize) {
      _lastOverlaySize = overlaySize;
      _lastMeasuredRect = null;
      _stableRect = null;
      _measurePass = 0;
    }

    widget.target?.ensureVisible();
    final measured = widget.target?.resolve(context);
    final clipped = _clipToOverlay(measured, overlaySize);
    final previous = _lastMeasuredRect;
    final stable = clipped == null ||
        (previous != null &&
            _rectsNearlyEqual(previous, clipped, widget.minStableDelta));

    // Show the very first measurement immediately rather than waiting for two
    // consecutive matching passes — otherwise every step transition guarantees
    // one visible frame with no highlight and the card in its fallback
    // position, then a jump once the "stable" rect finally lands.
    if ((stable || _stableRect == null) && _stableRect != clipped) {
      setState(() => _stableRect = clipped);
    }

    _lastMeasuredRect = clipped;
    _measurePass += 1;
    if (!stable && _measurePass < widget.maxMeasurePasses) {
      _scheduleMeasurement();
    } else if (_measurePass < 3) {
      _scheduleMeasurement();
    }
  }

  Rect? _clipToOverlay(Rect? rect, Size? overlaySize) {
    if (rect == null || overlaySize == null) return rect;
    final overlayRect = Offset.zero & overlaySize;
    if (!rect.overlaps(overlayRect)) return null;
    return rect.intersect(overlayRect);
  }

  bool _rectsNearlyEqual(Rect a, Rect b, double tolerance) {
    return (a.left - b.left).abs() <= tolerance &&
        (a.top - b.top).abs() <= tolerance &&
        (a.right - b.right).abs() <= tolerance &&
        (a.bottom - b.bottom).abs() <= tolerance;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: CustomPaint(
                    painter: _StableWalkthroughSpotlightPainter(
                      targetRect: _stableRect,
                      dimColor: widget.dimColor,
                      accentColor: widget.accentColor,
                      borderRadius: widget.target?.borderRadius ??
                          const BorderRadius.all(Radius.circular(16)),
                    ),
                  ),
                ),
                widget.cardBuilder(context, _stableRect, constraints),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StableWalkthroughSpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Color dimColor;
  final Color accentColor;
  final BorderRadius borderRadius;

  const _StableWalkthroughSpotlightPainter({
    required this.targetRect,
    required this.dimColor,
    required this.accentColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..addRect(Offset.zero & size)
      ..fillType = PathFillType.evenOdd;
    final target = targetRect;
    if (target != null) {
      overlayPath.addRRect(borderRadius.toRRect(target));
    }
    canvas.drawPath(overlayPath, Paint()..color = dimColor);

    if (target == null) return;
    final rrect = borderRadius.toRRect(target);
    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      )
      ..drawRRect(
        rrect.inflate(1.5),
        Paint()
          ..color = accentColor.withValues(alpha: 0.24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
  }

  @override
  bool shouldRepaint(covariant _StableWalkthroughSpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}
