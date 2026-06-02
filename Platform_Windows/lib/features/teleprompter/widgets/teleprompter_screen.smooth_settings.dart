part of 'teleprompter_screen.dart';

extension _TeleprompterSmoothSettingsParts on _TeleprompterScreenState {
  void _smoothScrollTick(Timer timer) {
    if (!mounted || !_scrollController.hasClients) {
      timer.cancel();
      _smoothScrollActive = false;
      return;
    }

    final current = _scrollController.offset;
    final diff = _scrollTarget - current;

    // Close enough - snap and stop
    if (diff.abs() < 0.2) {
      _scrollController.jumpTo(_scrollTarget);
      timer.cancel();
      _smoothScrollActive = false;
      return;
    }

    var step = diff * 0.035;
    step = step.clamp(-7.0, 7.0).toDouble();
    if (step.abs() < 0.25) step = diff.isNegative ? -0.25 : 0.25;
    final next = current + step;
    _scrollController
        .jumpTo(next.clamp(0.0, _scrollController.position.maxScrollExtent));
    _syncVisibleWordWindow();
  }

  void _showSettings() {
    _showControls();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => TeleprompterSettingsPanel(
        onFontSizeChanged: _preserveReadingPositionAfterLayoutChange,
        onLayoutChanged: () => _preserveReadingPositionAfterLayoutChange(0),
        onInvertColors: _togglePresenterColorInversion,
      ),
    );
  }
}
