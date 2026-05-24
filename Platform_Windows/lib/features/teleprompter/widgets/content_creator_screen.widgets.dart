part of 'content_creator_screen.dart';

extension _ContentCreatorScreenWidgets on _ContentCreatorScreenState {
  Widget _buildCameraFallback() {
    if (_isCameraInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
      );
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white54, size: 34),
            const SizedBox(height: 10),
            Text(
              _cameraError ?? 'Camera is unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFBF00),
                side: const BorderSide(color: Color(0xFFFFBF00)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContentCreatorSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Recording',
                  style: TextStyle(
                    color: Color(0xFFFFBF00),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['480p', '720p', '1080p'].map((resolution) {
                    final selected = settings.videoResolution == resolution;
                    return ChoiceChip(
                      label: Text(resolution),
                      selected: selected,
                      onSelected: (_) => _setVideoResolution(resolution),
                      selectedColor: const Color(0xFFFFBF00),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: const Color(0xFF1E1E1E),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: this.context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const TeleprompterSettingsPanel(),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Teleprompter settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrompterContent(
    Script? script,
    AppSettings settings,
    int activeWordIndex,
  ) {
    if (script == null || script.isEmpty) {
      return const Center(
        child: Text('No script loaded.', style: TextStyle(color: Colors.white)),
      );
    }

    final paragraphs = <List<ScriptWord>>[];
    List<ScriptWord> currentParagraph = [];
    for (final word in script.words) {
      if (word.isNewline) {
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph);
          currentParagraph = [];
        }
        paragraphs.add([word]);
      } else {
        currentParagraph.add(word);
      }
    }
    if (currentParagraph.isNotEmpty) paragraphs.add(currentParagraph);

    return Container(
      color: Color(settings.scriptBgColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: paragraphs.map<Widget>((para) {
          if (para.length == 1 && para[0].isNewline) {
            return SizedBox(
              key: para[0].index < _wordKeys.length
                  ? _wordKeys[para[0].index]
                  : null,
              height: settings.fontSize * 1.5 + (settings.lineSpacing * 4),
            );
          }

          final firstWord = para.first;
          final paraDir =
              firstWord.effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
          final paraAlign = firstWord.alignment;

          return Padding(
            padding:
                EdgeInsetsDirectional.only(bottom: settings.lineSpacing * 6),
            child: Align(
              alignment: _toAlignment(paraAlign, settings),
              child: Directionality(
                textDirection: paraDir,
                child: Wrap(
                  textDirection: paraDir,
                  alignment: _toWrapAlignment(paraAlign, settings),
                  children: para.map<Widget>((word) {
                    final i = word.index;
                    final isCurrent = i == activeWordIndex;
                    final isPast = i < activeWordIndex;
                    final displayText = word.raw.replaceAll(
                        RegExp(
                            r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg)(?:=[^\]]+)?\]|\*\*'),
                        '');

                    Color wordColor;
                    final futureColor =
                        word.textColor ?? Color(settings.futureWordColor);
                    if (isCurrent) {
                      wordColor = Color(settings.currentWordColor);
                    } else if (isPast) {
                      wordColor = futureColor.withValues(
                          alpha: settings.pastWordOpacity);
                    } else {
                      wordColor = futureColor;
                    }

                    final effectiveFontSize = word.fontSize != null
                        ? settings.fontSize * (word.fontSize! / 17.0)
                        : settings.fontSize;

                    return Directionality(
                      textDirection: word.effectiveRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Container(
                        key: i < _wordKeys.length ? _wordKeys[i] : null,
                        padding: EdgeInsets.only(right: settings.wordSpacing),
                        child: Text(
                          '$displayText ',
                          style: TextStyle(
                            fontSize: effectiveFontSize,
                            fontWeight:
                                word.isBold ? FontWeight.bold : FontWeight.w500,
                            fontStyle: word.isItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            letterSpacing: settings.letterSpacing,
                            color: wordColor,
                            decoration: word.isUnderline
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Alignment _toAlignment(TextAlign? paraAlign, AppSettings settings) {
    if (paraAlign == TextAlign.center ||
        (paraAlign == null && settings.textAlign == 'center')) {
      return Alignment.center;
    }
    if (paraAlign == TextAlign.right ||
        (paraAlign == null && settings.textAlign == 'right')) {
      return Alignment.centerRight;
    }
    return Alignment.centerLeft;
  }

  WrapAlignment _toWrapAlignment(TextAlign? paraAlign, AppSettings settings) {
    if (paraAlign == TextAlign.center ||
        (paraAlign == null && settings.textAlign == 'center')) {
      return WrapAlignment.center;
    }
    if (paraAlign == TextAlign.right ||
        (paraAlign == null && settings.textAlign == 'right')) {
      return WrapAlignment.end;
    }
    return WrapAlignment.start;
  }
}

class _LensHUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFBF00).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const radius = 60.0;
    const bracketSize = 12.0;

    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius + bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius - bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius + bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius, centerY + radius - bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius - bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius, centerY + radius - bracketSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
