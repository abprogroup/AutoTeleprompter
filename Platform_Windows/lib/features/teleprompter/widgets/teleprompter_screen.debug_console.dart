part of 'teleprompter_screen.dart';

extension _TeleprompterDebugConsoleParts on _TeleprompterScreenState {
  Widget _buildPresenterDebugConsole(
    BuildContext context,
    TeleprompterState tState, {
    required double bottom,
    required double height,
    required int wordCount,
  }) {
    return Positioned(
      bottom: bottom,
      left: 6,
      right: 6,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar with current status
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
                  const Spacer(),
                  Text(
                    'POS: ${tState.confirmedWordIndex}/${wordCount}',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'ðŸ”§ DEV',
                    style: TextStyle(color: Colors.orange, fontSize: 10),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: _debugConsoleMinimized
                        ? 'Expand debug output'
                        : 'Minimize debug output',
                    child: IconButton(
                      icon: Icon(
                        _debugConsoleMinimized
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setState(() {
                        _debugConsoleMinimized = !_debugConsoleMinimized;
                      }),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.copy, color: Colors.orange, size: 16),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      final text = tState.debugLogs.reversed.join('\n');
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Debug logs copied to clipboard',
                                style: TextStyle(color: Colors.black)),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Log list
            if (!_debugConsoleMinimized)
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: tState.debugLogs.length,
                  itemBuilder: (context, idx) {
                    final log =
                        tState.debugLogs[tState.debugLogs.length - 1 - idx];
                    Color logColor = Colors.greenAccent;
                    if (log.contains('â¸') || log.contains('WAIT')) {
                      logColor = Colors.yellow.shade200;
                    } else if (log.contains('âŒ') ||
                        log.contains('SKIP') ||
                        log.contains('â­')) {
                      logColor = Colors.redAccent.shade100;
                    } else if (log.contains('ðŸŽ¤') || log.contains('STATUS')) {
                      logColor = Colors.cyan.shade200;
                    } else if (log.contains('ðŸ’“') ||
                        log.contains('HEARTBEAT')) {
                      logColor = Colors.purple.shade200;
                    } else if (log.contains('ðŸš€') || log.contains('ðŸŒ')) {
                      logColor = Colors.blue.shade200;
                    }
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
}
