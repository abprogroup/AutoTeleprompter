part of 'teleprompter_screen.dart';

extension _TeleprompterChromeParts on _TeleprompterScreenState {
  Widget _buildPresenterControlsOverlay({
    required AppSettings settings,
    required TeleprompterState tState,
  }) {
    return MouseRegion(
      onEnter: (_) {
        if (Platform.isWindows) {
          _windowsControlsHovering = true;
          _showWindowsControlsFromHotZone();
        }
      },
      onExit: (_) {
        if (Platform.isWindows) {
          _windowsControlsHovering = false;
          _scheduleHideControls();
        }
      },
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.scrollMode == 'manual')
                _buildManualSpeedSlider(settings),
              _ControlBar(
                isListening: tState.isListening,
                isStarting: tState.isStarting,
                isManualMode: settings.scrollMode == 'manual',
                isManualScrolling: _manualScrolling,
                isScrollingBackward: _scrollingBackward,
                accentColor: Color(settings.currentWordColor),
                onStart: settings.scrollMode == 'manual'
                    ? _startManualScroll
                    : _requestAndStart,
                onStartBackward: () => _startManualScroll(backward: true),
                onStop: settings.scrollMode == 'manual'
                    ? _stopManualScroll
                    : () =>
                        ref.read(teleprompterProvider.notifier).stopSession(),
                onReset: () {
                  if (settings.scrollMode == 'manual') {
                    _resetManual();
                  } else {
                    ref.read(teleprompterProvider.notifier).resetPosition();
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                onBack: () {
                  _exitPresentation();
                },
                onEditCurrentPosition: _editCurrentPresenterPosition,
                onSettings: _showSettings,
                onAddBookmark: _addPresenterBookmark,
                onRemoveBookmark: _deletePresenterBookmarkAtCurrentPosition,
                onPreviousBookmark: () => _jumpPresenterBookmark(-1),
                onNextBookmark: () => _jumpPresenterBookmark(1),
                onSearch: _showSearchDialog,
                isFullscreen: _presenterFullscreen,
                onToggleFullscreen: _togglePresenterFullscreen,
                onFontSizeChanged: _preserveReadingPositionAfterLayoutChange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualSpeedSlider(AppSettings settings) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.speed, color: Colors.white54, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: settings.scrollSpeed,
              min: -300,
              max: 300,
              divisions: 120,
              activeColor: Color(settings.currentWordColor),
              inactiveColor: Colors.white24,
              onChanged: (v) {
                ref.read(settingsProvider.notifier).setScrollSpeed(v);
                if (_manualScrolling && v != 0) {
                  return;
                } else if (v != 0 && !_manualScrolling) {
                  _startManualScroll();
                } else if (v == 0) {
                  _stopManualScroll();
                }
              },
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${settings.scrollSpeed.round() > 0 ? "+" : ""}${settings.scrollSpeed.round()} wpm',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
