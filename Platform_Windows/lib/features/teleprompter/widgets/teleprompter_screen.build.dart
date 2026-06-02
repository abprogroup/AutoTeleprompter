part of 'teleprompter_screen.dart';

extension _TeleprompterBuildParts on _TeleprompterScreenState {
  Widget _buildTeleprompterScreen(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final tState = ref.watch(teleprompterProvider);
    final settings = ref.watch(settingsProvider);
    _publishPresenterStateIfChanged(script, tState, settings);
    if (script != null) {
      while (_wordKeys.length < script.words.length) {
        _wordKeys.add(GlobalKey());
      }
      unawaited(_loadBookmarksForScript(script));
      final layoutKey = _presenterLayoutKey(context, script, settings);
      if (_visibleWindowLayoutKey != layoutKey) {
        _visibleWindowLayoutKey = layoutKey;
        _scheduleVisibleWordWindowSync(force: true);
      }
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

    final paragraphs = _paragraphsForScript(script);

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
    final allowActiveManualScroll =
        PresenterInputLockService.allowActiveManualScroll(
      settingEnabled: settings.allowScrollDuringActiveSession,
      isListening: tState.isListening,
      isStarting: tState.isStarting,
    );
    final activeInputLocked = PresenterInputLockService.inputLocked(
      isWindows: Platform.isWindows,
      isListening: tState.isListening,
      isStarting: tState.isStarting,
      allowActiveManualScroll: allowActiveManualScroll,
    );

    final wordList = _buildPresenterWordList(
      context: context,
      script: script,
      paragraphs: paragraphs,
      tState: tState,
      settings: settings,
      bookmarkWordIndexes: bookmarkWordIndexes,
      presentationFontSize: presentationFontSize,
      presenterWordGap: presenterWordGap,
    );

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
                onTap: activeInputLocked ? null : _showControls,
                child: Stack(
                  children: [
                    // Scrollable script
                    NotificationListener<ScrollNotification>(
                      onNotification: _handleStoppedBrowsingScroll,
                      child: Listener(
                        onPointerSignal: (event) {
                          if (activeInputLocked &&
                              event is PointerScrollEvent) {
                            GestureBinding.instance.pointerSignalResolver
                                .register(event, (_) {});
                          }
                        },
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          physics: activeInputLocked
                              ? const NeverScrollableScrollPhysics()
                              : const ClampingScrollPhysics(),
                          child: wordList,
                        ),
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

                    // Compact search toolbar floats at top: prev/next/count.
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: Center(child: _buildPresenterSearchToolbar()),
                    ),

                    if (Platform.isWindows &&
                        (tState.isListening ||
                            tState.isStarting ||
                            _manualScrolling))
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

                    // Controls overlay: control bar + speed slider stacked at bottom.
                    _buildFloatingManualSpeedSlider(
                      settings: settings,
                      tState: tState,
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildPresenterControlsOverlay(
                        settings: settings,
                        tState: tState,
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

  String _presenterLayoutKey(
    BuildContext context,
    Script script,
    AppSettings settings,
  ) {
    final media = MediaQuery.of(context);
    return [
      script.sessionId,
      script.words.length,
      identityHashCode(script.words),
      media.size.width.round(),
      media.size.height.round(),
      settings.fontSize,
      settings.lineSpacing,
      settings.wordSpacing,
      settings.letterSpacing,
      settings.textAlign,
      settings.showAlignmentOverride,
      settings.flipRotation,
      settings.mirrorHorizontal,
      settings.mirrorVertical,
    ].join('|');
  }

  List<List<ScriptWord>> _paragraphsForScript(Script script) {
    final key = '${script.sessionId}|${script.words.length}|'
        '${identityHashCode(script.words)}';
    if (_paragraphCacheKey == key) return _paragraphCache;

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
    _paragraphCacheKey = key;
    _paragraphCache = paragraphs;
    return _paragraphCache;
  }
}
