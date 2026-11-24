part of 'teleprompter_screen.dart';

final _alignTagStripRe = RegExp(r'\[\/?align=[^\]]+\]');
final _bidiIsolationStripRe = RegExp('[\u200E\u200F\u2066\u2067\u2068\u2069]');
final _rtlCharRe = RegExp(r'[\u0590-\u08FF]');
final _latinCharRe = RegExp(r'[A-Za-z]');

class _PreparedPresenterWord {
  final ScriptWord word;
  final String displayText;
  final TextDirection wordDirection;
  final bool needsExplicitDirection;
  final bool joinsPreviousHighlight;
  final bool joinsNextHighlight;

  const _PreparedPresenterWord({
    required this.word,
    required this.displayText,
    required this.wordDirection,
    required this.needsExplicitDirection,
    required this.joinsPreviousHighlight,
    required this.joinsNextHighlight,
  });
}

class _PreparedPresenterParagraph {
  final int paragraphIndex;
  final List<ScriptWord> rawWords;
  final List<_PreparedPresenterWord> words;
  final bool isBlankLine;
  final bool isHardBlank;
  final int startWordIndex;
  final int endWordIndex;
  final bool isRtl;
  final TextDirection direction;
  final TextAlign? scriptAlignment;

  const _PreparedPresenterParagraph({
    required this.paragraphIndex,
    required this.rawWords,
    required this.words,
    required this.isBlankLine,
    required this.isHardBlank,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.isRtl,
    required this.direction,
    required this.scriptAlignment,
  });
}

class _PreparedPresenterScript {
  final String cacheKey;
  final List<List<ScriptWord>> rawParagraphs;
  final List<_PreparedPresenterParagraph> paragraphs;
  final int spokenWordCount;
  final List<int> wordToParagraphIndex;
  final List<List<ScriptWord>> highlightRuns;
  final List<int> highlightedWordIndices;
  final List<ScriptWord> underlineWords;

  const _PreparedPresenterScript({
    required this.cacheKey,
    required this.rawParagraphs,
    required this.paragraphs,
    required this.spokenWordCount,
    required this.wordToParagraphIndex,
    required this.highlightRuns,
    required this.highlightedWordIndices,
    required this.underlineWords,
  });

  bool get hasHighlights => highlightRuns.isNotEmpty;
  bool get hasUnderlines => underlineWords.isNotEmpty;

  /// Returns true if any highlighted word has index in `[startInclusive, endExclusive)`.
  /// Runs in O(log H) binary search so live reading across non-highlighted words
  /// triggers zero background `CustomPaint` repaints.
  bool hasHighlightedWordInRange(int startInclusive, int endExclusive) {
    if (highlightedWordIndices.isEmpty || startInclusive >= endExclusive) {
      return false;
    }
    var lo = 0;
    var hi = highlightedWordIndices.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (highlightedWordIndices[mid] < startInclusive) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < highlightedWordIndices.length &&
        highlightedWordIndices[lo] < endExclusive;
  }

  static _PreparedPresenterScript build(
    Script script, {
    required String cacheKey,
    required List<List<ScriptWord>> rawParagraphs,
  }) {
    final totalWords = script.words.length;
    final wordToParagraph = List<int>.filled(totalWords, -1);
    final paragraphs = <_PreparedPresenterParagraph>[];
    var spokenCount = 0;

    for (var paraIdx = 0; paraIdx < rawParagraphs.length; paraIdx++) {
      final para = rawParagraphs[paraIdx];
      if (para.isEmpty) continue;

      if (para.length == 1 && para[0].isNewline) {
        final nl = para[0];
        if (nl.index >= 0 && nl.index < totalWords) {
          wordToParagraph[nl.index] = paraIdx;
        }
        paragraphs.add(
          _PreparedPresenterParagraph(
            paragraphIndex: paraIdx,
            rawWords: para,
            words: const [],
            isBlankLine: true,
            isHardBlank: nl.raw == '\n\n',
            startWordIndex: nl.index,
            endWordIndex: nl.index,
            isRtl: false,
            direction: TextDirection.ltr,
            scriptAlignment: null,
          ),
        );
        continue;
      }

      final isRtl = _computeParagraphIsRtl(para);
      final paraDir = isRtl ? TextDirection.rtl : TextDirection.ltr;
      TextAlign? scriptAlign;
      for (final word in para) {
        if (word.alignment != null) {
          scriptAlign = word.alignment;
          break;
        }
      }
      scriptAlign ??= para.first.alignment;

      final preparedWords = <_PreparedPresenterWord>[];
      var minWordIdx = para.first.index;
      var maxWordIdx = para.first.index;

      for (var i = 0; i < para.length; i++) {
        final word = para[i];
        if (!word.isNewline) spokenCount++;
        if (word.index >= 0 && word.index < totalWords) {
          wordToParagraph[word.index] = paraIdx;
        }
        if (word.index < minWordIdx) minWordIdx = word.index;
        if (word.index > maxWordIdx) maxWordIdx = word.index;

        final displayText = word.raw
            .replaceAll(_tagStripRe, '')
            .replaceAll(_alignTagStripRe, '');
        final wordDir = _computeWordDirection(displayText, paraDir);
        final prevHighlight = i > 0 ? para[i - 1].highlight : null;
        final nextHighlight =
            i + 1 < para.length ? para[i + 1].highlight : null;
        final userBg = word.highlight;
        preparedWords.add(
          _PreparedPresenterWord(
            word: word,
            displayText: displayText,
            wordDirection: wordDir,
            needsExplicitDirection: wordDir != paraDir,
            joinsPreviousHighlight: userBg != null && userBg == prevHighlight,
            joinsNextHighlight: userBg != null && userBg == nextHighlight,
          ),
        );
      }

      paragraphs.add(
        _PreparedPresenterParagraph(
          paragraphIndex: paraIdx,
          rawWords: para,
          words: preparedWords,
          isBlankLine: false,
          isHardBlank: false,
          startWordIndex: minWordIdx,
          endWordIndex: maxWordIdx,
          isRtl: isRtl,
          direction: paraDir,
          scriptAlignment: scriptAlign,
        ),
      );
    }

    // Pre-compute contiguous highlight runs and underline list once per script.
    final highlightRuns = <List<ScriptWord>>[];
    final highlightedIndices = <int>[];
    final underlineWords = <ScriptWord>[];
    List<ScriptWord>? currentRun;
    int? prevRunIndex;
    Color? prevRunColor;

    for (final word in script.words) {
      if (word.isNewline) continue;
      if (word.isUnderline) {
        underlineWords.add(word);
      }
      final color = word.highlight;
      if (color == null) {
        if (currentRun != null &&
            HighlightBandPainter.isIgnorableHighlightSeparator(
              raw: word.raw,
              normalized: word.normalized,
            )) {
          continue;
        }
        currentRun = null;
        prevRunIndex = null;
        prevRunColor = null;
        continue;
      }
      highlightedIndices.add(word.index);
      final contiguous =
          prevRunIndex != null &&
          word.index > prevRunIndex &&
          prevRunColor == color;
      if (currentRun == null || !contiguous) {
        currentRun = <ScriptWord>[];
        highlightRuns.add(currentRun);
      }
      currentRun.add(word);
      prevRunIndex = word.index;
      prevRunColor = color;
    }

    return _PreparedPresenterScript(
      cacheKey: cacheKey,
      rawParagraphs: rawParagraphs,
      paragraphs: paragraphs,
      spokenWordCount: spokenCount,
      wordToParagraphIndex: wordToParagraph,
      highlightRuns: highlightRuns,
      highlightedWordIndices: highlightedIndices,
      underlineWords: underlineWords,
    );
  }

  static bool _computeParagraphIsRtl(List<ScriptWord> words) {
    for (final word in words) {
      if (word.isParagraphRtl != null) return word.isParagraphRtl!;
    }
    var hasLatin = false;
    for (final word in words) {
      final clean = word.raw.replaceAll(_tagStripRe, '').trim();
      if (clean.isEmpty) continue;
      if (_rtlCharRe.hasMatch(clean)) return true;
      if (_latinCharRe.hasMatch(clean)) hasLatin = true;
    }
    if (hasLatin) return false;
    return words.isNotEmpty && words.first.effectiveRtl;
  }

  static TextDirection _computeWordDirection(
    String text,
    TextDirection paragraphDirection,
  ) {
    final clean = text.replaceAll(_bidiIsolationStripRe, '');
    if (_rtlCharRe.hasMatch(clean)) return TextDirection.rtl;
    if (_latinCharRe.hasMatch(clean)) return TextDirection.ltr;
    return paragraphDirection;
  }
}

/// O(1) targeted dispatcher for Presenter word progress updates.
///
/// Instead of rebuilding all thousands of word widgets when `confirmedWordIndex`
/// advances by 1 word, only the 1–2 affected paragraphs receive a notification.
class _PresenterWordIndexController {
  int _displayWordIndex = 0;
  bool _readingActive = false;
  _PreparedPresenterScript? _prepared;
  final Map<int, List<VoidCallback>> _paragraphListeners = {};
  final ValueNotifier<int> highlightDecorationVersion = ValueNotifier<int>(0);

  int get displayWordIndex => _displayWordIndex;
  bool get readingActive => _readingActive;

  void attachScript(_PreparedPresenterScript prepared) {
    _prepared = prepared;
  }

  void addParagraphListener(int paragraphIndex, VoidCallback listener) {
    final list = _paragraphListeners.putIfAbsent(paragraphIndex, () => []);
    list.add(listener);
  }

  void removeParagraphListener(int paragraphIndex, VoidCallback listener) {
    final list = _paragraphListeners[paragraphIndex];
    if (list == null) return;
    list.remove(listener);
    if (list.isEmpty) {
      _paragraphListeners.remove(paragraphIndex);
    }
  }

  void update({
    required int displayWordIndex,
    required bool readingActive,
    bool notify = true,
  }) {
    final prevIndex = _displayWordIndex;
    final prevActive = _readingActive;
    if (prevIndex == displayWordIndex && prevActive == readingActive) {
      return;
    }
    _displayWordIndex = displayWordIndex;
    _readingActive = readingActive;
    if (!notify) return;

    final prepared = _prepared;
    if (prepared == null) {
      // Fallback: notify every mounted paragraph if script metadata isn't bound yet.
      for (final listeners in _paragraphListeners.values.toList()) {
        for (final listener in List<VoidCallback>.of(listeners)) {
          listener();
        }
      }
      return;
    }

    final affectedParagraphs = <int>{};
    if (prevIndex != displayWordIndex) {
      final lo = math.min(prevIndex, displayWordIndex);
      final hi = math.max(prevIndex, displayWordIndex);
      _collectParagraphsInRange(prepared, lo, hi, affectedParagraphs);
      if (prepared.hasHighlightedWordInRange(lo, hi)) {
        highlightDecorationVersion.value++;
      }
    }
    if (prevActive != readingActive) {
      _addParagraphForWord(prepared, displayWordIndex, affectedParagraphs);
      _addParagraphForWord(prepared, prevIndex, affectedParagraphs);
    }

    for (final paraIdx in affectedParagraphs) {
      final listeners = _paragraphListeners[paraIdx];
      if (listeners == null) continue;
      for (final listener in List<VoidCallback>.of(listeners)) {
        listener();
      }
    }
  }

  void _addParagraphForWord(
    _PreparedPresenterScript prepared,
    int wordIndex,
    Set<int> out,
  ) {
    final map = prepared.wordToParagraphIndex;
    if (map.isEmpty) return;
    final clamped = wordIndex.clamp(0, map.length - 1);
    final paraIdx = map[clamped];
    if (paraIdx >= 0) out.add(paraIdx);
  }

  void _collectParagraphsInRange(
    _PreparedPresenterScript prepared,
    int loWord,
    int hiWord,
    Set<int> out,
  ) {
    final map = prepared.wordToParagraphIndex;
    if (map.isEmpty) return;
    final start = loWord.clamp(0, map.length - 1);
    final end = hiWord.clamp(0, map.length - 1);
    final startPara = map[start];
    final endPara = map[end];
    if (startPara >= 0 && endPara >= 0) {
      final minPara = math.min(startPara, endPara);
      final maxPara = math.max(startPara, endPara);
      for (var p = minPara; p <= maxPara; p++) {
        out.add(p);
      }
      return;
    }
    for (var w = start; w <= end; w++) {
      final p = map[w];
      if (p >= 0) out.add(p);
    }
  }

  void dispose() {
    _paragraphListeners.clear();
    highlightDecorationVersion.dispose();
  }
}

class _PresenterParagraphView extends StatefulWidget {
  final _PreparedPresenterParagraph paragraph;
  final _PresenterWordIndexController controller;
  final List<GlobalKey> wordKeys;
  final AppSettings settings;
  final double presentationFontSize;
  final double paraFontSize;
  final double paraWordGap;
  final WrapAlignment wrapAlignment;
  final void Function(_PreparedPresenterParagraph paragraph, Offset globalPos)
  onParagraphTapUp;

  const _PresenterParagraphView({
    super.key,
    required this.paragraph,
    required this.controller,
    required this.wordKeys,
    required this.settings,
    required this.presentationFontSize,
    required this.paraFontSize,
    required this.paraWordGap,
    required this.wrapAlignment,
    required this.onParagraphTapUp,
  });

  @override
  State<_PresenterParagraphView> createState() =>
      _PresenterParagraphViewState();
}

class _PresenterParagraphViewState extends State<_PresenterParagraphView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addParagraphListener(
      widget.paragraph.paragraphIndex,
      _handleWordIndexUpdate,
    );
  }

  @override
  void didUpdateWidget(covariant _PresenterParagraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.paragraph.paragraphIndex != widget.paragraph.paragraphIndex) {
      oldWidget.controller.removeParagraphListener(
        oldWidget.paragraph.paragraphIndex,
        _handleWordIndexUpdate,
      );
      widget.controller.addParagraphListener(
        widget.paragraph.paragraphIndex,
        _handleWordIndexUpdate,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeParagraphListener(
      widget.paragraph.paragraphIndex,
      _handleWordIndexUpdate,
    );
    super.dispose();
  }

  void _handleWordIndexUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final paragraph = widget.paragraph;
    final settings = widget.settings;
    final displayWordIndex = widget.controller.displayWordIndex;
    final readingActive =
        widget.controller.readingActive || displayWordIndex > 0;
    final letterSpacing = ScriptTypographyService.effectiveSpacing(
      settings.letterSpacing,
      scale: ScriptTypographyService.presenterScaleFactor,
    );
    final scriptBgColor = Color(settings.scriptBgColor);
    final futureWordColor = Color(settings.futureWordColor);
    final currentWordColor = Color(settings.currentWordColor);
    final trackingHighlight =
        settings.showCurrentWordHighlight
            ? currentWordColor.withValues(alpha: 0.3)
            : null;
    final pastOpacity = settings.pastWordOpacity.clamp(0.0, 1.0);

    final children = List<Widget>.generate(paragraph.words.length, (idx) {
      final prep = paragraph.words[idx];
      final word = prep.word;
      final i = word.index;
      final isCurrent = readingActive && i == displayWordIndex;
      final isPast = i < displayWordIndex;
      final effectiveFontSize =
          word.fontSize != null
              ? word.fontSize! * 2.0
              : widget.presentationFontSize;
      final userBgColor = word.highlight;
      final trackingBgColor = isCurrent ? trackingHighlight : null;
      final effectiveBg = PresenterHighlightStyle.wordBackground(
        imported: userBgColor,
        tracking: trackingBgColor,
        isPast: isPast,
        customPainterEnabled: kUseCustomDocxDecorationPainting,
      );

      Color baseColor;
      if (isCurrent) {
        baseColor =
            settings.showCurrentWordHighlight
                ? currentWordColor
                : (settings.showUpcomingWordColor
                    ? futureWordColor
                    : (word.textColor ?? futureWordColor));
      } else if (isPast) {
        final base =
            settings.showUpcomingWordColor
                ? futureWordColor
                : (word.textColor ?? futureWordColor);
        baseColor = base.withValues(alpha: pastOpacity);
      } else {
        baseColor =
            settings.showUpcomingWordColor
                ? futureWordColor
                : (word.textColor ?? futureWordColor);
      }
      final textColor = PresenterHighlightStyle.readableText(
        text: ScriptColorInversionService.presenterTextColor(
          word: word,
          settings: settings,
          fallback: baseColor,
        ),
        imported: userBgColor,
        tracking: trackingBgColor,
        scriptBackground: scriptBgColor,
        isPast: isPast,
      );

      Widget wordWidget = Text(
        prep.displayText,
        key: widget.wordKeys[i],
        style: TextStyle(
          fontSize: effectiveFontSize,
          fontFamily: word.fontFamily ?? settings.fontFamily,
          fontWeight: word.isBold ? FontWeight.bold : FontWeight.w500,
          fontStyle: word.isItalic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: letterSpacing,
          color: textColor,
          height: settings.lineSpacing,
          decoration:
              word.isUnderline && !kUseCustomDocxDecorationPainting
                  ? TextDecoration.underline
                  : null,
          decorationStyle: TextDecorationStyle.solid,
          decorationThickness: word.isUnderline ? 1.5 : null,
        ),
      );

      if (effectiveBg != null) {
        final useSmoothHighlightBand =
            userBgColor != null && trackingBgColor == null;
        final highlightRadius = Radius.circular(
          (effectiveFontSize * 0.08).clamp(2.0, 8.0),
        );
        wordWidget = DecoratedBox(
          decoration: BoxDecoration(
            color: effectiveBg,
            borderRadius:
                useSmoothHighlightBand
                    ? BorderRadiusDirectional.horizontal(
                      start:
                          prep.joinsPreviousHighlight
                              ? Radius.zero
                              : highlightRadius,
                      end:
                          prep.joinsNextHighlight
                              ? Radius.zero
                              : highlightRadius,
                    )
                    : null,
          ),
          child: wordWidget,
        );
      }

      if (prep.needsExplicitDirection) {
        wordWidget = Directionality(
          textDirection: prep.wordDirection,
          child: wordWidget,
        );
      }

      return wordWidget;
    }, growable: false);

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(
          bottom:
              widget.paraFontSize *
              (settings.lineSpacing - 1.0).clamp(0.0, 1.0),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp:
              (details) =>
                  widget.onParagraphTapUp(paragraph, details.globalPosition),
          child: Directionality(
            textDirection: paragraph.direction,
            child: Wrap(
              textDirection: paragraph.direction,
              alignment: widget.wrapAlignment,
              spacing: widget.paraWordGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
