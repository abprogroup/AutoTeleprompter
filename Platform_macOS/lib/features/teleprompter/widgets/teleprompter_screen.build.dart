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
      if (_activeManualCorrection) return;
      if (settings.scrollMode == 'auto' && liveState.isListening && next > 0) {
        _scrollToWordIndex(next, anticipate: true);
      }
    });
    ref.listen(
        teleprompterProvider.select((s) => s.isListening || s.isStarting),
        (prev, next) {
      if (prev == next) return;
      if (next) {
        _scheduleHideControls();
      } else {
        _showControls();
      }
    });

    if (script == null || script.isEmpty) {
      return PopScope(
        canPop: _closingPresentation,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _exitPresentation();
        },
        child: Scaffold(
          backgroundColor: Color(settings.scriptBgColor),
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Center(
                  child: Text(
                    'No script loaded.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 16,
                  child: TextButton.icon(
                    onPressed: () => _exitPresentation(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
      isListening: tState.isListening,
      isStarting: tState.isStarting,
      allowActiveManualScroll: allowActiveManualScroll,
    );
    final sttStartingVisualActive =
        (tState.isStarting || _sttStartAffordanceVisible) && !tState.hasError;
    final controlsState =
        sttStartingVisualActive ? tState.copyWith(isStarting: true) : tState;

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
              child: MouseRegion(
                onEnter: _rememberPresenterPointer,
                onHover: _rememberPresenterPointer,
                onExit: (_) => _lastPresenterPointerGlobalPosition = null,
                child: GestureDetector(
                  onTap: activeInputLocked ? null : _showControls,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPresenterReadingSurface(
                        settings: settings,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Scrollable script
                            Positioned.fill(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _handleStoppedBrowsingScroll,
                                child: Listener(
                                  onPointerSignal: (event) {
                                    if (event is PointerScrollEvent) {
                                      if (!activeInputLocked) {
                                        _notePresenterUserScrollSignal();
                                      }
                                      if (!activeInputLocked) return;
                                      GestureBinding
                                          .instance.pointerSignalResolver
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
                            ),
                            // Reading fade overlay: gradient that dims already-read text above the reading line
                            if (settings.readFadeIntensity > 0)
                              _buildPresenterReadFadeOverlay(settings),
                            _buildPresenterReadingLine(settings),
                          ],
                        ),
                      ),
                      if (sttStartingVisualActive)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: _SttStartingIndicator(
                                accentColor: Color(settings.currentWordColor),
                              ),
                            ),
                          ),
                        ),
                      if (settings.showSoundLevelMeter &&
                          !settings.debugMode &&
                          (controlsState.isListening ||
                              controlsState.isStarting))
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: controlsReservedHeight + 16,
                          child: IgnorePointer(
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 360),
                                child: _SoundLevelBar(
                                  level: controlsState.soundLevel,
                                  isListening: controlsState.isListening,
                                  isStarting: controlsState.isStarting,
                                  accentColor: Color(settings.currentWordColor),
                                ),
                              ),
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

                      // Error banner with actionable guidance
                      if (tState.hasError && tState.statusMessage.isNotEmpty)
                        Positioned(
                          top: 60,
                          left: 20,
                          right: 20,
                          child: GestureDetector(
                            onTap: () {
                              // Tapping permission errors opens the exact settings page.
                              if (_isBrowserMicrophoneSettingsError(
                                tState.statusMessage,
                              )) {
                                unawaited(_openMicrophonePrivacySettings());
                              } else if (tState.statusMessage
                                      .contains('permission') ||
                                  tState.statusMessage.contains('Permission')) {
                                if (Platform.isMacOS) {
                                  unawaited(MacOSPermissions
                                      .openMicrophoneSettings());
                                } else {
                                  openAppSettings();
                                }
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
                                  if (_isBrowserMicrophoneSettingsError(
                                        tState.statusMessage,
                                      ) ||
                                      tState.statusMessage
                                          .contains('permission'))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        _isBrowserMicrophoneSettingsError(
                                          tState.statusMessage,
                                        )
                                            ? 'Tap here to open microphone settings'
                                            : 'Tap here to open Settings',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            decoration:
                                                TextDecoration.underline),
                                      ),
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

                      if (tState.isListening ||
                          tState.isStarting ||
                          _manualScrolling)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _presenterControlsHotZoneHeight,
                          child: MouseRegion(
                            opaque: false,
                            onEnter: (event) {
                              _rememberPresenterPointer(event);
                              _windowsControlsHovering = true;
                              _showWindowsControlsFromHotZone();
                            },
                            onHover: _rememberPresenterPointer,
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
                        child: KeyedSubtree(
                          key: _presenterControlsKey,
                          child: _buildPresenterControlsOverlay(
                            settings: settings,
                            tState: controlsState,
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
