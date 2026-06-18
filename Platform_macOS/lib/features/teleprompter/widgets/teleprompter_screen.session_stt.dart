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
            ref.read(teleprompterProvider.notifier).stopSession();
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
            ref.read(teleprompterProvider.notifier).resetPosition();
            _scrollController.jumpTo(0);
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

  Future<void> _togglePresenterColorInversion() async {
    final settings = ref.read(settingsProvider);
    final nextBackground =
        ScriptColorInversionService.nextBackgroundColor(settings);
    final nextFutureText =
        ScriptColorInversionService.futureTextColorForBackground(
      nextBackground,
    );

    final settingsNotifier = ref.read(settingsProvider.notifier);
    await settingsNotifier.setScriptBgColor(nextBackground);
    await settingsNotifier.setFutureWordColor(nextFutureText);
    await settingsNotifier.setShowUpcomingWordColor(true);
    await ref.read(scriptProvider.notifier).updateStyleMetadata(
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
    if (event.logicalKey == LogicalKeyboardKey.escape && _presenterFullscreen) {
      Future.microtask(() => _setPresenterFullscreen(false));
      return true;
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
    unawaited(teleprompterNotifier.stopSession().catchError((_) {}));
    try {
      await _setPresenterFullscreen(false);
    } catch (_) {}
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
    if (Platform.isWindows) {
      _hideControlsTimer?.cancel();
      final tState = ref.read(teleprompterProvider);
      final speechActive = tState.isListening || tState.isStarting;
      final activeAutoHide = speechActive || _manualScrolling;
      if (!activeAutoHide) {
        if (mounted && !_controlsVisible) {
          _setTeleprompterState(() => _controlsVisible = true);
        }
        return;
      }
      _hideControlsTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted || _windowsControlsHovering) return;
        _setTeleprompterState(() => _controlsVisible = false);
      });
      return;
    }
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _setTeleprompterState(() => _controlsVisible = false);
    });
  }

  /// Show a dialog when speech recognition needs a language pack.
  void _showMissingLanguageDialog(String languageName) {
    if (Platform.isWindows) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.settings_voice, color: Color(0xFFFFBF00), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text('Windows built-in speech-to-text',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Windows requires the "$languageName" Speech Pack for offline recognition. If no offline pack exists for this language, please enable Online Speech Recognition.',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text(
                'Action 1: Download Offline Pack',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Open Windows Settings -> Time & Language -> Speech, and add the speech pack if available.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Action 2: Enable Online Fallback',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'If offline is unavailable, open Privacy -> Speech, and toggle "Online speech recognition" to ON.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (Platform.isWindows) {
                  Process.run('cmd', ['/c', 'start', 'ms-settings:speech']);
                } else if (Platform.isMacOS) {
                  MacOSPermissions.openSpeechSettings();
                }
              },
              child: Text(
                  Platform.isMacOS ? 'Open Speech Settings' : 'Download Packs',
                  style: const TextStyle(color: Color(0xFF4DA8DA))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (Platform.isWindows) {
                  Process.run(
                      'cmd', ['/c', 'start', 'ms-settings:privacy-speech']);
                } else if (Platform.isMacOS) {
                  MacOSPermissions.openSpeechSettings();
                }
              },
              child: Text(
                  Platform.isMacOS ? 'Speech Privacy' : 'Online Fallback',
                  style: const TextStyle(color: Color(0xFF4DA8DA))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
      return;
    }

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
              '1. Connect this Windows device to the internet\n\n'
              '2. Enable online speech recognition if this language has no offline pack\n\n'
              '3. Restart the teleprompter session',
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: English may work offline if the speech pack is already downloaded. '
              'Other languages (Hebrew, Arabic, etc.) typically require an internet connection.',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
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
      return 'Microphone permission denied. Open Windows Settings > Privacy & security > Microphone, then allow microphone access and desktop apps.';
    }
    if (error.contains('error_language')) {
      return 'Language not available for speech recognition. Some languages need online speech recognition or an installed Windows speech pack.';
    }
    if (error.contains('error_audio')) {
      return 'Microphone not available. Check that no other app is using the microphone.';
    }
    if (error.contains('not available') || error.contains('init failed')) {
      return 'Speech recognition not available. Check Windows Settings > Time & Language > Speech, and Privacy & security > Microphone.';
    }
    return error;
  }

  bool _isBrowserMicrophoneSettingsError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('webview2') ||
        normalized.contains('microphone blocked');
  }

  Future<void> _openMicrophonePrivacySettings() async {
    if (Platform.isWindows) {
      await Process.run(
        'cmd',
        ['/c', 'start', 'ms-settings:privacy-microphone'],
      );
      return;
    }
    if (Platform.isMacOS) {
      await MacOSPermissions.openMicrophoneSettings();
      return;
    }
    await openAppSettings();
  }

  void _showControls() {
    if (Platform.isWindows) {
      final tState = ref.read(teleprompterProvider);
      final speechActive = tState.isListening || tState.isStarting;
      final activeAutoHide = speechActive || _manualScrolling;
      if (activeAutoHide && !_windowsControlsHovering) return;
      _setTeleprompterState(() => _controlsVisible = true);
      if (activeAutoHide) _scheduleHideControls();
      return;
    }
    _setTeleprompterState(() => _controlsVisible = true);
    _scheduleHideControls();
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
              'Microphone permission was denied.\n\nOpen Windows Settings > Privacy & security > Microphone, then allow microphone access and allow desktop apps.',
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
      await _startCurrentScriptSession();
    }
  }

  Future<void> _startCurrentScriptSession() async {
    final script = ref.read(scriptProvider);
    if (script == null) return;
    await _teleprompterNotifier.startSession(script);
    final currentIndex = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.isEmpty ? 0 : script.words.length - 1)
        .toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToWordIndex(currentIndex, anticipate: true);
    });
  }

  // Smooth pixel-based manual scroll.
}
