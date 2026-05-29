part of 'teleprompter_screen.dart';

extension _TeleprompterPresenterWordListParts on _TeleprompterScreenState {
  Widget _buildPresenterWordList({
    required BuildContext context,
    required Script script,
    required List<List<ScriptWord>> paragraphs,
    required TeleprompterState tState,
    required AppSettings settings,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
    required double presenterWordGap,
  }) {
    Widget wordList = Padding(
      key: _presenterContentKey,
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
        vertical: MediaQuery.of(context).size.height * 0.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: paragraphs.map<Widget>((para) {
          if (para.length == 1 && para[0].isNewline) {
            final isHard = para[0].raw == '\n\n';
            return SizedBox(
              key: _wordKeys[para[0].index],
              height:
                  isHard ? presentationFontSize * settings.lineSpacing : 0.0,
            );
          }

          final firstWord = para.first;
          final paragraphRtl = _paragraphIsRtl(para);
          final paraDir = paragraphRtl ? TextDirection.rtl : TextDirection.ltr;
          TextAlign? paraAlign;
          if (settings.showAlignmentOverride) {
            switch (settings.textAlign) {
              case 'left':
                paraAlign = TextAlign.left;
                break;
              case 'right':
                paraAlign = TextAlign.right;
                break;
              default:
                paraAlign = TextAlign.center;
                break;
            }
          } else {
            for (final word in para) {
              if (word.alignment == null) continue;
              paraAlign = word.alignment;
              break;
            }
            paraAlign ??= firstWord.alignment;
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: presentationFontSize *
                  (settings.lineSpacing - 1.0).clamp(0.0, 1.0),
            ),
            child: Directionality(
              textDirection: paraDir,
              child: Wrap(
                textDirection: paraDir,
                alignment: _toWrapAlignment(paraAlign, settings, paragraphRtl),
                spacing: presenterWordGap,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: para.asMap().entries.map<Widget>((entry) {
                  return _buildPresenterWord(
                    para: para,
                    localWordIndex: entry.key,
                    word: entry.value,
                    tState: tState,
                    settings: settings,
                    paragraphDirection: paraDir,
                    bookmarkWordIndexes: bookmarkWordIndexes,
                    presentationFontSize: presentationFontSize,
                  );
                }).toList(),
              ),
            ),
          )
              .animate(key: ValueKey('para_${para.first.index}'))
              .fadeIn(duration: 300.ms);
        }).toList(),
      ),
    );

    if (kUseCustomDocxDecorationPainting) {
      wordList = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PresenterDecorationPainter(
                  contentKey: _presenterContentKey,
                  wordKeys: _wordKeys,
                  words: script.words,
                  confirmedWordIndex: tState.confirmedWordIndex,
                  isManualMode: false,
                  type: MarkupDecorationType.background,
                  gapTolerance: _decorationGapTolerance(presenterWordGap),
                ),
              ),
            ),
          ),
          wordList,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PresenterDecorationPainter(
                  contentKey: _presenterContentKey,
                  wordKeys: _wordKeys,
                  words: script.words,
                  confirmedWordIndex: tState.confirmedWordIndex,
                  isManualMode: false,
                  type: MarkupDecorationType.underline,
                  gapTolerance: _decorationGapTolerance(presenterWordGap),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (settings.mirrorHorizontal || settings.mirrorVertical) {
      wordList = Transform.scale(
        scaleX: settings.mirrorHorizontal ? -1 : 1,
        scaleY: settings.mirrorVertical ? -1 : 1,
        child: wordList,
      );
    }
    if (settings.flipRotation != 0) {
      wordList = RotatedBox(
        quarterTurns: settings.flipRotation ~/ 90,
        child: wordList,
      );
    }
    return wordList;
  }

  Widget _buildPresenterWord({
    required List<ScriptWord> para,
    required int localWordIndex,
    required ScriptWord word,
    required TeleprompterState tState,
    required AppSettings settings,
    required TextDirection paragraphDirection,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
  }) {
    final i = word.index;
    final hasBookmark = bookmarkWordIndexes.contains(i);
    final isCurrent = i == tState.confirmedWordIndex;
    final isPast = i < tState.confirmedWordIndex;
    final visibleWordText = word.raw
        .replaceAll(_tagStripRe, '')
        .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '');
    final displayText = _bidiIsolatedDisplayText(
      visibleWordText,
      paragraphDirection: paragraphDirection,
    );
    final wordDirection = _wordDirectionForDisplay(
      displayText,
      paragraphDirection: paragraphDirection,
    );

    final effectiveFontSize =
        word.fontSize != null ? word.fontSize! * 2.0 : presentationFontSize;
    final userBgColor = word.highlight;
    final trackingBgColor = isCurrent && settings.showCurrentWordHighlight
        ? Color(settings.currentWordColor).withValues(alpha: 0.3)
        : null;
    final effectiveBg = kUseCustomDocxDecorationPainting
        ? trackingBgColor
        : trackingBgColor ??
            (isPast ? userBgColor?.withValues(alpha: 0.15) : userBgColor);
    final textColor = _presenterWordTextColor(
      word: word,
      isCurrent: isCurrent,
      isPast: isPast,
      currentIndex: tState.confirmedWordIndex,
      settings: settings,
    );
    final joinsPreviousHighlight = _sameHighlightColor(
      userBgColor,
      localWordIndex > 0 ? para[localWordIndex - 1].highlight : null,
    );
    final joinsNextHighlight = _sameHighlightColor(
      userBgColor,
      localWordIndex + 1 < para.length
          ? para[localWordIndex + 1].highlight
          : null,
    );
    final useSmoothHighlightBand = !kUseCustomDocxDecorationPainting &&
        userBgColor != null &&
        trackingBgColor == null;
    final highlightRadius = Radius.circular(
      (effectiveFontSize * 0.08).clamp(2.0, 8.0),
    );
    final speechActive = tState.isListening || tState.isStarting;
    final wordWidget = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: speechActive ? null : () => _jumpToWordIndex(i),
      child: Directionality(
        textDirection: wordDirection,
        child: Container(
          key: _wordKeys[i],
          padding: EdgeInsets.zero,
          decoration: effectiveBg == null
              ? null
              : BoxDecoration(
                  color: effectiveBg,
                  borderRadius: useSmoothHighlightBand
                      ? BorderRadiusDirectional.horizontal(
                          start: joinsPreviousHighlight
                              ? Radius.zero
                              : highlightRadius,
                          end: joinsNextHighlight
                              ? Radius.zero
                              : highlightRadius,
                        )
                      : null,
                ),
          child: Text(
            displayText,
            style: TextStyle(
              fontSize: effectiveFontSize,
              fontWeight: word.isBold ? FontWeight.bold : FontWeight.w500,
              fontStyle: word.isItalic ? FontStyle.italic : FontStyle.normal,
              letterSpacing: settings.letterSpacing,
              wordSpacing: settings.wordSpacing,
              color: textColor,
              height: settings.lineSpacing,
              decoration: word.isUnderline && !kUseCustomDocxDecorationPainting
                  ? TextDecoration.underline
                  : null,
              decorationStyle: TextDecorationStyle.solid,
              decorationThickness: word.isUnderline ? 1.5 : null,
            ),
          ),
        ),
      ),
    );
    if (!hasBookmark) return wordWidget;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: 'Bookmark',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: speechActive ? null : () => _tapPresenterBookmarkMarker(i),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: effectiveFontSize * 0.06,
                vertical: effectiveFontSize * 0.04,
              ),
              child: Text(
                '\u00BB',
                style: TextStyle(
                  color: Color(settings.currentWordColor),
                  fontSize: effectiveFontSize * 0.62,
                  fontWeight: FontWeight.bold,
                  height: settings.lineSpacing,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: effectiveFontSize * 0.08),
        wordWidget,
      ],
    );
  }

  Color _presenterWordTextColor({
    required ScriptWord word,
    required bool isCurrent,
    required bool isPast,
    required int currentIndex,
    required AppSettings settings,
  }) {
    if (isCurrent) {
      return settings.showCurrentWordHighlight
          ? Color(settings.currentWordColor)
          : (settings.showUpcomingWordColor
              ? Color(settings.futureWordColor)
              : (word.textColor ?? Color(settings.futureWordColor)));
    }
    if (isPast) {
      final base = settings.showUpcomingWordColor
          ? Color(settings.futureWordColor)
          : (word.textColor ?? Color(settings.futureWordColor));
      final pastDist = (word.index - currentIndex).abs();
      final gradOpacity = pastDist <= 3
          ? settings.pastWordOpacity +
              (1.0 - settings.pastWordOpacity) * (1.0 - pastDist / 3.0) * 0.5
          : settings.pastWordOpacity;
      return base.withValues(alpha: gradOpacity.clamp(0.0, 1.0));
    }
    return settings.showUpcomingWordColor
        ? Color(settings.futureWordColor)
        : (word.textColor ?? const Color(0xFFFFFFFF));
  }
}
