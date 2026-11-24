part of 'teleprompter_screen.dart';

extension _TeleprompterPresenterWordListParts on _TeleprompterScreenState {
  Widget _buildPresenterWordList({
    required BuildContext context,
    required Script script,
    required _PreparedPresenterScript prepared,
    required TeleprompterState tState,
    required AppSettings settings,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
    required double presenterWordGap,
    required String layoutKey,
  }) {
    final horizontal = PresenterHorizontalMargins.resolve(
      viewportWidth: MediaQuery.sizeOf(context).width,
      sideMargin: settings.presenterSideMargin,
      horizontalOffset: settings.presenterHorizontalOffset,
    );
    final verticalPad = MediaQuery.sizeOf(context).height * 0.45;
    final rawParagraphs = prepared.rawParagraphs;

    TextAlign? alignmentOverride;
    if (settings.showAlignmentOverride) {
      switch (settings.textAlign) {
        case 'left':
          alignmentOverride = TextAlign.left;
          break;
        case 'right':
          alignmentOverride = TextAlign.right;
          break;
        default:
          alignmentOverride = TextAlign.center;
          break;
      }
    }

    Widget wordList = Padding(
      key: _presenterContentKey,
      padding: EdgeInsets.fromLTRB(
        horizontal.left,
        verticalPad,
        horizontal.right,
        verticalPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List<Widget>.generate(prepared.paragraphs.length, (i) {
          final para = prepared.paragraphs[i];
          if (para.isBlankLine) {
            final blankFontSize =
                ScriptTypographyService.blankLinePresentationFontSize(
                  rawParagraphs,
                  para.paragraphIndex,
                  presentationFontSize,
                );
            return SizedBox(
              key: _wordKeys[para.startWordIndex],
              height:
                  para.isHardBlank ? blankFontSize * settings.lineSpacing : 0.0,
            );
          }

          final paraAlign = alignmentOverride ?? para.scriptAlignment;
          final paraFontSize =
              ScriptTypographyService.paragraphPresentationFontSize(
                para.rawWords,
                presentationFontSize,
              );
          final paraWordGap = ScriptTypographyService.presenterWordGap(
            paraFontSize,
            settings.wordSpacing,
          );
          return _PresenterParagraphView(
            key: ValueKey('para_${para.startWordIndex}'),
            paragraph: para,
            controller: _wordIndexController,
            wordKeys: _wordKeys,
            settings: settings,
            presentationFontSize: presentationFontSize,
            paraFontSize: paraFontSize,
            paraWordGap: paraWordGap,
            wrapAlignment: _toWrapAlignment(paraAlign, settings, para.isRtl),
            onParagraphTapUp: _handlePresenterParagraphTapUp,
          );
        }, growable: false),
      ),
    );

    if (kUseCustomDocxDecorationPainting &&
        (prepared.hasHighlights || prepared.hasUnderlines)) {
      final decorationGap = ScriptTypographyService.maxScriptWordGap(
        rawParagraphs,
        presentationFontSize,
        settings.wordSpacing,
      );
      final gapTolerance = _decorationGapTolerance(decorationGap);
      wordList = Stack(
        clipBehavior: Clip.none,
        children: [
          if (prepared.hasHighlights)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable:
                        _wordIndexController.highlightDecorationVersion,
                    builder:
                        (context, version, _) => CustomPaint(
                          painter: _PresenterDecorationPainter(
                            contentKey: _presenterContentKey,
                            wordKeys: _wordKeys,
                            words: script.words,
                            highlightRuns: prepared.highlightRuns,
                            underlineWords: const [],
                            confirmedWordIndex:
                                _wordIndexController.displayWordIndex,
                            isManualMode: false,
                            type: MarkupDecorationType.background,
                            gapTolerance: gapTolerance,
                            layoutKey: layoutKey,
                            decorationVersion: version,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          wordList,
          if (prepared.hasUnderlines)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PresenterDecorationPainter(
                      contentKey: _presenterContentKey,
                      wordKeys: _wordKeys,
                      words: script.words,
                      highlightRuns: const [],
                      underlineWords: prepared.underlineWords,
                      confirmedWordIndex: 0,
                      isManualMode: false,
                      type: MarkupDecorationType.underline,
                      gapTolerance: gapTolerance,
                      underlineColor: Color(settings.futureWordColor),
                      layoutKey: layoutKey,
                      decorationVersion: 0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (bookmarkWordIndexes.isNotEmpty) {
      final speechActive = tState.isListening || tState.isStarting;
      wordList = Stack(
        clipBehavior: Clip.none,
        children: [
          wordList,
          PresenterBookmarkMarkerLayer(
            contentKey: _presenterContentKey,
            wordKeys: _wordKeys,
            words: script.words,
            bookmarkWordIndexes: bookmarkWordIndexes,
            color: Color(settings.currentWordColor),
            fontSize: presentationFontSize,
            lineSpacing: settings.lineSpacing,
            onTap: speechActive ? null : _tapPresenterBookmarkMarker,
          ),
        ],
      );
    }

    return wordList;
  }

  void _handlePresenterParagraphTapUp(
    _PreparedPresenterParagraph paragraph,
    Offset globalPosition,
  ) {
    final liveState = ref.read(teleprompterProvider);
    if (liveState.isListening || liveState.isStarting) return;
    for (final prep in paragraph.words) {
      final idx = prep.word.index;
      if (idx < 0 || idx >= _wordKeys.length) continue;
      final box = _wordKeys[idx].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(globalPosition);
      if (box.paintBounds.contains(local)) {
        _jumpToWordIndex(idx);
        return;
      }
    }
  }
}
