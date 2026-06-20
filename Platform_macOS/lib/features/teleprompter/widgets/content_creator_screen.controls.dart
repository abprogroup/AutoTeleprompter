part of 'content_creator_screen.dart';

extension _ContentCreatorControls on _ContentCreatorScreenState {
  Widget _buildContentControlsOverlay({
    required AppSettings settings,
    required TeleprompterState tState,
  }) {
    final controlsAutoHideActive = _contentControlsAutoHideActive(tState);
    final showControls = _contentControlsVisible || !controlsAutoHideActive;
    return MouseRegion(
      onEnter: (_) {
        _contentControlsHovering = true;
        _showContentControlsFromHotZone();
      },
      onExit: (_) {
        _contentControlsHovering = false;
        _scheduleHideContentControls();
      },
      child: AnimatedOpacity(
        opacity: showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: IgnorePointer(
          ignoring: !showControls,
          child: _buildContentControlBar(settings, tState),
        ),
      ),
    );
  }

  Widget _buildContentControlBar(
    AppSettings settings,
    TeleprompterState tState,
  ) {
    final audioOnly = settings.contentCreatorRecordingFormat ==
        AppSettings.contentCreatorRecordingFormatWav;
    final isReady = audioOnly || _isActiveCameraInitialized();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.95),
            Colors.black.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _barIcon(Icons.arrow_back, 'Back to editor', _exitContentCreator),
            _barIcon(Icons.edit_note, 'Edit current position',
                _exitContentCreatorAtCurrentPosition),
            _barIcon(Icons.skip_previous, 'Previous bookmark',
                () => _jumpContentBookmark(-1)),
            _barText('A', 'Smaller font', () => _applyContentFontDelta(-4)),
            if (!settings.contentCreatorRecordingControlsSpeech)
              _contentSpeechButton(settings, tState),
            _recordButton(
              isReady,
              audioOnly: audioOnly,
              speechLinked: settings.contentCreatorRecordingControlsSpeech,
            ),
            _barText('A', 'Larger font', () => _applyContentFontDelta(4),
                large: true),
            _barIcon(Icons.bookmark_add_outlined, 'Add bookmark',
                _addContentBookmark),
            _barIcon(Icons.bookmark_remove_outlined, 'Remove bookmark',
                _isRecording ? null : _deleteContentBookmarkAtCurrentPosition),
            _barIcon(Icons.photo_camera, 'Camera source',
                _showContentCreatorSettings),
            _barIcon(Icons.tune, 'Prompter settings', _showPrompterSettings),
            _barIcon(
              _contentFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              _contentFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              _toggleContentFullscreen,
            ),
            _barIcon(Icons.skip_next, 'Next bookmark',
                () => _jumpContentBookmark(1)),
            _barIcon(Icons.replay, 'Restart script', _resetContentPosition),
            _barIcon(Icons.search, 'Search script', _showContentSearchDialog),
          ],
        ),
      ),
    );
  }

  Widget _contentSpeechButton(AppSettings settings, TeleprompterState tState) {
    final speechActive = tState.isListening || tState.isStarting;
    final manual = settings.scrollMode == 'manual' && !speechActive;
    final booting = !manual && tState.isStarting;
    final active = manual ? _contentManualScrolling : tState.isListening;
    final icon = !manual
        ? (booting ? Icons.hourglass_top : (active ? Icons.stop : Icons.mic))
        : (active ? Icons.pause : Icons.play_arrow);
    final tooltip = !manual
        ? (booting
            ? 'Starting speech-to-text'
            : (active ? 'Stop speech-to-text' : 'Start speech-to-text'))
        : (active ? 'Pause manual scroll' : 'Start manual scroll');
    final onTap = booting ? null : _toggleContentSpeechSession;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? Colors.red
            : (booting
                ? const Color(0xFFFFBF00).withValues(alpha: 0.72)
                : const Color(0xFFFFBF00)),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkResponse(
          onTap: onTap,
          customBorder: const CircleBorder(),
          containedInkWell: true,
          hoverColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.24),
          splashColor: Colors.white.withValues(alpha: 0.22),
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              icon,
              color: active ? Colors.white : Colors.black,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordButton(
    bool isReady, {
    required bool audioOnly,
    required bool speechLinked,
  }) {
    final canStopOrCancel = _isRecording || _recordStartInFlight;
    final icon = canStopOrCancel
        ? Icons.stop
        : (speechLinked
            ? (audioOnly ? Icons.record_voice_over : Icons.video_camera_front)
            : (audioOnly ? Icons.mic_none_outlined : Icons.videocam));
    final tooltip = _recordStartInFlight
        ? 'Cancel recording countdown'
        : (_isRecording
            ? 'Stop recording'
            : (audioOnly
                ? (speechLinked
                    ? 'Start audio recording + speech'
                    : 'Start audio recording')
                : (speechLinked
                    ? 'Start recording + speech'
                    : 'Start recording')));
    return GestureDetector(
      onTap: isReady || canStopOrCancel ? _toggleRecording : null,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: speechLinked && !canStopOrCancel
                  ? const Color(0xFFFFBF00)
                  : Colors.white,
              width: speechLinked && !canStopOrCancel ? 3 : 2,
            ),
          ),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording
                  ? Colors.red
                  : (_recordStartInFlight
                      ? const Color(0xFFFFBF00)
                      : (isReady
                          ? Colors.red
                          : Colors.red.withValues(alpha: 0.45))),
            ),
            child: Icon(
              icon,
              color: _recordStartInFlight ? Colors.black : Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget _barIcon(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon,
          color: onPressed == null ? Colors.white24 : Colors.white70),
    );
  }

  Widget _barText(String text, String tooltip, VoidCallback onPressed,
      {bool large = false}) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Text(
        text,
        style: TextStyle(
          color: Colors.white70,
          fontSize: large ? 22 : 16,
          fontWeight: large ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildContentSearchToolbar() {
    if (!_contentSearchToolbarVisible || _lastSearchQuery.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMatches = _contentSearchMatches.isNotEmpty;
    final activeApproximate = hasMatches &&
        _contentSearchMatchIndex >= 0 &&
        _contentSearchMatchIndex < _contentSearchMatches.length &&
        _contentSearchMatches[_contentSearchMatchIndex].isApproximate;
    final label = hasMatches
        ? '${activeApproximate ? 'Approx ' : ''}'
            '${_contentSearchMatchIndex + 1}/${_contentSearchMatches.length}'
        : '0/0';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x66FFBF00), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              _barIcon(Icons.keyboard_arrow_left, 'Previous result',
                  hasMatches ? () => _jumpContentSearchResult(-1) : null),
              SizedBox(
                width: 104,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _barIcon(Icons.keyboard_arrow_right, 'Next result',
                  hasMatches ? () => _jumpContentSearchResult(1) : null),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _lastSearchQuery,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              _barIcon(
                  Icons.search, 'Search new text', _showContentSearchDialog),
              _barIcon(Icons.close, 'Close search toolbar',
                  _closeContentSearchToolbar),
            ],
          ),
        ),
      ),
    );
  }
}
