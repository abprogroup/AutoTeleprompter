part of 'teleprompter_screen.dart';

extension _TeleprompterChromeParts on _TeleprompterScreenState {
  Widget _buildPresenterControlsOverlay({
    required AppSettings settings,
    required TeleprompterState tState,
  }) {
    final showSpeedSlider = _shouldShowManualSpeedSlider(settings, tState);
    final showBottomSpeedSlider = showSpeedSlider &&
        settings.manualScrollBarPlacement == AppSettings.manualScrollBarBottom;
    final showControlBar = _controlsVisible;
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
        opacity: showBottomSpeedSlider || showControlBar ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: IgnorePointer(
          ignoring: !showBottomSpeedSlider && !showControlBar,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBottomSpeedSlider) _buildManualSpeedSlider(settings),
              AnimatedOpacity(
                opacity: showControlBar ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 240),
                child: IgnorePointer(
                  ignoring: !showControlBar,
                  child: _ControlBar(
                    isListening: tState.isListening,
                    isStarting: tState.isStarting,
                    isManualMode: settings.scrollMode == 'manual',
                    isManualScrolling: _manualScrolling,
                    isScrollingBackward: _scrollingBackward,
                    accentColor: Color(settings.currentWordColor),
                    onStart: settings.scrollMode == 'manual' &&
                            !tState.isListening &&
                            !tState.isStarting
                        ? _startManualScroll
                        : _requestAndStart,
                    onStartBackward: () => _startManualScroll(backward: true),
                    onStop: tState.isListening || tState.isStarting
                        ? () => ref
                            .read(teleprompterProvider.notifier)
                            .stopSession()
                        : settings.scrollMode == 'manual'
                            ? _stopManualScroll
                            : () => ref
                                .read(teleprompterProvider.notifier)
                                .stopSession(),
                    onReset: () {
                      if (settings.scrollMode == 'manual') {
                        _resetManual();
                      } else {
                        _resetPresenterPositionToStart();
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
                    onFontSizeChanged:
                        _preserveReadingPositionAfterLayoutChange,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowManualSpeedSlider(
    AppSettings settings,
    TeleprompterState tState,
  ) {
    return settings.scrollMode == 'manual';
  }

  Widget _buildFloatingManualSpeedSlider({
    required AppSettings settings,
    required TeleprompterState tState,
  }) {
    if (!_shouldShowManualSpeedSlider(settings, tState) ||
        settings.manualScrollBarPlacement ==
            AppSettings.manualScrollBarBottom) {
      return const SizedBox.shrink();
    }
    final placement = settings.manualScrollBarPlacement;
    final vertical = placement == AppSettings.manualScrollBarLeft ||
        placement == AppSettings.manualScrollBarRight;
    final slider = vertical
        ? RotatedBox(
            quarterTurns: placement == AppSettings.manualScrollBarLeft ? -1 : 1,
            child: SizedBox(
              width: MediaQuery.of(context).size.height * 0.58,
              child: _buildManualSpeedSlider(settings),
            ),
          )
        : _buildManualSpeedSlider(settings);
    return Positioned(
      top: placement == AppSettings.manualScrollBarTop ? 0 : null,
      bottom: placement == AppSettings.manualScrollBarTop ? null : 108,
      left: placement == AppSettings.manualScrollBarRight ? null : 0,
      right: placement == AppSettings.manualScrollBarLeft ? null : 0,
      child: SafeArea(
        child: vertical
            ? SizedBox(
                width: 52,
                height: MediaQuery.of(context).size.height * 0.58,
                child: Center(child: slider),
              )
            : slider,
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
          Tooltip(
            message: 'Reset manual speed to 0',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 34,
                height: 34,
              ),
              icon: const Icon(
                Icons.pause_circle_outline,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () {
                ref.read(settingsProvider.notifier).setScrollSpeed(0);
                _stopManualScroll();
              },
            ),
          ),
          const SizedBox(width: 6),
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
