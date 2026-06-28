part of 'content_creator_screen.dart';

extension _ContentCreatorFeed on _ContentCreatorScreenState {
  // ---------------------------------------------------------------------------
  // Controls auto-hide
  // ---------------------------------------------------------------------------

  void _handleCreatorTap() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible) {
      _setContentCreatorState(() => _controlsVisible = true);
    }
    _scheduleControlsHide();
  }

  /// While a session (recording/STT) is active the controls fade away after a
  /// few seconds; a tap brings them back. When idle they stay visible.
  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    final tState = ref.read(teleprompterProvider);
    final sessionActive = _isRecording ||
        _recordStartInFlight ||
        tState.isListening ||
        tState.isStarting;
    if (!sessionActive) return;
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _setContentCreatorState(() => _controlsVisible = false);
    });
  }

  /// Called when a recording/STT session starts so the controls reveal once and
  /// then auto-hide.
  void _onCreatorSessionActivated() {
    _setContentCreatorState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  // ---------------------------------------------------------------------------
  // Camera feed layers
  // ---------------------------------------------------------------------------

  Widget _creatorCameraCover() {
    final controller = _cameraController;
    if (!_isInit || controller == null || !controller.value.isInitialized) {
      return _buildCameraFallback();
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize!.height,
          height: controller.value.previewSize!.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildCreatorCameraLayer(AppSettings settings, String feedMode) {
    if (feedMode == AppSettings.contentCreatorFeedFull) {
      // Camera fills the whole background; a soft scrim keeps the text legible.
      return Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _creatorCameraCover(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Color(0xAA000000)],
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Default 'strip': bottom-40% preview with the eye-contact vignette + HUD.
    return Positioned.fill(
      child: Column(
        children: [
          const Spacer(flex: 6),
          Expanded(
            flex: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _creatorCameraCover(),
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.85,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.4, 0.7, 1.0],
                    ),
                  ),
                ),
                CustomPaint(painter: _LensHUDPainter(), child: Container()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorBubble(AppSettings settings) {
    final shape = settings.contentCreatorBubbleShape;
    final isCircle = shape == AppSettings.contentCreatorBubbleCircle;
    final double w = isCircle ? 140 : 128;
    final double h = isCircle ? 140 : 168;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final defaultPos = Offset(screen.width - w - 16, screen.height - h - 232);
    final minTop = media.padding.top + 8;

    double clampLeft(double x) => x.clamp(8.0, screen.width - w - 8);
    double clampTop(double y) => y.clamp(minTop, screen.height - h - 8);

    final pos = _bubbleOffset ?? defaultPos;
    final radius = BorderRadius.circular(
      isCircle
          ? w / 2
          : (shape == AppSettings.contentCreatorBubbleRectangle ? 4 : 18),
    );

    return Positioned(
      left: clampLeft(pos.dx),
      top: clampTop(pos.dy),
      width: w,
      height: h,
      child: GestureDetector(
        // Drag the bubble anywhere instead of fixed corner offsets.
        onPanUpdate: (details) {
          final base = _bubbleOffset ?? defaultPos;
          _setContentCreatorState(() {
            _bubbleOffset = Offset(
              clampLeft(base.dx + details.delta.dx),
              clampTop(base.dy + details.delta.dy),
            );
          });
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0xFFFFBF00), width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: ClipRRect(borderRadius: radius, child: _creatorCameraCover()),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Prompter layer
  // ---------------------------------------------------------------------------

  Widget _buildCreatorPrompterLayer(
    Script? script,
    AppSettings settings,
    dynamic tState,
    bool audioOnly,
    String feedMode,
  ) {
    // Strip keeps the prompter in the top 60%; full/bubble/audio use the whole
    // height. Over the full-background camera the page colour drops away.
    final fullHeight =
        audioOnly || feedMode != AppSettings.contentCreatorFeedStrip;
    final transparentBg =
        !audioOnly && feedMode == AppSettings.contentCreatorFeedFull;

    final scroll = SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: 40,
        bottom: MediaQuery.of(context).size.height * 0.3,
        left: 20,
        right: 20,
      ),
      child: _buildPrompterContent(script, settings, tState,
          transparentBg: transparentBg),
    );

    final Widget content = fullHeight
        ? scroll
        : Column(
            children: [
              Expanded(flex: 6, child: scroll),
              const Spacer(flex: 4),
            ],
          );

    return Positioned.fill(
      child: SafeArea(
        child: KeyedSubtree(key: _creatorSurfaceKey, child: content),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Overlays
  // ---------------------------------------------------------------------------

  Widget _buildRecordTimerChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
    );
  }

  Widget _buildCountdownBadge() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$_countdown',
        style: const TextStyle(
          color: Color(0xFFFFBF00),
          fontSize: 80,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCreatorReadingLine(AppSettings settings) {
    return Positioned(
      top: MediaQuery.of(context).size.height * settings.scrollLead - 2,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          height: 3,
          color: Color(settings.currentWordColor).withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _buildCreatorReadFade(AppSettings settings) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: MediaQuery.of(context).size.height * settings.scrollLead + 20,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(settings.scriptBgColor)
                    .withValues(alpha: settings.readFadeIntensity),
                Color(settings.scriptBgColor)
                    .withValues(alpha: settings.readFadeIntensity * 0.6),
                Colors.transparent,
              ],
              stops: const [0.0, 0.7, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Smooth auto-scroll that follows the spoken word (ported from present mode).
  // ---------------------------------------------------------------------------

  void _scrollToWordIndex(int index) {
    if (index < 0 || index >= _wordKeys.length) return;
    if (!_scrollController.hasClients) return;
    final ctx = _wordKeys[index].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;

    final settings = ref.read(settingsProvider);
    final screenH = MediaQuery.of(context).size.height;
    final targetY = screenH * settings.scrollLead;
    final wordPos =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
    final rowProgress = _visualRowProgress(index, box);
    final lineAdvance =
        (box.size.height * settings.lineSpacing).clamp(0.0, screenH * 0.22);
    final rawTarget = _scrollController.offset +
        wordPos.dy -
        targetY +
        rowProgress * lineAdvance;
    _scrollTarget =
        rawTarget.clamp(0.0, _scrollController.position.maxScrollExtent);

    if (!_smoothScrollActive) {
      _smoothScrollActive = true;
      _smoothScrollTimer?.cancel();
      _smoothScrollTimer =
          Timer.periodic(const Duration(milliseconds: 16), _smoothScrollTick);
    }
  }

  double _visualRowProgress(int index, RenderBox currentBox) {
    if (index < 0 || index >= _wordKeys.length) return 0.0;
    final currentDy = currentBox.localToGlobal(Offset.zero).dy;
    final tolerance = (currentBox.size.height * 0.7).clamp(10.0, 90.0);

    var rowStart = index;
    for (var i = index - 1; i >= 0; i--) {
      final box = _boxForWordIndex(i);
      if (box == null) break;
      if ((box.localToGlobal(Offset.zero).dy - currentDy).abs() > tolerance) {
        break;
      }
      rowStart = i;
    }
    var rowEnd = index;
    for (var i = index + 1; i < _wordKeys.length; i++) {
      final box = _boxForWordIndex(i);
      if (box == null) break;
      if ((box.localToGlobal(Offset.zero).dy - currentDy).abs() > tolerance) {
        break;
      }
      rowEnd = i;
    }
    final span = rowEnd - rowStart;
    if (span <= 0) return 0.0;
    return ((index - rowStart) / span).clamp(0.0, 1.0).toDouble();
  }

  RenderBox? _boxForWordIndex(int index) {
    if (index < 0 || index >= _wordKeys.length) return null;
    final ctx = _wordKeys[index].currentContext;
    if (ctx == null) return null;
    return ctx.findRenderObject() as RenderBox?;
  }

  void _smoothScrollTick(Timer timer) {
    if (!mounted || !_scrollController.hasClients) {
      timer.cancel();
      _smoothScrollActive = false;
      return;
    }
    final current = _scrollController.offset;
    final diff = _scrollTarget - current;
    if (diff.abs() < 0.5) {
      _scrollController.jumpTo(_scrollTarget);
      timer.cancel();
      _smoothScrollActive = false;
      return;
    }
    final next = current + diff * 0.12;
    _scrollController
        .jumpTo(next.clamp(0.0, _scrollController.position.maxScrollExtent));
  }
}
