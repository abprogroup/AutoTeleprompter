part of 'teleprompter_screen.dart';

extension _TeleprompterDebugConsoleParts on _TeleprompterScreenState {
  Widget _buildPresenterDebugConsole(
    BuildContext context,
    TeleprompterState tState, {
    required double bottom,
    required double height,
    required bool expanded,
    required Color accentColor,
    required int wordCount,
  }) {
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A00),
                borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              ),
              child: Row(
                children: [
                  Icon(
                    tState.isListening ? Icons.mic : Icons.mic_off,
                    color: tState.isListening ? Colors.greenAccent : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tState.isListening ? 'LISTENING' : 'IDLE',
                    style: TextStyle(
                      color:
                          tState.isListening ? Colors.greenAccent : Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SoundLevelBar(
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
                      'POS: ${tState.confirmedWordIndex}/${wordCount == 0 ? 0 : wordCount - 1}',
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
                    _debugConsolePinned ? 'PIN DEV' : 'DEV',
                    style: const TextStyle(color: Colors.orange, fontSize: 10),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: _debugConsolePinned
                        ? 'Unpin debug output'
                        : 'Pin debug output',
                    child: IconButton(
                      icon: Icon(
                        _debugConsolePinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        color: Colors.orange,
                        size: 16,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 28),
                      onPressed: () =>
                          _setPresenterDebugPinned(!_debugConsolePinned),
                    ),
                  ),
                  Tooltip(
                    message: expanded
                        ? 'Minimize debug output'
                        : 'Expand debug output',
                    child: IconButton(
                      icon: Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _setPresenterDebugExpanded(!expanded),
                    ),
                  ),
                  if (expanded)
                    IconButton(
                      icon: const Icon(Icons.bug_report_outlined,
                          color: Colors.orange, size: 16),
                      tooltip: 'Send Feedback',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FeedbackReportScreen(),
                        ),
                      ),
                    ),
                  if (expanded)
                    IconButton(
                      icon: const Icon(Icons.copy,
                          color: Colors.orange, size: 16),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        final text = tState.debugLogs.reversed.join('\n');
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Debug logs copied to clipboard',
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
            ),
            if (expanded)
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: tState.debugLogs.length,
                  itemBuilder: (context, idx) {
                    final log =
                        tState.debugLogs[tState.debugLogs.length - 1 - idx];
                    final logColor = _debugLogColor(log);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        log,
                        style: TextStyle(
                          color: logColor,
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _debugLogColor(String log) {
    if (log.contains('[WAIT]') || log.contains('WAIT')) {
      return Colors.yellow.shade200;
    }
    if (log.contains('[ERROR]') ||
        log.contains('[WARN]') ||
        log.contains('SKIP') ||
        log.contains('FAILED')) {
      return Colors.redAccent.shade100;
    }
    if (log.contains('[STT]') || log.contains('STATUS')) {
      return Colors.cyan.shade200;
    }
    if (log.contains('[HEARTBEAT]') || log.contains('HEARTBEAT')) {
      return Colors.purple.shade200;
    }
    if (log.contains('[SESSION]') || log.contains('[LANG]')) {
      return Colors.blue.shade200;
    }
    if (log.contains('[MIC]')) {
      return Colors.greenAccent.shade100;
    }
    return Colors.greenAccent;
  }
}
