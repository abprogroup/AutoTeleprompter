part of 'content_creator_screen.dart';

extension _ContentCreatorDebug on _ContentCreatorScreenState {
  void _logContentDebug(String message) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _contentDebugLogs.add('[$stamp] $message');
    if (_contentDebugLogs.length > 100) {
      _contentDebugLogs.removeRange(0, _contentDebugLogs.length - 100);
    }
    if (kDebugMode) debugPrint('[Content Creator] $message');
  }

  void _setContentDebugPinned(bool value) {
    _updateContentCreatorState(() {
      _contentDebugConsolePinned = value;
      if (_contentDebugConsolePinned) {
        _contentDebugConsoleMinimized = false;
      }
    });
  }

  void _setContentDebugExpanded(bool expanded) {
    _updateContentCreatorState(() {
      if (expanded) {
        _contentDebugConsoleMinimized = false;
        if (!_contentControlsVisible) _contentDebugConsolePinned = true;
      } else {
        _contentDebugConsoleMinimized = true;
      }
    });
  }

  Widget _buildContentCreatorDebugConsole(
    BuildContext context,
    TeleprompterState tState, {
    required double bottom,
    required double height,
    required bool expanded,
    required Color accentColor,
    required AppSettings settings,
    required int wordCount,
  }) {
    final statusLines = _contentDebugStatusLines(tState, settings, wordCount);
    return Positioned(
      bottom: bottom,
      left: expanded ? 6 : null,
      right: 6,
      width: expanded ? null : 360,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildContentDebugHeader(
              context,
              tState,
              expanded: expanded,
              accentColor: accentColor,
              wordCount: wordCount,
              statusLines: statusLines,
            ),
            if (expanded) _buildContentDebugLogList(tState, statusLines),
          ],
        ),
      ),
    );
  }

  List<String> _contentDebugStatusLines(
    TeleprompterState tState,
    AppSettings settings,
    int wordCount,
  ) {
    final controller = _cameraController;
    final preview = controller?.value.previewSize;
    final cameraName = _selectedCameraName ?? 'none';
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    return [
      'mode=${_cameraSourceModeLabel(_cameraSourceMode)}',
      'device=$cameraName',
      'resolution=${settings.videoResolution} preview=${preview == null ? 'none' : '${preview.width.round()}x${preview.height.round()}'}',
      'initGen=$_cameraInitGeneration init=$_isInit recording=$_isRecording pending=$_recordStartInFlight countdown=$_countdown',
      'recordingAudio=${settings.contentCreatorRecordingAudioMode} format=${settings.contentCreatorRecordingFormat}',
      'feed=${settings.contentCreatorFeedMode} layout=${settings.contentCreatorLayoutPreset} opacity=${settings.contentCreatorCameraOpacity.toStringAsFixed(2)}',
      'bubble=${settings.contentCreatorBubblePosition}/${settings.contentCreatorBubbleShape} size=${settings.contentCreatorBubbleSize.toStringAsFixed(2)} opacity=${settings.contentCreatorBubbleOpacity.toStringAsFixed(2)} offset=${settings.contentCreatorBubbleOffsetX.toStringAsFixed(2)},${settings.contentCreatorBubbleOffsetY.toStringAsFixed(2)}',
      'stt=${settings.sttEngine} language=${settings.languageMode}',
      'lock=${settings.allowScrollDuringActiveSession ? 'manual-override' : 'stt-owned'} scrollBar=${settings.manualScrollBarPlacement}',
      'scroll=${offset.toStringAsFixed(1)} line=${settings.scrollLead.toStringAsFixed(2)}',
      'word=$_activeWordIndex/${wordCount == 0 ? 0 : wordCount - 1} provider=${tState.confirmedWordIndex}',
      if (_cameraError != null) 'error=$_cameraError',
    ];
  }

  Widget _buildContentDebugHeader(
    BuildContext context,
    TeleprompterState tState, {
    required bool expanded,
    required Color accentColor,
    required int wordCount,
    required List<String> statusLines,
  }) {
    final isActive = _isRecording || tState.isListening;
    final label =
        _isRecording ? 'REC' : (tState.isListening ? 'LISTENING' : 'IDLE');
    final icon = _isRecording
        ? Icons.videocam
        : (tState.isListening ? Icons.mic : Icons.mic_off);
    final statusColor =
        isActive ? Colors.greenAccent : Colors.redAccent.shade100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A00),
        borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
      ),
      child: Row(
        children: [
          Icon(icon, color: statusColor, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ContentSoundLevelBar(
              level: tState.soundLevel,
              isListening: tState.isListening,
              isStarting: tState.isStarting,
              accentColor: accentColor,
              compact: !expanded,
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 8),
            Text(
              'POS: ${tState.confirmedWordIndex}/$wordCount',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            _contentDebugConsolePinned ? 'PIN DEV' : 'DEV',
            style: const TextStyle(color: Colors.orange, fontSize: 10),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: _contentDebugConsolePinned
                ? 'Unpin debug output'
                : 'Pin debug output',
            child: IconButton(
              icon: Icon(
                _contentDebugConsolePinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                color: Colors.orange,
                size: 16,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
              onPressed: () =>
                  _setContentDebugPinned(!_contentDebugConsolePinned),
            ),
          ),
          Tooltip(
            message: expanded ? 'Minimize debug output' : 'Expand debug output',
            child: IconButton(
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                color: Colors.orange,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _setContentDebugExpanded(!expanded),
            ),
          ),
          if (expanded)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined,
                  color: Colors.orange, size: 16),
              tooltip: 'Send Feedback',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FeedbackReportScreen(),
                ),
              ),
            ),
          if (expanded)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.orange, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                final text = [
                  ...statusLines,
                  ..._contentDebugLogs.reversed,
                  ...tState.debugLogs.reversed,
                ].join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Content Creator debug copied to clipboard',
                      style: TextStyle(color: Colors.black),
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContentDebugLogList(
    TeleprompterState tState,
    List<String> statusLines,
  ) {
    final logs = [
      ..._contentDebugLogs.reversed.map((log) => '[CONTENT] $log'),
      ...tState.debugLogs.reversed,
    ].take(80).toList();
    return Expanded(
      child: ListView(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          for (final line in statusLines.reversed)
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9.5,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          if (logs.isNotEmpty) const Divider(color: Colors.white12, height: 8),
          for (final line in logs)
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _contentDebugLogColor(line),
                fontSize: 9.5,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }

  Color _contentDebugLogColor(String log) {
    if (log.contains('[WAIT]') || log.contains('WAIT')) {
      return Colors.yellow.shade200;
    }
    if (log.contains('[ERROR]') ||
        log.contains('[WARN]') ||
        log.contains('SKIP') ||
        log.contains('FAILED') ||
        log.contains('error=')) {
      return Colors.redAccent.shade100;
    }
    if (log.contains('[STT]') || log.contains('STATUS')) {
      return Colors.cyan.shade200;
    }
    if (log.contains('[HEARTBEAT]') || log.contains('HEARTBEAT')) {
      return Colors.purple.shade200;
    }
    if (log.contains('[SESSION]') ||
        log.contains('[LANG]') ||
        log.contains('[CONTENT]')) {
      return Colors.blue.shade200;
    }
    if (log.contains('[MIC]') || log.contains('camera')) {
      return Colors.greenAccent.shade100;
    }
    return Colors.greenAccent;
  }
}

class _ContentSoundLevelBar extends StatelessWidget {
  final double level;
  final bool isListening;
  final bool isStarting;
  final Color accentColor;
  final bool compact;

  const _ContentSoundLevelBar({
    required this.level,
    required this.isListening,
    required this.isStarting,
    required this.accentColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final clampedLevel = level.clamp(0.0, 1.0).toDouble();
    final activeColor = isListening ? accentColor : Colors.white38;
    final iconSize = compact ? 12.0 : 16.0;
    final barHeight = compact ? 5.0 : 7.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(compact ? 999 : 8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 4 : 7,
        ),
        child: Row(
          children: [
            Icon(
              isStarting
                  ? Icons.hourglass_top
                  : (isListening ? Icons.graphic_eq : Icons.volume_off),
              color: activeColor,
              size: iconSize,
            ),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: clampedLevel,
                  minHeight: barHeight,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text(
                  '${(clampedLevel * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
