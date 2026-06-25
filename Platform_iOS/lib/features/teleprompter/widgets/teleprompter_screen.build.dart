part of 'teleprompter_screen.dart';

extension _TeleprompterBuildParts on _TeleprompterScreenState {
  Widget _buildTeleprompterScreen(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final tState = ref.watch(teleprompterProvider);
    final settings = ref.watch(settingsProvider);
    _publishPresenterStateIfChanged(script, tState, settings);
    _syncControlsAutoHide(
      PresenterInputLockService.controlsAutoHideActive(
        isListening: tState.isListening,
        isStarting: tState.isStarting,
      ),
    );
    if (script != null) {
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
      unawaited(_loadBookmarksForScript(script));
    }

    // Auto-scroll on speech recognition
    ref.listen(teleprompterProvider.select((s) => s.confirmedWordIndex),
        (prev, next) {
      if (_userBrowsingWhileStopped) return;
      if (settings.scrollMode == 'auto' && next > 0) {
        _scrollToWordIndex(next);
      }
    });

    _scheduleVisibleWordWindowSync();

    if (script == null || script.isEmpty) {
      return Scaffold(
        backgroundColor: Color(settings.scriptBgColor),
        body: const Center(
            child: Text('No script loaded.',
                style: TextStyle(color: Colors.white))),
      );
    }
    final bookmarkWordIndexes = _bookmarks.map((b) => b.wordIndex).toSet();

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

    // Presentation mode uses 2x font size for readability.
    // The editor shows smaller text for fluid editing; the teleprompter enlarges it.
    final presentationFontSize = settings.fontSize * 2.0;
    final debugConsoleHeight = settings.debugMode
        ? (_debugConsoleMinimized ? 40.0 : 220.0)
        : 0.0;
    final controlsReservedHeight =
        settings.scrollMode == 'manual' ? 150.0 : 104.0;
    // Drop the box to the bottom edge when the toolbar hides during a session,
    // otherwise keep it above the reserved control area.
    final debugConsoleBottom = !settings.debugMode
        ? 10.0
        : (_controlsVisible ? controlsReservedHeight : 10.0);

    Widget wordList = Padding(
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
              height: isHard ? presentationFontSize * 0.5 : 0.0,
            );
          }

          final firstWord = para.first;
          final paraDir =
              firstWord.effectiveRtl ? TextDirection.rtl : TextDirection.ltr;
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
                alignment: _toWrapAlignment(
                    paraAlign, settings, firstWord.effectiveRtl),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: para.map<Widget>((wordObj) {
                  final ScriptWord word = wordObj;
                  final i = word.index;
                  final markerOnRight = firstWord.effectiveRtl;
                  final isManual = settings.scrollMode == 'manual';
                  final isCurrent = !isManual && i == tState.confirmedWordIndex;
                  final isPast = !isManual && i < tState.confirmedWordIndex;
                  final displayText = word.raw
                      .replaceAll(_tagStripRe, '')
                      .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '');
                  final hasBookmark = bookmarkWordIndexes.contains(i);

                  final effectiveFontSize = word.fontSize != null
                      ? presentationFontSize * (word.fontSize! / 17.0)
                      : presentationFontSize;

                  // User-applied highlight (from tokenizer-parsed [bg=] tags)
                  final userBgColor = word.highlight;
                  // Word-tracking highlight (current word)
                  final trackingBgColor = isCurrent &&
                          settings.showCurrentWordHighlight
                      ? Color(settings.currentWordColor).withValues(alpha: 0.3)
                      : null;
                  final effectiveBg = trackingBgColor ??
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

                  // Use Container padding instead of trailing space for word gaps.
                  // Container.color covers padding area → continuous highlight blocks.
                  final wordGap = effectiveFontSize * 0.28;
                  final wordWidget = Directionality(
                    textDirection: word.effectiveRtl
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Container(
                      key: _wordKeys[i],
                      padding: EdgeInsets.only(
                        right: word.effectiveRtl ? 0 : wordGap,
                        left: word.effectiveRtl ? wordGap : 0,
                      ),
                      color: effectiveBg,
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
                          decoration: word.isUnderline
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  );
                  if (!hasBookmark) return wordWidget;
                  return Padding(
                    padding: EdgeInsets.only(
                      left: markerOnRight ? 0 : 28,
                      right: markerOnRight ? 28 : 0,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        wordWidget,
                        Positioned(
                          left: markerOnRight ? null : -30,
                          right: markerOnRight ? -30 : null,
                          top: (effectiveFontSize - 24) / 2,
                          child: Tooltip(
                            message: 'Delete bookmark',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  unawaited(_deletePresenterBookmark(i)),
                              child: const SizedBox(
                                width: 24,
                                height: 28,
                                child: Text(
                                  '\u00BB',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFFFBF00),
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
    final allowActiveManualScroll =
        PresenterInputLockService.allowActiveManualScroll(
      settingEnabled: settings.allowScrollDuringActiveSession,
      isListening: tState.isListening,
      isStarting: tState.isStarting,
    );
    final activeInputLocked = PresenterInputLockService.inputLocked(
      isListening: tState.isListening,
      isStarting: tState.isStarting,
      allowActiveManualScroll: allowActiveManualScroll,
    );

    return PopScope(
      // Stop STT the moment the back gesture is confirmed — before the
      // exit animation starts and long before dispose() is called.
      // dispose() still calls stopSession() as a safety net.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _teleprompterNotifier.stopSession();
      },
      child: KeyboardListener(
        focusNode: _presentationFocusNode,
        autofocus: true,
        onKeyEvent: _handlePresentationKey,
        child: Scaffold(
          backgroundColor: Color(settings.scriptBgColor),
          body: GestureDetector(
            onTap: _showControls,
            child: Stack(
              children: [
                // Scrollable script
                NotificationListener<ScrollNotification>(
                  onNotification: _handleStoppedBrowsingScroll,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: activeInputLocked
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
                // Technical Debug Overlay
                if (settings.debugMode)
                  Positioned(
                    bottom: debugConsoleBottom,
                    left: 6,
                    right: 6,
                    child: Container(
                      height: debugConsoleHeight,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header bar with current status
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A1A00),
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(9)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  tState.isListening
                                      ? Icons.mic
                                      : Icons.mic_off,
                                  color: tState.isListening
                                      ? Colors.greenAccent
                                      : Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tState.isListening ? 'LISTENING' : 'IDLE',
                                  style: TextStyle(
                                    color: tState.isListening
                                        ? Colors.greenAccent
                                        : Colors.red,
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
                                    accentColor: Colors.orange,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'POS: ${tState.confirmedWordIndex}/${script.words.where((w) => !w.isNewline).length}',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.bug_report_outlined,
                                      color: Colors.orange, size: 16),
                                  tooltip: 'Send feedback',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const FeedbackReportScreen(),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _debugConsoleMinimized
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  tooltip: _debugConsoleMinimized
                                      ? 'Expand debug box'
                                      : 'Minimize debug box',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _setTeleprompterState(() =>
                                      _debugConsoleMinimized =
                                          !_debugConsoleMinimized),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.copy,
                                      color: Colors.orange, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    final text =
                                        tState.debugLogs.reversed.join('\n');
                                    Clipboard.setData(
                                        ClipboardData(text: text));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Debug logs copied to clipboard',
                                              style: TextStyle(
                                                  color: Colors.black)),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              itemCount: tState.debugLogs.length,
                              itemBuilder: (context, idx) {
                                final log = tState.debugLogs[
                                    tState.debugLogs.length - 1 - idx];
                                Color logColor = Colors.greenAccent;
                                if (log.contains('⏸') || log.contains('WAIT')) {
                                  logColor = Colors.yellow.shade200;
                                } else if (log.contains('❌') ||
                                    log.contains('SKIP') ||
                                    log.contains('⏭')) {
                                  logColor = Colors.redAccent.shade100;
                                } else if (log.contains('🎤') ||
                                    log.contains('STATUS')) {
                                  logColor = Colors.cyan.shade200;
                                } else if (log.contains('💓') ||
                                    log.contains('HEARTBEAT')) {
                                  logColor = Colors.purple.shade200;
                                } else if (log.contains('🚀') ||
                                    log.contains('🌐')) {
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
                  ),

                // Reading line
                Positioned(
                  top:
                      MediaQuery.of(context).size.height * settings.scrollLead -
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
                                        decoration: TextDecoration.underline)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!settings.debugMode &&
                    settings.showSoundLevelMeter &&
                    (tState.isListening || tState.isStarting))
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: controlsReservedHeight + 10,
                    child: _buildListeningMeter(tState),
                  ),

                // Controls overlay — control bar + speed slider stacked at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.92),
                              Colors.black.withValues(alpha: 0.58),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPresenterSearchToolbar(),
                            // Speed slider — sits just above the control bar, always visible in manual mode
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
                                        activeColor:
                                            Color(settings.currentWordColor),
                                        inactiveColor: Colors.white24,
                                        onChanged: (v) {
                                          ref
                                              .read(settingsProvider.notifier)
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
                                  _resetPresenterPositionToStart();
                                }
                              },
                              onBack: () => Navigator.of(context).pop(),
                              onSettings: _showSettings,
                              onAddBookmark: _addPresenterBookmark,
                              onRemoveBookmark:
                                  _deletePresenterBookmarkAtCurrentPosition,
                              onPreviousBookmark: () =>
                                  _jumpPresenterBookmark(-1),
                              onNextBookmark: () => _jumpPresenterBookmark(1),
                              onSearch: _showPresenterSearchDialog,
                              sttKey: _presenterSttKey,
                              settingsKey: _presenterSettingsKey,
                              bookmarksKey: _presenterBookmarksKey,
                              resetKey: _presenterResetKey,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_presenterWalkthroughVisible)
                  _buildPresenterWalkthroughOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListeningMeter(TeleprompterState state) {
    final level =
        state.isStarting ? 0.0 : state.soundLevel.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFFBF00).withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(
            state.isStarting ? Icons.hourglass_empty_rounded : Icons.graphic_eq,
            color: const Color(0xFFFFBF00),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: state.isStarting ? null : level,
                minHeight: 8,
                backgroundColor: Colors.white12,
                color: const Color(0xFFFFBF00),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            state.isStarting ? 'STARTING' : 'LISTENING',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _publishPresenterStateIfChanged(
    Script? script,
    TeleprompterState tState,
    AppSettings settings,
  ) {
    final scriptActive = script != null && !script.isEmpty;
    final sessionActive =
        tState.isListening || tState.isStarting || _manualScrolling;
    final isStarting = tState.isStarting;
    final mode = settings.scrollMode == 'manual' ? 'manual' : 'auto';
    final speed = settings.scrollSpeed.clamp(-300.0, 300.0).toDouble();
    if (_lastPublishedRemoteScriptActive == scriptActive &&
        _lastPublishedRemoteSessionActive == sessionActive &&
        _lastPublishedRemoteIsStarting == isStarting &&
        _lastPublishedRemoteScrollMode == mode &&
        _lastPublishedRemoteScrollSpeed == speed) {
      return;
    }
    _lastPublishedRemoteScriptActive = scriptActive;
    _lastPublishedRemoteSessionActive = sessionActive;
    _lastPublishedRemoteIsStarting = isStarting;
    _lastPublishedRemoteScrollMode = mode;
    _lastPublishedRemoteScrollSpeed = speed;
    ref.read(remoteControlProvider).publishPresenterState(
          scriptActive: scriptActive,
          sessionActive: sessionActive,
          isStarting: isStarting,
          scrollMode: mode,
          scrollSpeed: speed,
        );
  }
}
