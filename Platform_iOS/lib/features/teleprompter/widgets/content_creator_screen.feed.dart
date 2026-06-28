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

  Widget _buildCreatorBubble() {
    return Positioned(
      right: 16,
      bottom: 224,
      width: 128,
      height: 168,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFBF00), width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: _creatorCameraCover(),
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
}
