part of 'content_creator_screen.dart';

extension _ContentCreatorScreenWidgets on _ContentCreatorScreenState {
  Widget _buildReadingSurfaceLayer() {
    final settings = ref.watch(settingsProvider);
    if (settings.contentCreatorFeedMode ==
        AppSettings.contentCreatorFeedBubble) {
      return const Positioned.fill(child: SizedBox.shrink());
    }
    final preset = settings.contentCreatorLayoutPreset;
    final topAlpha = switch (preset) {
      AppSettings.contentCreatorLayoutCamera => 0.40,
      AppSettings.contentCreatorLayoutBalanced => 0.52,
      _ => 0.64,
    };
    final midAlpha = switch (preset) {
      AppSettings.contentCreatorLayoutCamera => 0.22,
      AppSettings.contentCreatorLayoutBalanced => 0.34,
      _ => 0.48,
    };
    final lowerAlpha = switch (preset) {
      AppSettings.contentCreatorLayoutCamera => 0.04,
      AppSettings.contentCreatorLayoutBalanced => 0.08,
      _ => 0.14,
    };
    final lead = settings.scrollLead.clamp(0.18, 0.42).toDouble();
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: topAlpha),
                Colors.black.withValues(alpha: topAlpha),
                Colors.black.withValues(alpha: midAlpha),
                Colors.black.withValues(alpha: lowerAlpha),
                Colors.black.withValues(alpha: 0.04),
              ],
              stops: [
                0.0,
                (lead + 0.10).clamp(0.0, 1.0),
                (lead + 0.28).clamp(0.0, 1.0),
                0.82,
                1.0,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraBackgroundLayer() {
    final settings = ref.watch(settingsProvider);
    if (_contentAudioOnlyMode(settings) ||
        settings.contentCreatorFeedMode ==
        AppSettings.contentCreatorFeedBubble) {
      return Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(settings.scriptBgColor)),
        ),
      );
    }
    return Positioned.fill(
      child: _cameraPreviewReady
          ? _buildFadedCameraPreviewLayer()
          : _buildCameraFallback(),
    );
  }

  Widget _buildCameraPreviewEntry(AppSettings settings) {
    return Stack(
      children: [
        Positioned.fill(
          child: _cameraPreviewReady
              ? _buildCameraPreviewBackdrop()
              : _buildCameraFallback(),
        ),
        Positioned(
          left: 24,
          top: 24,
          child: SafeArea(
            child: _previewPillButton(
              icon: Icons.arrow_back,
              label: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _previewPillButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera settings',
                  onPressed: _showContentCreatorSettings,
                ),
                const SizedBox(width: 14),
                _previewPillButton(
                  icon: Icons.check_circle_outline,
                  label: 'Confirm frame',
                  emphasized: true,
                  onPressed: _cameraPreviewReady ? _confirmContentFrame : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewPillButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool emphasized = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: emphasized ? const Color(0xFFFFBF00) : Colors.black87,
        foregroundColor: emphasized ? Colors.black : Colors.white,
        disabledBackgroundColor: Colors.black45,
        disabledForegroundColor: Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: emphasized ? const Color(0xFFFFBF00) : Colors.white24,
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreviewBackdrop() {
    if (!_cameraPreviewReady) return _buildCameraFallback();
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.56,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: _buildCameraPreviewFit(BoxFit.cover),
          ),
        ),
        _buildCameraPreviewFit(BoxFit.contain),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.95,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.22),
                Colors.black.withValues(alpha: 0.58),
              ],
              stops: const [0.48, 0.78, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentPresenterStage({
    required AppSettings settings,
    required Widget child,
  }) {
    final quarterTurns = ((settings.flipRotation ~/ 90) % 4 + 4) % 4;
    if (quarterTurns == 0) return Positioned.fill(child: child);
    if (quarterTurns.isEven) {
      return Positioned.fill(
        child: ClipRect(
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: child,
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
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentReadFadeOverlay(AppSettings settings) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final center = (settings.scrollLead + 0.05).clamp(0.0, 1.0).toDouble();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: screenHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: settings.readFadeIntensity),
                Colors.black.withValues(
                  alpha: settings.readFadeIntensity * 0.56,
                ),
                Colors.transparent,
                Colors.transparent,
              ],
              stops: [
                0.0,
                (center - 0.16).clamp(0.0, 1.0).toDouble(),
                center,
                1.0,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentReadingLine(AppSettings settings) {
    final size = MediaQuery.sizeOf(context);
    final color = Color(settings.currentWordColor);
    final decoration = BoxDecoration(
      color: color.withValues(alpha: 0.46),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.22),
          blurRadius: 8,
        ),
      ],
    );
    if (_contentUsesVerticalReadingLine(settings)) {
      final x = _contentReadingLineCoordinate(settings, size);
      return Positioned(
        left: x - 1.0,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Container(width: 2, decoration: decoration),
        ),
      );
    }
    final y = _contentReadingLineCoordinate(settings, size);
    return Positioned(
      top: y - 1.0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(height: 2, decoration: decoration),
      ),
    );
  }

  Widget _buildFadedCameraPreviewLayer() {
    if (!_cameraPreviewReady) return _buildCameraFallback();
    final settings = ref.watch(settingsProvider);
    final opacity = switch (settings.contentCreatorLayoutPreset) {
      AppSettings.contentCreatorLayoutCamera =>
        (settings.contentCreatorCameraOpacity + 0.10).clamp(0.45, 1.0),
      AppSettings.contentCreatorLayoutBalanced =>
        settings.contentCreatorCameraOpacity.clamp(0.35, 1.0),
      _ => (settings.contentCreatorCameraOpacity * 0.78).clamp(0.28, 0.82),
    }
        .toDouble();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.34,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: settings.contentCreatorFeedBlur,
                sigmaY: settings.contentCreatorFeedBlur,
              ),
              child: _buildCameraPreviewFit(BoxFit.cover),
            ),
          ),
          Opacity(
            opacity: opacity,
            child: _buildCameraPreviewFit(BoxFit.contain),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(
                    alpha: settings.contentCreatorTextScrim,
                  ),
                  Colors.black.withValues(
                    alpha: settings.contentCreatorTextScrim * 0.42,
                  ),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.62),
                ],
                stops: const [0.0, 0.22, 0.50, 0.78, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.92,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(
                    alpha: settings.contentCreatorVignetteIntensity * 0.45,
                  ),
                  Colors.black.withValues(
                    alpha: settings.contentCreatorVignetteIntensity,
                  ),
                ],
                stops: const [0.35, 0.74, 1.0],
              ),
            ),
          ),
          CustomPaint(
            painter: _LensHUDPainter(),
            child: Container(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraBubble(AppSettings settings) {
    if (!_cameraPreviewReady) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final shape = settings.contentCreatorBubbleShape;
    final isCircle = shape == AppSettings.contentCreatorBubbleShapeCircle;
    final isTriangle = shape == AppSettings.contentCreatorBubbleShapeTriangle;
    final shortestSide = size.shortestSide;
    final width = isCircle || isTriangle
        ? (shortestSide * settings.contentCreatorBubbleSize)
            .clamp(56.0, shortestSide * 0.82)
            .toDouble()
        : (size.width * settings.contentCreatorBubbleSize)
            .clamp(64.0, size.width * 0.56)
            .toDouble();
    final preview = _cameraController?.value.previewSize;
    final aspect = preview == null || preview.height == 0
        ? 16 / 9
        : preview.width / preview.height;
    final height = (isCircle || isTriangle)
        ? width
        : (width / aspect).clamp(64.0, size.height * 0.46).toDouble();
    final effectiveWidth = width;
    final maxRadius = (effectiveWidth < height ? effectiveWidth : height) / 2;
    final radius = switch (shape) {
      AppSettings.contentCreatorBubbleShapeRectangle => 8.0,
      AppSettings.contentCreatorBubbleShapeCircle => maxRadius,
      AppSettings.contentCreatorBubbleShapeTriangle => 0.0,
      _ => (maxRadius * settings.contentCreatorBubbleRoundness)
          .clamp(0.0, maxRadius)
          .toDouble(),
    };
    const margin = 22.0;
    final position = settings.contentCreatorBubblePosition;
    final alignTop = position == AppSettings.contentCreatorBubbleTopLeft ||
        position == AppSettings.contentCreatorBubbleTopRight;
    final alignLeft = position == AppSettings.contentCreatorBubbleBottomLeft ||
        position == AppSettings.contentCreatorBubbleTopLeft;
    final horizontalShift = size.width * settings.contentCreatorBubbleOffsetX;
    final verticalShift = size.height * settings.contentCreatorBubbleOffsetY;
    final maxSideInset = (size.width - effectiveWidth).clamp(0.0, size.width);
    final maxVerticalInset =
        (size.height - height - 108.0).clamp(0.0, size.height);
    final leftInset = alignLeft
        ? (margin + horizontalShift).clamp(0.0, maxSideInset).toDouble()
        : null;
    final rightInset = alignLeft
        ? null
        : (margin - horizontalShift).clamp(0.0, maxSideInset).toDouble();
    final topInset = alignTop
        ? (margin + MediaQuery.paddingOf(context).top + verticalShift)
            .clamp(0.0, maxVerticalInset)
            .toDouble()
        : null;
    final bottomInset = alignTop
        ? null
        : (108.0 - verticalShift).clamp(0.0, maxVerticalInset).toDouble();
    final previewWidget = _buildCameraPreviewFit(BoxFit.cover);
    final clippedPreview = switch (shape) {
      AppSettings.contentCreatorBubbleShapeCircle =>
        ClipOval(child: previewWidget),
      AppSettings.contentCreatorBubbleShapeTriangle => ClipPath(
          clipper: _TriangleBubbleClipper(),
          child: previewWidget,
        ),
      _ => ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: previewWidget,
        ),
    };
    final bubbleShell = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.52),
            blurRadius: 24,
            spreadRadius: 3,
          ),
        ],
      ),
      child: clippedPreview,
    );
    final shapedBubble = isTriangle
        ? ClipPath(
            clipper: _TriangleBubbleClipper(),
            child: bubbleShell,
          )
        : bubbleShell;
    return Positioned(
      top: topInset,
      bottom: bottomInset,
      left: leftInset,
      right: rightInset,
      width: effectiveWidth,
      height: height,
      child: IgnorePointer(
        child: Opacity(
          opacity: settings.contentCreatorBubbleOpacity,
          child: shapedBubble,
        ),
      ),
    );
  }

  Widget _buildCameraPreviewFit(BoxFit fit) {
    final controller = _cameraController;
    final preview = controller?.value.previewSize;
    if (controller == null ||
        preview == null ||
        !controller.value.isInitialized) {
      return _buildCameraFallback(compact: true);
    }
    return ClipRect(
      child: FittedBox(
        fit: fit,
        child: SizedBox(
          width: preview.width,
          height: preview.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildRecordingTimerHud() {
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.circle, color: Colors.white, size: 8),
            const SizedBox(width: 6),
            Text(
              _formatTimer(_recordSeconds),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingExportHud() {
    final progress = (_recordExportProgress ?? 0.0).clamp(0.0, 1.0);
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFBF00)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saving recording',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              color: const Color(0xFFFFBF00),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(44),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  spreadRadius: 12,
                ),
              ],
            ),
            child: Text(
              '$_countdown',
              style: const TextStyle(
                color: Color(0xFFFFBF00),
                fontSize: 92,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentResumeBlocker() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withValues(alpha: 0.18),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFBF00)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFFBF00),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Preparing resume choice...',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LensHUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFBF00).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const radius = 60.0;
    const bracketSize = 12.0;

    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius + bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius - bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius + bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius, centerY + radius - bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius - bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius, centerY + radius - bracketSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TriangleBubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
