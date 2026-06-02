part of 'teleprompter_screen.dart';

class _PresenterScrollAxis {
  final bool horizontal;
  final double direction;

  const _PresenterScrollAxis({
    required this.horizontal,
    required this.direction,
  });
}

extension _TeleprompterPresenterTransformParts on _TeleprompterScreenState {
  Widget _buildPresenterReadingSurface({
    required AppSettings settings,
    required Widget child,
  }) {
    Widget transformed = SizedBox.expand(child: child);
    if (settings.mirrorHorizontal || settings.mirrorVertical) {
      transformed = Transform.scale(
        scaleX: settings.mirrorHorizontal ? -1 : 1,
        scaleY: settings.mirrorVertical ? -1 : 1,
        child: transformed,
      );
    }

    final quarterTurns = ((settings.flipRotation ~/ 90) % 4 + 4) % 4;
    if (quarterTurns == 0) return Positioned.fill(child: transformed);
    if (quarterTurns.isEven) {
      return Positioned.fill(
        child: ClipRect(
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: transformed,
          ),
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    return Positioned.fill(
      child: ClipRect(
        child: Center(
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: transformed,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresenterReadFadeOverlay(AppSettings settings) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: screenHeight * settings.scrollLead + 20,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(settings.scriptBgColor).withValues(
                  alpha: settings.readFadeIntensity,
                ),
                Color(settings.scriptBgColor).withValues(
                  alpha: settings.readFadeIntensity * 0.6,
                ),
                Colors.transparent,
              ],
              stops: const [0.0, 0.7, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresenterReadingLine(AppSettings settings) {
    return Positioned(
      top: MediaQuery.sizeOf(context).height * settings.scrollLead - 2,
      left: 0,
      right: 0,
      child: Container(
        key: _presenterReadingLineKey,
        height: 3,
        color: Color(settings.currentWordColor).withValues(alpha: 0.35),
      ),
    );
  }

  _PresenterScrollAxis _presenterScrollAxis() {
    final ctx = _presenterContentKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return const _PresenterScrollAxis(horizontal: false, direction: 1);
    }

    final origin = box.localToGlobal(Offset.zero);
    final down = box.localToGlobal(const Offset(0, 100));
    final delta = down - origin;
    final horizontal = delta.dx.abs() > delta.dy.abs();
    final rawDirection = horizontal ? delta.dx : delta.dy;
    return _PresenterScrollAxis(
      horizontal: horizontal,
      direction: rawDirection < 0 ? -1 : 1,
    );
  }

  double _presenterAxisValue(Offset point, _PresenterScrollAxis axis) {
    return axis.horizontal ? point.dx : point.dy;
  }

  double _presenterReadingLineAxis(_PresenterScrollAxis axis) {
    final ctx = _presenterReadingLineKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      final center = box.localToGlobal(
        Offset(box.size.width / 2, box.size.height / 2),
      );
      return _presenterAxisValue(center, axis);
    }

    final size = MediaQuery.sizeOf(context);
    return axis.horizontal
        ? size.width * settingsProviderFallbackScrollLead()
        : size.height * settingsProviderFallbackScrollLead();
  }

  double settingsProviderFallbackScrollLead() {
    return ref.read(settingsProvider).scrollLead;
  }

  double _presenterBoxAxisCenter(
    RenderBox box,
    _PresenterScrollAxis axis,
  ) {
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    return _presenterAxisValue(center, axis);
  }

  Rect _presenterGlobalRect(RenderBox box) {
    final points = [
      box.localToGlobal(Offset.zero),
      box.localToGlobal(Offset(box.size.width, 0)),
      box.localToGlobal(Offset(0, box.size.height)),
      box.localToGlobal(Offset(box.size.width, box.size.height)),
    ];
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final point in points) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
