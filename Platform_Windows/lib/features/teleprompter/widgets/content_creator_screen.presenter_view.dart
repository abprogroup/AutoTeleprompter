part of 'content_creator_screen.dart';

extension _ContentCreatorPresenterView on _ContentCreatorScreenState {
  Widget _buildContentPresenterWordList({
    required BuildContext context,
    required Script script,
    required List<List<ScriptWord>> paragraphs,
    required int activeWordIndex,
    required AppSettings settings,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
    required double presenterWordGap,
  }) {
    Widget wordList = Padding(
      key: _creatorContentKey,
      padding: EdgeInsets.only(
        left: MediaQuery.of(context).size.width * 0.05,
        right: MediaQuery.of(context).size.width * 0.05,
        top: MediaQuery.of(context).size.height * 0.40,
        bottom: MediaQuery.of(context).size.height * 0.58,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final para in paragraphs)
            _buildContentParagraph(
              para: para,
              activeWordIndex: activeWordIndex,
              settings: settings,
              bookmarkWordIndexes: bookmarkWordIndexes,
              presentationFontSize: presentationFontSize,
              presenterWordGap: presenterWordGap,
            ),
        ],
      ),
    );

    if (kUseCustomDocxDecorationPainting) {
      wordList = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ContentDecorationPainter(
                  contentKey: _creatorContentKey,
                  wordKeys: _wordKeys,
                  words: script.words,
                  activeWordIndex: activeWordIndex,
                  type: MarkupDecorationType.background,
                  gapTolerance:
                      _contentDecorationGapTolerance(presenterWordGap),
                ),
              ),
            ),
          ),
          wordList,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ContentDecorationPainter(
                  contentKey: _creatorContentKey,
                  wordKeys: _wordKeys,
                  words: script.words,
                  activeWordIndex: activeWordIndex,
                  type: MarkupDecorationType.underline,
                  gapTolerance:
                      _contentDecorationGapTolerance(presenterWordGap),
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

  Widget _buildContentParagraph({
    required List<ScriptWord> para,
    required int activeWordIndex,
    required AppSettings settings,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
    required double presenterWordGap,
  }) {
    if (para.length == 1 && para[0].isNewline) {
      final isHard = para[0].raw == '\n\n';
      return SizedBox(
        key: _wordKeys[para[0].index],
        height: isHard ? presentationFontSize * settings.lineSpacing : 0.0,
      );
    }

    final paragraphRtl = _contentParagraphIsRtl(para);
    final paraDir = paragraphRtl ? TextDirection.rtl : TextDirection.ltr;
    TextAlign? paraAlign;
    if (settings.showAlignmentOverride) {
      paraAlign = switch (settings.textAlign) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      };
    } else {
      try {
        paraAlign = para.firstWhere((w) => w.alignment != null).alignment;
      } catch (_) {
        paraAlign = para.first.alignment;
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            presentationFontSize * (settings.lineSpacing - 1.0).clamp(0.0, 1.0),
      ),
      child: Directionality(
        textDirection: paraDir,
        child: Wrap(
          textDirection: paraDir,
          alignment: _contentWrapAlignment(paraAlign, settings, paragraphRtl),
          spacing: presenterWordGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final entry in para.asMap().entries)
              _buildContentWord(
                para: para,
                localWordIndex: entry.key,
                word: entry.value,
                activeWordIndex: activeWordIndex,
                settings: settings,
                paragraphDirection: paraDir,
                bookmarkWordIndexes: bookmarkWordIndexes,
                presentationFontSize: presentationFontSize,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentWord({
    required List<ScriptWord> para,
    required int localWordIndex,
    required ScriptWord word,
    required int activeWordIndex,
    required AppSettings settings,
    required TextDirection paragraphDirection,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
  }) {
    final i = word.index;
    final hasBookmark = bookmarkWordIndexes.contains(i);
    final isCurrent = i == activeWordIndex;
    final isPast = i < activeWordIndex;
    final visibleWordText = word.raw
        .replaceAll(_contentCreatorTagStripRe, '')
        .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '');
    final displayText = _contentBidiDisplayText(
      visibleWordText,
      paragraphDirection: paragraphDirection,
    );
    final wordDirection = _contentWordDirectionForDisplay(
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
    final joinsPreviousHighlight = _contentSameHighlightColor(
      userBgColor,
      localWordIndex > 0 ? para[localWordIndex - 1].highlight : null,
    );
    final joinsNextHighlight = _contentSameHighlightColor(
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
    final wordWidget = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _jumpToContentWordIndex(i),
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
              color: _contentWordTextColor(
                word: word,
                isCurrent: isCurrent,
                isPast: isPast,
                activeWordIndex: activeWordIndex,
                settings: settings,
              ),
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
            onTap: () => _jumpToContentWordIndex(i, immediate: true),
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

  Color _contentWordTextColor({
    required ScriptWord word,
    required bool isCurrent,
    required bool isPast,
    required int activeWordIndex,
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
      final pastDist = (word.index - activeWordIndex).abs();
      final opacity = pastDist <= 3
          ? settings.pastWordOpacity +
              (1.0 - settings.pastWordOpacity) * (1.0 - pastDist / 3.0) * 0.5
          : settings.pastWordOpacity;
      return base.withValues(alpha: opacity.clamp(0.0, 1.0));
    }
    return settings.showUpcomingWordColor
        ? Color(settings.futureWordColor)
        : (word.textColor ?? const Color(0xFFFFFFFF));
  }

  TextDirection _contentWordDirectionForDisplay(
    String text, {
    required TextDirection paragraphDirection,
  }) {
    if (RegExp(r'[\u0590-\u08FF]').hasMatch(text)) return TextDirection.rtl;
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return TextDirection.ltr;
    return paragraphDirection;
  }

  String _contentBidiDisplayText(
    String text, {
    required TextDirection paragraphDirection,
  }) {
    return text;
  }

  bool _contentParagraphIsRtl(List<ScriptWord> words) {
    for (final word in words) {
      final clean = word.raw.replaceAll(_contentCreatorTagStripRe, '').trim();
      if (clean.isEmpty) continue;
      if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) return true;
      if (RegExp(r'[A-Za-z]').hasMatch(clean)) return false;
    }
    return words.isNotEmpty && words.first.effectiveRtl;
  }

  WrapAlignment _contentWrapAlignment(
    TextAlign? paraAlign,
    AppSettings settings,
    bool isRtl,
  ) {
    final textAlign = paraAlign ?? (isRtl ? TextAlign.right : TextAlign.left);
    if (textAlign == TextAlign.center) return WrapAlignment.center;
    if (isRtl) {
      if (textAlign == TextAlign.left) return WrapAlignment.end;
      if (textAlign == TextAlign.right) return WrapAlignment.start;
    } else {
      if (textAlign == TextAlign.left) return WrapAlignment.start;
      if (textAlign == TextAlign.right) return WrapAlignment.end;
    }
    return WrapAlignment.center;
  }

  bool _contentSameHighlightColor(Color? a, Color? b) {
    if (a == null || b == null) return false;
    return a == b;
  }

  double _contentWordGap(double fontSize, AppSettings settings) {
    final defaultSpace = fontSize * 0.24;
    return (defaultSpace + settings.wordSpacing).clamp(0.0, 80.0).toDouble();
  }

  double _contentDecorationGapTolerance(double wordGap) {
    final dynamicTolerance = wordGap + 8.0;
    return dynamicTolerance < 18.0 ? 18.0 : dynamicTolerance;
  }
}

class _ContentDecorationPainter extends CustomPainter {
  final GlobalKey contentKey;
  final List<GlobalKey> wordKeys;
  final List<ScriptWord> words;
  final int activeWordIndex;
  final MarkupDecorationType type;
  final double gapTolerance;

  const _ContentDecorationPainter({
    required this.contentKey,
    required this.wordKeys,
    required this.words,
    required this.activeWordIndex,
    required this.type,
    required this.gapTolerance,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final contentBox =
        contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null || !contentBox.attached) return;

    if (type == MarkupDecorationType.background) {
      final rectsByColor = <Color, List<Rect>>{};
      for (final word in words) {
        if (word.isNewline || word.index >= wordKeys.length) continue;
        final highlight = word.highlight;
        if (highlight == null) continue;
        final color = word.index < activeWordIndex
            ? highlight.withValues(alpha: highlight.a * 0.15)
            : highlight;
        final rect = _rectForWord(word.index, contentBox);
        if (rect == null) continue;
        rectsByColor.putIfAbsent(color, () => <Rect>[]).add(rect);
      }
      final paint = Paint()..style = PaintingStyle.fill;
      for (final entry in rectsByColor.entries) {
        if (entry.key.a <= 0) continue;
        paint.color = entry.key;
        final merged = MarkupDecorationBoxMerger.merge(
          entry.value,
          rowTolerance: 8,
          gapTolerance: gapTolerance,
        );
        for (final rect in _backgroundBands(merged, size)) {
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
      gapTolerance: gapTolerance,
    )) {
      final y = rect.bottom - (paint.strokeWidth * 0.5);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  List<Rect> _backgroundBands(List<Rect> bands, Size size) {
    final sorted =
        bands.where((band) => band.width > 0 && band.height > 0).toList()
          ..sort((a, b) {
            final top = a.top.compareTo(b.top);
            return top != 0 ? top : a.left.compareTo(b.left);
          });
    if (sorted.isEmpty) return const [];

    final medianHeight = _medianHeight(sorted);
    final pad = (medianHeight * 0.07).clamp(3.0, 8.0).toDouble();
    final overlap = (medianHeight * 0.035).clamp(1.5, 4.0).toDouble();
    final maxAdjacentDistance = medianHeight * 1.75;
    final bridgeGapLimit = medianHeight * 0.65;
    final painted = [
      for (final band in sorted)
        Rect.fromLTRB(
          band.left,
          (band.top - pad).clamp(0.0, size.height).toDouble(),
          band.right,
          (band.bottom + pad).clamp(0.0, size.height).toDouble(),
        ),
    ];

    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];
      final centerDistance = next.center.dy - current.center.dy;
      if (centerDistance <= medianHeight * 0.25 ||
          centerDistance > maxAdjacentDistance) {
        continue;
      }
      final rowGap = next.top - current.bottom;
      if (rowGap > bridgeGapLimit) continue;
      final boundary = (current.bottom + next.top) / 2.0;
      if (boundary <= painted[i].top || boundary >= painted[i + 1].bottom) {
        continue;
      }
      painted[i] = Rect.fromLTRB(
        painted[i].left,
        painted[i].top,
        painted[i].right,
        (boundary + overlap).clamp(0.0, size.height).toDouble(),
      );
      painted[i + 1] = Rect.fromLTRB(
        painted[i + 1].left,
        (boundary - overlap).clamp(0.0, size.height).toDouble(),
        painted[i + 1].right,
        painted[i + 1].bottom,
      );
    }

    return painted;
  }

  double _medianHeight(List<Rect> rects) {
    final heights = rects.map((rect) => rect.height).toList()..sort();
    if (heights.isEmpty) return 1.0;
    return heights[heights.length ~/ 2].clamp(1.0, double.infinity).toDouble();
  }

  Rect? _rectForWord(int index, RenderBox contentBox) {
    final box =
        wordKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: contentBox);
    return topLeft & box.size;
  }

  @override
  bool shouldRepaint(covariant _ContentDecorationPainter oldDelegate) => true;
}
