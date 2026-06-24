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

  static Rect? rectForKey(
    BuildContext overlayContext,
    GlobalKey key, {
    double padding = 0,
  }) {
    final overlayObject = overlayContext.findRenderObject();
    final targetContext = key.currentContext;
    if (overlayObject is! RenderBox ||
        !overlayObject.hasSize ||
        targetContext == null) {
      return null;
    }
    final targetObject = targetContext.findRenderObject();
    if (targetObject is! RenderBox || !targetObject.hasSize) return null;
    final topLeft = overlayObject.globalToLocal(
      targetObject.localToGlobal(Offset.zero),
    );
    final bottomRight = overlayObject.globalToLocal(
      targetObject.localToGlobal(targetObject.size.bottomRight(Offset.zero)),
    );
    return Rect.fromPoints(topLeft, bottomRight).inflate(padding);
  }

  Rect? resolve(BuildContext overlayContext) {
    final custom = resolver;
    if (custom != null) return custom(overlayContext)?.inflate(padding);
    final targetKey = key;
    if (targetKey == null) return null;
    final overlayObject = overlayContext.findRenderObject();
    final targetContext = targetKey.currentContext;
    if (overlayObject is! RenderBox ||
        !overlayObject.hasSize ||
        targetContext == null) {
      return null;
    }
    final targetObject = targetContext.findRenderObject();
    if (targetObject is! RenderBox || !targetObject.hasSize) return null;
    final topLeft = overlayObject.globalToLocal(
      targetObject.localToGlobal(Offset.zero),
    );
    final bottomRight = overlayObject.globalToLocal(
      targetObject.localToGlobal(targetObject.size.bottomRight(Offset.zero)),
    );
    return Rect.fromPoints(topLeft, bottomRight).inflate(padding);
  }

  void ensureVisible() {
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    if (Scrollable.maybeOf(targetContext) == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
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

  const StableWalkthroughOverlay({
    super.key,
    required this.stepId,
    required this.target,
    required this.cardBuilder,
    required this.onClose,
    this.dimColor = const Color(0xAD000000),
    this.accentColor = const Color(0xFFFFBF00),
  });

  @override
  State<StableWalkthroughOverlay> createState() =>
      _StableWalkthroughOverlayState();
}

class _StableWalkthroughOverlayState extends State<StableWalkthroughOverlay> {
  Rect? _lastMeasured;
  Rect? _stableRect;
  Size? _lastSize;
  int _passes = 0;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant StableWalkthroughOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepId != widget.stepId ||
        oldWidget.target != widget.target) {
      _reset();
    }
  }

  void _reset() {
    _lastMeasured = null;
    _stableRect = null;
    _passes = 0;
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final object = context.findRenderObject();
    final size = object is RenderBox && object.hasSize ? object.size : null;
    if (size != null && size != _lastSize) {
      _lastSize = size;
      _lastMeasured = null;
      _stableRect = null;
      _passes = 0;
    }
    widget.target?.ensureVisible();
    final next = _clip(widget.target?.resolve(context), size);
    final previous = _lastMeasured;
    final stable = next == null ||
        (previous != null &&
            (previous.left - next.left).abs() <= 1 &&
            (previous.top - next.top).abs() <= 1 &&
            (previous.right - next.right).abs() <= 1 &&
            (previous.bottom - next.bottom).abs() <= 1);
    if (stable && _stableRect != next) setState(() => _stableRect = next);
    _lastMeasured = next;
    _passes += 1;
    if ((!stable && _passes < 12) || _passes < 3) _scheduleMeasure();
  }

  Rect? _clip(Rect? rect, Size? size) {
    if (rect == null || size == null) return rect;
    final overlay = Offset.zero & size;
    return rect.overlaps(overlay) ? rect.intersect(overlay) : null;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
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
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: CustomPaint(
                  painter: _WalkthroughSpotlightPainter(
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
          ),
        ),
      ),
    );
  }
}

class _WalkthroughSpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Color dimColor;
  final Color accentColor;
  final BorderRadius borderRadius;

  const _WalkthroughSpotlightPainter({
    required this.targetRect,
    required this.dimColor,
    required this.accentColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..fillType = PathFillType.evenOdd;
    final target = targetRect;
    if (target != null) path.addRRect(borderRadius.toRRect(target));
    canvas.drawPath(path, Paint()..color = dimColor);
    if (target == null) return;
    final rrect = borderRadius.toRRect(target);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _WalkthroughSpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}
