part of 'teleprompter_screen.dart';

extension _TeleprompterBuildParts on _TeleprompterScreenState {
  Widget _buildTeleprompterScreen(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final tState = ref.watch(teleprompterProvider);
    final settings = ref.watch(settingsProvider);
    if (script != null) {
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
      unawaited(_loadBookmarksForScript(script));
      _scheduleVisibleWordWindowSync();
    }

    // Auto-scroll on speech recognition
    ref.listen(teleprompterProvider.select((s) => s.confirmedWordIndex),
        (prev, next) {
      final liveState = ref.read(teleprompterProvider);
      if (settings.scrollMode == 'auto' && liveState.isListening && next > 0) {
        _scrollToWordIndex(next, anticipate: true);
      }
    });

    if (script == null || script.isEmpty) {
      return Scaffold(
        backgroundColor: Color(settings.scriptBgColor),
        body: const Center(
            child: Text('No script loaded.',
                style: TextStyle(color: Colors.white))),
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

    // Presentation mode is a viewing surface, so it renders the single saved
    // font-size value larger without changing the metadata number shared with
    // the editor.
    final presentationFontSize = settings.fontSize * 2.0;
    final presenterWordGap = _presenterWordGap(presentationFontSize, settings);
    final controlsReservedHeight =
        settings.scrollMode == 'manual' ? 150.0 : 104.0;
    final debugConsoleExpanded = settings.debugMode &&
        !_debugConsoleMinimized &&
        (_controlsVisible || _debugConsolePinned);
    final debugConsoleHeight =
        settings.debugMode ? (debugConsoleExpanded ? 220.0 : 38.0) : 0.0;
    final debugConsoleBottom = settings.debugMode
        ? (debugConsoleExpanded
            ? (_debugConsolePinned && !_controlsVisible
                ? 10.0
                : controlsReservedHeight)
            : (_controlsVisible ? controlsReservedHeight : 10.0))
        : 10.0;
    final bookmarkWordIndexes = _bookmarks
        .map(
          (bookmark) => ScriptBookmarkService.nearestBookmarkableWordIndex(
            script.words,
            bookmark.wordIndex,
          ),
        )
        .whereType<int>()
        .toSet();

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
            // Override mode: use the settings alignment instead of editor tags
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
            try {
              // v3.9.5.3: Hardened Alignment Extraction - use direct word.alignment property
              // The tokenizer already parses [align=...] tags into this field.
              paraAlign = para.firstWhere((w) => w.alignment != null).alignment;
            } catch (_) {
              paraAlign = firstWord.alignment;
            }
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
                  final localWordIndex = entry.key;
                  final ScriptWord word = entry.value;
                  final i = word.index;
                  final hasBookmark = bookmarkWordIndexes.contains(i);
                  final isManual = settings.scrollMode == 'manual';
                  final isCurrent = !isManual && i == tState.confirmedWordIndex;
                  final isPast = !isManual && i < tState.confirmedWordIndex;
                  final visibleWordText = word.raw
                      .replaceAll(_tagStripRe, '')
                      .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '');
                  final displayText = _bidiIsolatedDisplayText(
                    visibleWordText,
                    paragraphDirection: paraDir,
                  );
                  final wordDirection = _wordDirectionForDisplay(
                    displayText,
                    paragraphDirection: paraDir,
                  );

                  final effectiveFontSize = word.fontSize != null
                      ? word.fontSize! * 2.0
                      : presentationFontSize;

                  // User-applied highlight (from tokenizer-parsed [bg=] tags)
                  final userBgColor = word.highlight;
                  // Word-tracking highlight (current word)
                  final trackingBgColor = isCurrent &&
                          settings.showCurrentWordHighlight
                      ? Color(settings.currentWordColor).withValues(alpha: 0.3)
                      : null;
                  final effectiveBg = kUseCustomDocxDecorationPainting
                      ? trackingBgColor
                      : trackingBgColor ??
                          (isPast
                              ? userBgColor?.withValues(alpha: 0.15)
                              : userBgColor);

                  // Text color with graduated opacity for smooth spotlight effect.
                  // Words close to the current position gently transition between
                  // full brightness and past-word dimness.
                  final int currentIdx = tState.confirmedWordIndex;
                  final int dist =
                      i - currentIdx; // negative = past, positive = future
                  final Color textColor;
                  if (isCurrent) {
                    textColor = settings.showCurrentWordHighlight
                        ? Color(settings.currentWordColor)
                        : (settings.showUpcomingWordColor
                            ? Color(settings.futureWordColor)
                            : (word.textColor ??
                                Color(settings.futureWordColor)));
                  } else if (isPast) {
                    final base = settings.showUpcomingWordColor
                        ? Color(settings.futureWordColor)
                        : (word.textColor ?? Color(settings.futureWordColor));
                    // Graduated fade: words just behind current are brighter
                    final pastDist =
                        dist.abs(); // 1 = just passed, 2 = two back, etc.
                    final gradOpacity = pastDist <= 3
                        ? settings.pastWordOpacity +
                            (1.0 - settings.pastWordOpacity) *
                                (1.0 - pastDist / 3.0) *
                                0.5
                        : settings.pastWordOpacity;
                    textColor =
                        base.withValues(alpha: gradOpacity.clamp(0.0, 1.0));
                  } else {
                    // Toggle ON: uniform override color. Toggle OFF: use per-word markup color.
                    textColor = settings.showUpcomingWordColor
                        ? Color(settings.futureWordColor)
                        : (word.textColor ?? const Color(0xFFFFFFFF));
                  }

                  // Keep presenter word gaps as physical Wrap spacing, not
                  // trailing text spaces. Text spaces are neutral bidi
                  // characters and, in Hebrew paragraphs, can attach to the
                  // wrong side of one-word Text widgets.
                  final joinsPreviousHighlight = _sameHighlightColor(
                    userBgColor,
                    localWordIndex > 0
                        ? para[localWordIndex - 1].highlight
                        : null,
                  );
                  final joinsNextHighlight = _sameHighlightColor(
                    userBgColor,
                    localWordIndex + 1 < para.length
                        ? para[localWordIndex + 1].highlight
                        : null,
                  );
                  final useSmoothHighlightBand =
                      !kUseCustomDocxDecorationPainting &&
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
                            fontWeight:
                                word.isBold ? FontWeight.bold : FontWeight.w500,
                            fontStyle: word.isItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            letterSpacing: settings.letterSpacing,
                            wordSpacing: settings.wordSpacing,
                            color: textColor,
                            height: settings.lineSpacing,
                            decoration: word.isUnderline &&
                                    !kUseCustomDocxDecorationPainting
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
                          onTap: speechActive
                              ? null
                              : () => _tapPresenterBookmarkMarker(i),
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
                  isManualMode: settings.scrollMode == 'manual',
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
                  isManualMode: settings.scrollMode == 'manual',
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

    return PopScope(
      canPop: _closingPresentation,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _exitPresentation();
      },
      child: Scaffold(
        backgroundColor: Color(settings.scriptBgColor),
        body: Focus(
          autofocus: true,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyF,
                  control: true, shift: true): _PresentationSearchIntent(),
              SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
                  _PresentationSearchIntent(),
            },
            child: Actions(
              actions: {
                _PresentationSearchIntent:
                    CallbackAction<_PresentationSearchIntent>(onInvoke: (_) {
                  _showSearchDialog();
                  return null;
                }),
              },
              child: GestureDetector(
                onTap: (Platform.isWindows &&
                        (tState.isListening || tState.isStarting))
                    ? null
                    : _showControls,
                child: Stack(
                  children: [
                    // Scrollable script
                    NotificationListener<ScrollNotification>(
                      onNotification: _handleStoppedBrowsingScroll,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: (tState.isListening || tState.isStarting)
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        child: wordList,
                      ),
                    ),
                    // Reading fade overlay: gradient that dims already-read text above the reading line
                    if (settings.readFadeIntensity > 0)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: MediaQuery.of(context).size.height *
                                settings.scrollLead +
                            20,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(settings.scriptBgColor).withValues(
                                      alpha: settings.readFadeIntensity),
                                  Color(settings.scriptBgColor).withValues(
                                      alpha: settings.readFadeIntensity * 0.6),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.7, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (tState.isStarting && !tState.hasError)
                      Positioned(
                        top: 22,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _SttStartingIndicator(
                            accentColor: Color(settings.currentWordColor),
                          ),
                        ),
                      ),
                    if (settings.debugMode)
                      _buildPresenterDebugConsole(
                        context,
                        tState,
                        bottom: debugConsoleBottom,
                        height: debugConsoleHeight,
                        expanded: debugConsoleExpanded,
                        accentColor: Color(settings.currentWordColor),
                        wordCount:
                            script.words.where((w) => !w.isNewline).length,
                      ),

                    // STT Pro Dashboard Integration
                    if (_webviewController != null &&
                        tState.sttWebViewUrl != null)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        width: 1,
                        height: 1,
                        child: IgnorePointer(
                          ignoring: true,
                          child: Opacity(
                            opacity: 0.01,
                            child: Webview(_webviewController!),
                          ),
                        ),
                      ),

                    // Reading line
                    Positioned(
                      top: MediaQuery.of(context).size.height *
                              settings.scrollLead -
                          2,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        color: Color(settings.currentWordColor)
                            .withValues(alpha: 0.35),
                      ),
                    ),

                    // Error banner with actionable guidance
                    if (tState.hasError && tState.statusMessage.isNotEmpty)
                      Positioned(
                        top: 60,
                        left: 20,
                        right: 20,
                        child: GestureDetector(
                          onTap: () {
                            // Tapping the error banner opens app settings for permission issues
                            if (tState.statusMessage.contains('permission') ||
                                tState.statusMessage.contains('Permission')) {
                              openAppSettings();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _getUserFriendlyError(tState.statusMessage),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                                if (tState.statusMessage.contains('permission'))
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text('Tap here to open Settings',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            decoration:
                                                TextDecoration.underline)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Compact search toolbar â€” floats at top, prev/next, count
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: Center(child: _buildPresenterSearchToolbar()),
                    ),

                    if (Platform.isWindows &&
                        (tState.isListening || tState.isStarting))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 92,
                        child: MouseRegion(
                          opaque: false,
                          onEnter: (_) {
                            _windowsControlsHovering = true;
                            _showWindowsControlsFromHotZone();
                          },
                          onExit: (_) {
                            _windowsControlsHovering = false;
                            _scheduleHideControls();
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),

                    // Controls overlay â€” control bar + speed slider stacked at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: MouseRegion(
                        onEnter: (_) {
                          if (Platform.isWindows) {
                            _windowsControlsHovering = true;
                            _showWindowsControlsFromHotZone();
                          }
                        },
                        onExit: (_) {
                          if (Platform.isWindows) {
                            _windowsControlsHovering = false;
                            _scheduleHideControls();
                          }
                        },
                        child: AnimatedOpacity(
                          opacity: _controlsVisible ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Speed slider â€” sits just above the control bar, always visible in manual mode
                                if (settings.scrollMode == 'manual')
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.speed,
                                            color: Colors.white54, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Slider(
                                            value: settings.scrollSpeed,
                                            min: -300,
                                            max: 300,
                                            divisions: 120, // 5wpm steps
                                            activeColor: Color(
                                                settings.currentWordColor),
                                            inactiveColor: Colors.white24,
                                            onChanged: (v) {
                                              ref
                                                  .read(
                                                      settingsProvider.notifier)
                                                  .setScrollSpeed(v);
                                              if (_manualScrolling && v != 0) {
                                                // If already scrolling, update will happen in next tick of timer
                                                // No need to restart timer if we handle speed dynamically
                                              } else if (v != 0 &&
                                                  !_manualScrolling) {
                                                _startManualScroll();
                                              } else if (v == 0) {
                                                _stopManualScroll();
                                              }
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: 62,
                                          child: Text(
                                              '${settings.scrollSpeed.round() > 0 ? "+" : ""}${settings.scrollSpeed.round()} wpm',
                                              style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11)),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Control bar
                                _ControlBar(
                                  isListening: tState.isListening,
                                  isStarting: tState.isStarting,
                                  isManualMode: settings.scrollMode == 'manual',
                                  isManualScrolling: _manualScrolling,
                                  isScrollingBackward: _scrollingBackward,
                                  accentColor: Color(settings.currentWordColor),
                                  onStart: settings.scrollMode == 'manual'
                                      ? _startManualScroll
                                      : _requestAndStart,
                                  onStartBackward: () =>
                                      _startManualScroll(backward: true),
                                  onStop: settings.scrollMode == 'manual'
                                      ? _stopManualScroll
                                      : () => ref
                                          .read(teleprompterProvider.notifier)
                                          .stopSession(),
                                  onReset: () {
                                    if (settings.scrollMode == 'manual') {
                                      _resetManual();
                                    } else {
                                      ref
                                          .read(teleprompterProvider.notifier)
                                          .resetPosition();
                                      _scrollController.animateTo(0,
                                          duration:
                                              const Duration(milliseconds: 400),
                                          curve: Curves.easeOutCubic);
                                    }
                                  },
                                  onBack: () {
                                    _exitPresentation();
                                  },
                                  onSettings: _showSettings,
                                  onAddBookmark: _addPresenterBookmark,
                                  onRemoveBookmark:
                                      _deletePresenterBookmarkAtCurrentPosition,
                                  onPreviousBookmark: () =>
                                      _jumpPresenterBookmark(-1),
                                  onNextBookmark: () =>
                                      _jumpPresenterBookmark(1),
                                  onSearch: _showSearchDialog,
                                  onFontSizeChanged:
                                      _preserveReadingPositionAfterLayoutChange,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
