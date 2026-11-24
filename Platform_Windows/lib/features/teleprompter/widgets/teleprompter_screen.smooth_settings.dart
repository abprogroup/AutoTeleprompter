part of 'teleprompter_screen.dart';

extension _TeleprompterSmoothSettingsParts on _TeleprompterScreenState {
  void _smoothScrollFrame(Duration elapsed) {
    if (!mounted || !_scrollController.hasClients) {
      _cancelSmoothScroll();
      return;
    }

    final previous = _lastSmoothScrollTickElapsed;
    _lastSmoothScrollTickElapsed = elapsed;
    final dt =
        previous == null
            ? 1.0 / 60.0
            : (elapsed - previous).inMicroseconds / 1000000.0;

    final current = _scrollController.offset;
    final diff = _scrollTarget - current;

    // Close enough - snap and stop
    if (diff.abs() < 0.2) {
      _scrollController.jumpTo(_scrollTarget);
      _cancelSmoothScroll();
      return;
    }

    _suppressPresenterProgrammaticPositionCommit(immediate: false);
    final settings = ref.read(settingsProvider);
    final step = PresenterScrollMotion.step(
      diff,
      smoothness: settings.speechScrollSmoothness,
      speed: settings.speechScrollSpeed,
      deltaSeconds: dt,
    );
    final next = current + step;
    _scrollController.jumpTo(
      next.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
    _syncVisibleWordWindow();
  }

  void _showSettings() {
    _showControls();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => TeleprompterSettingsPanel(
        showSpeechScrollControls: true,
        onFontSizeChanged: _preserveReadingPositionAfterLayoutChange,
        onLayoutChanged: () => _preserveReadingPositionAfterLayoutChange(0),
        onInvertColors: _togglePresenterColorInversion,
      ),
    );
  }
}
