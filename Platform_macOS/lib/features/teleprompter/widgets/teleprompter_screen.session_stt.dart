part of 'teleprompter_screen.dart';

extension _TeleprompterSessionSttParts on _TeleprompterScreenState {
  void _initRemoteListener() {
    _remoteCmdSub?.cancel();
    _remoteCmdSub = _remoteControlService.onCommand.listen((cmd) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      if (cmd.startsWith('SET_SPEED:')) {
        final speed = double.tryParse(cmd.substring('SET_SPEED:'.length));
        if (speed != null && settings.scrollMode == 'manual') {
          unawaited(
            ref
                .read(settingsProvider.notifier)
                .setScrollSpeed(speed.clamp(-300.0, 300.0).toDouble()),
          );
        }
        return;
      }

      switch (cmd) {
        case 'TOGGLE':
          final tState = ref.read(teleprompterProvider);
          if (tState.isListening || tState.isStarting) {
            _stopSpeechSessionFromUi('presenter.remoteToggleStop');
          } else if (settings.scrollMode == 'manual') {
            _manualScrolling ? _stopManualScroll() : _startManualScroll();
          } else {
            _requestAndStart();
          }
          break;
        case 'FASTER':
          ref
              .read(settingsProvider.notifier)
              .setScrollSpeed((settings.scrollSpeed + 15).clamp(-300.0, 300.0));
          break;
        case 'SLOWER':
          ref
              .read(settingsProvider.notifier)
              .setScrollSpeed((settings.scrollSpeed - 15).clamp(-300.0, 300.0));
          break;
        case 'RESET':
          if (settings.scrollMode == 'manual') {
            _resetManual();
          } else {
            _resetPresenterPositionToStart(animated: false);
          }
          break;
        case 'MODE_AUTO':
          ref.read(settingsProvider.notifier).setScrollMode('auto');
          break;
        case 'MODE_MANUAL':
          ref.read(settingsProvider.notifier).setScrollMode('manual');
          break;
        case 'BOOKMARK_ADD':
          unawaited(_addPresenterBookmark());
          break;
        case 'BOOKMARK_REMOVE':
          final tState = ref.read(teleprompterProvider);
          if (!tState.isListening && !tState.isStarting) {
            unawaited(_deletePresenterBookmarkAtCurrentPosition());
          }
          break;
        case 'BOOKMARK_PREVIOUS':
          unawaited(_jumpPresenterBookmark(-1));
          break;
        case 'BOOKMARK_NEXT':
          unawaited(_jumpPresenterBookmark(1));
          break;
        case 'INVERT_COLORS':
          unawaited(_togglePresenterColorInversion());
          break;
      }
    });
  }

  void _stopSpeechSessionFromUi(String source) {
    _hideSttStartAffordance();
    unawaited(_teleprompterNotifier.stopSession().catchError((
      Object error,
      StackTrace stack,
    ) {
      LightweightDiagnostics.instance.recordError(error, stack, source: source);
    }));
  }

  Future<void> _togglePresenterColorInversion() async {
    final settings = ref.read(settingsProvider);
    final nextBackground =
        ScriptColorInversionService.nextBackgroundColor(settings);
    final nextFutureText =
        ScriptColorInversionService.futureTextColorForBackground(
      nextBackground,
    );

    final settingsNotifier = ref.read(settingsProvider.notifier);
    final scriptNotifier = ref.read(scriptProvider.notifier);
    await settingsNotifier.setScriptBgColor(nextBackground);
    await settingsNotifier.setFutureWordColor(nextFutureText);
    await scriptNotifier.updateStyleMetadata(
      scriptBgColor: nextBackground,
      futureWordColor: nextFutureText,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Color(nextBackground).computeLuminance() > 0.5
              ? 'Script colors inverted: light background'
              : 'Script colors inverted: dark background',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _handlePresentationKey(KeyEvent event) {
    if (event is! KeyDownEvent || _searchDialogOpen || !mounted) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final isSearchShortcut = event.logicalKey == LogicalKeyboardKey.keyF &&
        keyboard.isShiftPressed &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_presenterFullscreen) {
        Future.microtask(() => _setPresenterFullscreen(false));
        return true;
      }
      final script = ref.read(scriptProvider);
      if (script == null || script.isEmpty) {
        Future.microtask(_exitPresentation);
        return true;
      }
    }
    if (!isSearchShortcut) return false;
    Future.microtask(_showSearchDialog);
    return true;
  }

  Future<void> _exitPresentation({bool returnCurrentPosition = false}) async {
    if (_closingPresentation) return;
    _closingPresentation = true;
    final navigator = Navigator.of(context);
    final teleprompterNotifier = _teleprompterNotifier;
    final returnWordIndex = returnCurrentPosition
        ? ref.read(teleprompterProvider).confirmedWordIndex
        : null;
    // Return to the editor IMMEDIATELY. Navigator.pop bypasses PopScope, and
    // popping before any await means a hung native fullscreen exit or a stalled
    // speech-session stop can never trap the user in present mode (the earlier
    // version awaited those first, and if the widget unmounted meanwhile the
    // `if (mounted) pop` was skipped). Cleanup now runs afterwards, best-effort.
    navigator.pop(returnWordIndex);
    _stopManualScroll();
    unawaited(teleprompterNotifier.stopSession().catchError((
      Object error,
      StackTrace stack,
    ) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'presenter.exitStopSession',
      );
    }));
    try {
      await _setPresenterFullscreen(false);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'presenter.exitFullscreenCleanup',
      );
    }
  }

  Future<void> _editCurrentPresenterPosition() async {
    await _exitPresentation(returnCurrentPosition: true);
  }

  Future<void> _togglePresenterFullscreen() async {
    await _setPresenterFullscreen(!_presenterFullscreen);
    _showWindowsControlsFromHotZone();
  }

  Future<void> _setPresenterFullscreen(bool enabled) async {
    if (!Platform.isWindows && enabled == _presenterFullscreen) return;
    try {
      final applied = await PresenterFullscreenService.setEnabled(enabled);
      if (!mounted) {
        _presenterFullscreen = applied;
        return;
      }
      _setTeleprompterState(() => _presenterFullscreen = applied);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'presenter.fullscreen',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fullscreen is unavailable.')),
        );
      }
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_presenterWalkthroughVisible) {
      if (mounted && !_controlsVisible) {
        _setTeleprompterState(() => _controlsVisible = true);
      }
      return;
    }
    final activeAutoHide = _presenterControlsAutoHideActive();
    if (!activeAutoHide) {
      if (mounted && !_controlsVisible) {
        _setTeleprompterState(() => _controlsVisible = true);
      }
      return;
    }
    _hideControlsTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      if (_shouldKeepPresenterControlsVisible()) {
        if (!_controlsVisible) {
          _setTeleprompterState(() => _controlsVisible = true);
        }
        _scheduleHideControls();
        return;
      }
      _setTeleprompterState(() => _controlsVisible = false);
    });
  }

  bool _presenterControlsAutoHideActive() {
    final tState = ref.read(teleprompterProvider);
    return PresenterInputLockService.controlsAutoHideActive(
      isListening: tState.isListening,
      isStarting: tState.isStarting,
    );
  }

  void _rememberPresenterPointer(PointerEvent event) {
    _lastPresenterPointerGlobalPosition = event.position;
  }

  bool _shouldKeepPresenterControlsVisible() {
    return PresenterInputLockService.shouldDeferControlsAutoHide(
      hoveringControls: _windowsControlsHovering,
      pointerInHotZone: _presenterPointerInControlsHotZone(),
    );
  }

  bool _presenterPointerInControlsHotZone() {
    final pointer = _lastPresenterPointerGlobalPosition;
    if (pointer == null) return false;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final local = renderObject.globalToLocal(pointer);
    return PresenterInputLockService.bottomControlsHotZoneContains(
      localX: local.dx,
      localY: local.dy,
      surfaceWidth: renderObject.size.width,
      surfaceHeight: renderObject.size.height,
      hotZoneHeight: _presenterControlsHotZoneHeight,
    );
  }

  void _showSttStartAffordance() {
    _sttStartAffordanceTimer?.cancel();
    _setTeleprompterState(() => _sttStartAffordanceVisible = true);
    _sttStartAffordanceTimer = Timer(_sttStartAffordanceDuration, () {
      if (!mounted) return;
      _setTeleprompterState(() => _sttStartAffordanceVisible = false);
    });
  }

  void _hideSttStartAffordance() {
    _sttStartAffordanceTimer?.cancel();
    if (_sttStartAffordanceVisible) {
      _setTeleprompterState(() => _sttStartAffordanceVisible = false);
    }
  }

  /// Show a dialog when speech recognition needs macOS language support.
  void _showMissingLanguageDialog(String languageName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Color(0xFFFFBF00), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$languageName Speech Recognition',
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$languageName is not available for offline speech recognition on this device.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.wifi_rounded, color: Color(0xFFFFBF00), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'An internet connection is required for this language.',
                    style: TextStyle(
                        color: Color(0xFFFFBF00),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Please try:',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Check macOS Speech Recognition permission\n\n'
              '2. Check Dictation and language support in macOS Keyboard settings\n\n'
              '3. Restart the teleprompter session',
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: some languages may require network-backed Apple speech '
              'recognition even when microphone permission is already granted.',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              MacOSPermissions.openSpeechSettings();
            },
            child: const Text('Open Speech Settings',
                style: TextStyle(color: Color(0xFF4DA8DA))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  /// Convert raw STT error codes into human-readable messages
  String _getUserFriendlyError(String error) {
    if (error.contains('requires an internet connection')) {
      return error; // Already user-friendly from provider
    }
    if (error.contains('error_permission') ||
        error.contains('insufficient_permissions')) {
      return 'Microphone permission denied. Open macOS System Settings > Privacy & Security > Microphone, then allow AutoTeleprompter.';
    }
    if (error.contains('error_language')) {
      return 'Language not available for speech recognition. Check macOS Speech Recognition permission and language availability.';
    }
    if (error.contains('error_audio')) {
      return 'Microphone not available. Check that no other app is using the microphone.';
    }
    if (error.contains('not available') || error.contains('init failed')) {
      return 'Speech recognition not available. Check macOS System Settings > Privacy & Security > Microphone and Speech Recognition.';
    }
    return error;
  }

  bool _isBrowserMicrophoneSettingsError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('webview2') ||
        normalized.contains('microphone blocked');
  }

  Future<void> _openMicrophonePrivacySettings() async {
    await MacOSPermissions.openMicrophoneSettings();
  }

  void _showControls() {
    if (!mounted) return;
    final activeAutoHide = _presenterControlsAutoHideActive();
    _setTeleprompterState(() => _controlsVisible = true);
    if (activeAutoHide) {
      _scheduleHideControls();
      return;
    }
    _hideControlsTimer?.cancel();
  }

  void _showWindowsControlsFromHotZone() {
    if (!Platform.isWindows) {
      _showControls();
      return;
    }
    _hideControlsTimer?.cancel();
    if (mounted && !_controlsVisible) {
      _setTeleprompterState(() => _controlsVisible = true);
    }
  }

  Future<void> _requestAndStart() async {
    if (Platform.isMacOS) {
      final micStatus = await MacOSPermissions.requestMicrophone();
      if (!mounted) return;
      if (!micStatus.isGranted) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Microphone Permission Required',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                'AutoTeleprompter needs microphone access to follow your speech.\n\nOpen macOS System Settings and allow microphone access for this app.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      MacOSPermissions.openMicrophoneSettings();
                    },
                    child: const Text('Open Settings',
                        style: TextStyle(color: Color(0xFFFFBF00)))),
              ],
            ),
          );
        }
        return;
      }

      final speechStatus = await MacOSPermissions.requestSpeech();
      if (!mounted) return;
      if (!speechStatus.isGranted) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Speech Permission Required',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                'Speech recognition permission is needed.\n\nOpen macOS System Settings and allow Speech Recognition for this app.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      MacOSPermissions.openSpeechSettings();
                    },
                    child: const Text('Open Settings',
                        style: TextStyle(color: Color(0xFFFFBF00)))),
              ],
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      await _maybeShowAppleSttPreflight();
      if (!mounted) return;
      _showSttStartAffordance();
      await _startCurrentScriptSession();
      return;
    }

    // Check current status first
    var micStatus = await Permission.microphone.status;

    // If permanently denied, go straight to app settings
    if (micStatus.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Microphone Permission Required',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'Microphone permission was denied.\n\nOpen macOS System Settings > Privacy & Security > Microphone, then allow AutoTeleprompter.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('Open Settings',
                      style: TextStyle(color: Color(0xFFFFBF00)))),
            ],
          ),
        );
      }
      return;
    }

    // Request if not yet granted
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }

    // On Apple platforms (iOS/macOS), also need speech recognition permission
    if (PlatformPermissions.requiresSpeechPermissionCheck) {
      final speechStatus = await Permission.speech.request();
      if (!speechStatus.isGranted) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Speech Permission Required',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                'Speech recognition permission is needed.\n\nGo to Settings and enable Speech Recognition.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      openAppSettings();
                    },
                    child: const Text('Open Settings',
                        style: TextStyle(color: Color(0xFFFFBF00)))),
              ],
            ),
          );
        }
        return;
      }
    }

    if (!micStatus.isGranted) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Microphone Permission Required',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'AutoTeleprompter needs microphone access to follow your speech.\n\nPlease grant the permission when prompted.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }

    final script = ref.read(scriptProvider);
    if (script != null) {
      _showSttStartAffordance();
      await _startCurrentScriptSession();
    }
  }

  Future<void> _startCurrentScriptSession() async {
    final script = ref.read(scriptProvider);
    if (script == null) return;
    await _teleprompterNotifier.startSession(script);
    if (!mounted) return;
    final currentIndex = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.isEmpty ? 0 : script.words.length - 1)
        .toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToWordIndex(currentIndex, anticipate: true);
    });
  }

  Future<void> _maybeShowAppleSttPreflight() async {
    final settings = ref.read(settingsProvider);
    if (settings.sttPreflightCompletedForVersion ==
        TeleprompterNotifier.appleSttPreflightVersion) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.record_voice_over_outlined,
                color: Color(0xFFFFBF00), size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Speech-control mic check',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When the session starts, read any clearly visible line near the place you want to begin, using the same distance and volume you will use while presenting.',
              style:
                  TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
            SizedBox(height: 14),
            Text(
              'Watch the Mic signal meter and quality badge. Clear means Apple Speech is matching the script. Low voice, Noise, or Matching means the app will keep listening and coach instead of restarting in a loop.',
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
            ),
            SizedBox(height: 14),
            Text(
              'For far speakers or loud rooms, use Noisy room mode, move the mic closer, lower room speaker volume, or have an operator ready with Manual Speed or Remote Control. If the room changes later, reopen Present settings and watch the Mic signal and quality badge again.',
              style:
                  TextStyle(color: Colors.white38, fontSize: 12, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ref
                  .read(settingsProvider.notifier)
                  .setSttPreflightCompletedForVersion(
                    TeleprompterNotifier.appleSttPreflightVersion,
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'Start speech control',
              style: TextStyle(color: Color(0xFFFFBF00)),
            ),
          ),
        ],
      ),
    );
  }

  // Smooth pixel-based manual scroll.
}
