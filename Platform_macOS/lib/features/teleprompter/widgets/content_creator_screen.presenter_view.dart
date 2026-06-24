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
    required bool allowWordJump,
  }) {
    Widget wordList = Padding(
      key: _creatorContentKey,
      padding: EdgeInsets.only(
        left: MediaQuery.of(context).size.width * 0.05,
        right: MediaQuery.of(context).size.width * 0.05,
        top: MediaQuery.of(context).size.height *
            (settings.scrollLead + 0.06).clamp(0.24, 0.38).toDouble(),
        bottom: MediaQuery.of(context).size.height * 0.68,
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
              allowWordJump: allowWordJump,
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

    if (bookmarkWordIndexes.isNotEmpty) {
      wordList = Stack(
        clipBehavior: Clip.none,
        children: [
          wordList,
          PresenterBookmarkMarkerLayer(
            contentKey: _creatorContentKey,
            wordKeys: _wordKeys,
            words: script.words,
            bookmarkWordIndexes: bookmarkWordIndexes,
            color: Color(settings.currentWordColor),
            fontSize: presentationFontSize,
            lineSpacing: settings.lineSpacing,
            onTap: allowWordJump
                ? (index) => _jumpToContentWordIndex(index, immediate: true)
                : null,
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
    return wordList;
  }

  Widget _buildContentParagraph({
    required List<ScriptWord> para,
    required int activeWordIndex,
    required AppSettings settings,
    required Set<int> bookmarkWordIndexes,
    required double presentationFontSize,
    required double presenterWordGap,
    required bool allowWordJump,
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
      paraAlign = para.first.alignment;
      for (final word in para) {
        if (word.alignment == null) continue;
        paraAlign = word.alignment;
        break;
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
                presentationFontSize: presentationFontSize,
                allowWordJump: allowWordJump,
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
    required double presentationFontSize,
    required bool allowWordJump,
  }) {
    final i = word.index;
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
    final effectiveBg = trackingBgColor ??
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
    final useSmoothHighlightBand =
        userBgColor != null && trackingBgColor == null;
    final highlightRadius = Radius.circular(
      (effectiveFontSize * 0.08).clamp(2.0, 8.0),
    );
    final wordWidget = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: allowWordJump ? () => _jumpToContentWordIndex(i) : null,
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
    return wordWidget;
  }

  Color _contentWordTextColor({
    required ScriptWord word,
    required bool isCurrent,
    required bool isPast,
    required int activeWordIndex,
    required AppSettings settings,
  }) {
    Color baseColor;
    if (isCurrent) {
      baseColor = settings.showCurrentWordHighlight
          ? Color(settings.currentWordColor)
          : (settings.showUpcomingWordColor
              ? Color(settings.futureWordColor)
              : (word.textColor ?? Color(settings.futureWordColor)));
    } else if (isPast) {
      final base = settings.showUpcomingWordColor
          ? Color(settings.futureWordColor)
          : (word.textColor ?? Color(settings.futureWordColor));
      final pastDist = (word.index - activeWordIndex).abs();
      final opacity = pastDist <= 3
          ? settings.pastWordOpacity +
              (1.0 - settings.pastWordOpacity) * (1.0 - pastDist / 3.0) * 0.5
          : settings.pastWordOpacity;
      baseColor = base.withValues(alpha: opacity.clamp(0.0, 1.0));
    } else {
      baseColor = settings.showUpcomingWordColor
          ? Color(settings.futureWordColor)
          : (word.textColor ?? const Color(0xFFFFFFFF));
    }
    return ScriptColorInversionService.presenterTextColor(
      word: word,
      settings: settings,
      fallback: baseColor,
    );
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
    var hasLatin = false;
    for (final word in words) {
      final clean = word.raw.replaceAll(_contentCreatorTagStripRe, '').trim();
      if (clean.isEmpty) continue;
      if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) return true;
      if (RegExp(r'[A-Za-z]').hasMatch(clean)) hasLatin = true;
    }
    if (hasLatin) return false;
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
    final defaultSpace = fontSize * 0.33;
    final editorFontSize =
        settings.fontSize <= 0 ? fontSize : settings.fontSize;
    final presentationScale = (fontSize / editorFontSize).clamp(1.0, 2.5);
    final scaledWordSpacing = settings.wordSpacing * presentationScale;
    final minimumReadableGap = fontSize * 0.18;
    return (defaultSpace + scaledWordSpacing)
        .clamp(minimumReadableGap, 96.0)
        .toDouble();
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
      // Paint each highlight run on its own. A run's wrapped lines connect into
      // one rounded block, but two separate highlights that share a color and
      // sit on adjacent lines stay distinct (so spacing reads evenly).
      final runs = _highlightRuns();
      final sharedLanes = _highlightLanesForRuns(runs, size, contentBox);
      for (final run in runs) {
        _paintHighlightSegments(canvas, size, contentBox, run, sharedLanes);
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

  void _paintHighlightSegments(
    Canvas canvas,
    Size size,
    RenderBox contentBox,
    List<ScriptWord> run,
    List<Rect> sharedLanes,
  ) {
    final paintedWords = <({Color color, Rect rect})>[];
    for (final word in run) {
      final highlight = word.highlight;
      if (highlight == null) continue;
      final rect = _rectForWord(word.index, contentBox);
      if (rect == null) continue;
      paintedWords
          .add((color: _effectiveHighlightColor(word, highlight), rect: rect));
    }
    if (paintedWords.isEmpty) return;
    final runMerged = MarkupDecorationBoxMerger.merge(
      [for (final word in paintedWords) word.rect],
      rowTolerance: 8,
      gapTolerance: gapTolerance,
    );
    final runBands = _applyRowLanes(runMerged, sharedLanes);

    Color? segmentColor;
    final segmentRects = <Rect>[];

    void flushSegment() {
      final color = segmentColor;
      if (color == null || color.a <= 0 || segmentRects.isEmpty) {
        segmentRects.clear();
        segmentColor = null;
        return;
      }
      final merged = MarkupDecorationBoxMerger.merge(
        segmentRects,
        rowTolerance: 8,
        gapTolerance: gapTolerance,
      );
      final bands = _applyRowLanes(merged, sharedLanes);
      HighlightBandPainter.paintConnectedRegion(
        canvas,
        bands,
        color,
        size,
        radius: HighlightBandPainter.suggestedRadius(bands),
        connectorGapRatio: 0.95,
        maxConnectorGap: _maxPresenterConnectorGap(bands),
      );
      segmentRects.clear();
      segmentColor = null;
    }

    for (final word in paintedWords) {
      final color = word.color;
      if (segmentColor != null && segmentColor != color) {
        flushSegment();
      }
      segmentColor = color;
      segmentRects.add(word.rect);
    }
    flushSegment();
    _paintRunSeams(canvas, runBands, paintedWords);
  }

  List<Rect> _highlightLanesForRuns(
    List<List<ScriptWord>> runs,
    Size size,
    RenderBox contentBox,
  ) {
    final rects = <Rect>[];
    for (final run in runs) {
      for (final word in run) {
        final rect = _rectForWord(word.index, contentBox);
        if (rect != null) rects.add(rect);
      }
    }
    if (rects.isEmpty) return const [];
    final merged = MarkupDecorationBoxMerger.merge(
      rects,
      rowTolerance: 8,
      gapTolerance: gapTolerance,
    );
    return _backgroundBands(merged, size);
  }

  Color _effectiveHighlightColor(ScriptWord word, Color highlight) {
    if (word.index < activeWordIndex) {
      return highlight.withValues(alpha: highlight.a * 0.15);
    }
    return highlight;
  }

  /// Groups consecutive highlighted words into runs. Plain newlines do not
  /// break a run because a highlighted paragraph can wrap through block
  /// boundaries; real non-highlighted words still break the run.
  List<List<ScriptWord>> _highlightRuns() {
    final runs = <List<ScriptWord>>[];
    List<ScriptWord>? current;
    int? prevIndex;
    Color? prevColor;
    for (final word in words) {
      if (word.isNewline) continue;
      final color = word.highlight;
      if (word.index >= wordKeys.length) {
        current = null;
        prevIndex = null;
        prevColor = null;
        continue;
      }
      if (color == null) {
        if (current != null &&
            HighlightBandPainter.isIgnorableHighlightSeparator(
              raw: word.raw,
              normalized: word.normalized,
            )) {
          continue;
        }
        current = null;
        prevIndex = null;
        prevColor = null;
        continue;
      }
      final contiguous =
          prevIndex != null && word.index > prevIndex && prevColor == color;
      if (current == null || !contiguous) {
        current = <ScriptWord>[];
        runs.add(current);
      }
      current.add(word);
      prevIndex = word.index;
      prevColor = color;
    }
    return runs;
  }

  List<Rect> _backgroundBands(List<Rect> bands, Size size) {
    final sorted =
        bands.where((band) => band.width > 0 && band.height > 0).toList()
          ..sort((a, b) {
            final top = a.top.compareTo(b.top);
            return top != 0 ? top : a.left.compareTo(b.left);
          });
    if (sorted.isEmpty) return const [];

    return HighlightBandPainter.textLaneBands(
      sorted,
      size,
      topPaddingRatio: 0.15,
      bottomPaddingRatio: 0.15,
      minHeight: 8.0,
      maxHeight: 240.0,
    );
  }

  List<Rect> _applyRowLanes(List<Rect> bands, List<Rect> lanes) {
    if (bands.isEmpty || lanes.isEmpty) return const [];
    return [
      for (final band in bands)
        Rect.fromLTRB(
          band.left,
          _laneForBand(band, lanes).top,
          band.right,
          _laneForBand(band, lanes).bottom,
        ),
    ];
  }

  void _paintRunSeams(
    Canvas canvas,
    List<Rect> bands,
    List<({Color color, Rect rect})> paintedWords,
  ) {
    if (bands.length < 2 || paintedWords.isEmpty) return;
    final sorted = [...bands]..sort((a, b) => a.top.compareTo(b.top));
    final medianHeight = HighlightBandPainter.medianBandHeight(sorted);
    final maxGap = (medianHeight * 0.95)
        .clamp(2.0, _maxPresenterConnectorGap(sorted))
        .toDouble();
    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];
      final gap = next.top - current.bottom;
      if (gap <= 0 || gap > maxGap) continue;
      final left = current.left > next.left ? current.left : next.left;
      final right = current.right < next.right ? current.right : next.right;
      if (right - left <= 3.0) continue;
      final top = current.bottom.floorToDouble();
      final bottom = next.top.ceilToDouble();
      if (bottom <= top) continue;
      final currentColor = _colorForBand(current, paintedWords);
      final nextColor = _colorForBand(next, paintedWords);
      final seamColor =
          nextColor.a >= currentColor.a ? nextColor : currentColor;
      if (seamColor.a <= 0) continue;
      canvas.drawRect(
        Rect.fromLTRB(left.floorToDouble(), top, right.ceilToDouble(), bottom),
        Paint()..color = seamColor,
      );
    }
  }

  double _maxPresenterConnectorGap(List<Rect> bands) {
    if (bands.isEmpty) return 18.0;
    final medianHeight = HighlightBandPainter.medianBandHeight(bands);
    return (medianHeight * 1.1).clamp(18.0, 96.0).toDouble();
  }

  Color _colorForBand(Rect band, List<({Color color, Rect rect})> words) {
    var best = words.first;
    var bestScore = double.negativeInfinity;
    for (final word in words) {
      final overlapTop = band.top > word.rect.top ? band.top : word.rect.top;
      final overlapBottom =
          band.bottom < word.rect.bottom ? band.bottom : word.rect.bottom;
      final overlap =
          overlapBottom > overlapTop ? overlapBottom - overlapTop : 0.0;
      final centerDistance = (band.center.dy - word.rect.center.dy).abs();
      final score = (overlap * 1000.0) - centerDistance;
      if (score > bestScore) {
        bestScore = score;
        best = word;
      }
    }
    return best.color;
  }

  Rect _laneForBand(Rect band, List<Rect> lanes) {
    var bestLane = lanes.first;
    var bestScore = double.negativeInfinity;
    for (final lane in lanes) {
      final overlapTop = band.top > lane.top ? band.top : lane.top;
      final overlapBottom =
          band.bottom < lane.bottom ? band.bottom : lane.bottom;
      final overlap =
          overlapBottom > overlapTop ? overlapBottom - overlapTop : 0.0;
      final centerDistance = (band.center.dy - lane.center.dy).abs();
      final score = (overlap * 1000.0) - centerDistance;
      if (score > bestScore) {
        bestScore = score;
        bestLane = lane;
      }
    }
    return bestLane;
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
