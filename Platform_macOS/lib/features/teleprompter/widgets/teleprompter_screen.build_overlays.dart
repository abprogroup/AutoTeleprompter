part of 'teleprompter_screen.dart';

extension _TeleprompterBuildOverlayParts on _TeleprompterScreenState {
  Widget _buildDebugConsoleOverlay({
    required BuildContext context,
    required TeleprompterState tState,
    required Script? script,
    required AppSettings settings,
    required double debugConsoleBottom,
    required double debugConsoleHeight,
  }) {
    return Positioned(
      bottom: debugConsoleBottom,
      left: 6,
      right: 6,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: debugConsoleHeight,
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
                    'POS: ${tState.confirmedWordIndex}/${script?.words.where((w) => !w.isNewline).length ?? 0}',
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

  bool _sameHighlightColor(Color? a, Color? b) {
    if (a == null || b == null) return false;
    return a == b;
  }

  TextDirection _wordDirectionForDisplay(
    String text, {
    required TextDirection paragraphDirection,
  }) {
    final clean = _stripBidiIsolation(text);
    if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) return TextDirection.rtl;
    if (RegExp(r'[A-Za-z]').hasMatch(clean)) return TextDirection.ltr;
    return paragraphDirection;
  }

  TextDirection _paragraphDirectionFor(List<ScriptWord> paragraph) {
    for (final word in paragraph) {
      final clean = word.raw
          .replaceAll(_tagStripRe, '')
          .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
          .trim();
      if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) {
        return TextDirection.rtl;
      }
      if (RegExp(r'[A-Za-z]').hasMatch(clean)) {
        return TextDirection.ltr;
      }
    }
    return paragraph.first.effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
  }

  String _bidiIsolatedDisplayText(
    String text, {
    required TextDirection paragraphDirection,
  }) {
    // Each presenter word is already wrapped in a Directionality widget.
    // Adding Unicode isolates inside every word over-constrains mixed
    // Hebrew/English/neutral punctuation and can flip brackets/numbers.
    return text;
  }

  String _stripBidiIsolation(String text) =>
      text.replaceAll(RegExp('[\u200E\u200F\u2066\u2067\u2068\u2069]'), '');
}

class _PresenterDecorationPainter extends CustomPainter {
  final GlobalKey contentKey;
  final List<GlobalKey> wordKeys;
  final List<ScriptWord> words;
  final int confirmedWordIndex;
  final bool isManualMode;
  final MarkupDecorationType type;

  const _PresenterDecorationPainter({
    required this.contentKey,
    required this.wordKeys,
    required this.words,
    required this.confirmedWordIndex,
    required this.isManualMode,
    required this.type,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final contentContext = contentKey.currentContext;
    final contentBox = contentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null || !contentBox.attached) return;

    if (type == MarkupDecorationType.background) {
      final rectsByColor = <Color, List<Rect>>{};
      for (final word in words) {
        if (word.isNewline || word.index >= wordKeys.length) continue;
        final highlight = word.highlight;
        if (highlight == null) continue;
        final color = !isManualMode && word.index < confirmedWordIndex
            ? highlight.withOpacity(highlight.opacity * 0.15)
            : highlight;
        final rect = _rectForWord(word.index, contentBox);
        if (rect == null) continue;
        rectsByColor.putIfAbsent(color, () => <Rect>[]).add(rect);
      }
      final paint = Paint()..style = PaintingStyle.fill;
      for (final entry in rectsByColor.entries) {
        if (entry.key.opacity <= 0) continue;
        paint.color = entry.key;
        for (final rect in MarkupDecorationBoxMerger.merge(
          entry.value,
          rowTolerance: 8,
          gapTolerance: 54,
        )) {
          final radius = Radius.circular((rect.height * 0.10).clamp(2.0, 8.0));
          canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
        }
      }
      return;
    }

    final underlineRects = <Rect>[];
    for (final word in words) {
      if (word.isNewline ||
          !word.isUnderline ||
          word.index >= wordKeys.length) {
        continue;
      }
      final rect = _rectForWord(word.index, contentBox);
      if (rect != null) underlineRects.add(rect);
    }
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final rect in MarkupDecorationBoxMerger.merge(
      underlineRects,
      rowTolerance: 8,
      gapTolerance: 54,
    )) {
      final y = rect.bottom - (paint.strokeWidth * 0.5);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  Rect? _rectForWord(int index, RenderBox contentBox) {
    final context = wordKeys[index].currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: contentBox);
    return topLeft & box.size;
  }

  @override
  bool shouldRepaint(covariant _PresenterDecorationPainter oldDelegate) => true;
}
