part of 'teleprompter_screen.dart';

extension _TeleprompterSessionSttParts on _TeleprompterScreenState {
  void _initRemoteListener() {
    _remoteCmdSub?.cancel();
    _remoteCmdSub = ref.read(remoteControlProvider).onCommand.listen((cmd) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);

      switch (cmd) {
        case 'TOGGLE':
          if (settings.scrollMode == 'manual') {
            _manualScrolling ? _stopManualScroll() : _startManualScroll();
          } else {
            final tState = ref.read(teleprompterProvider);
            tState.isListening
                ? ref.read(teleprompterProvider.notifier).stopSession()
                : _requestAndStart();
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
      }
    });
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

  Future<void> _stopPresentationSession() async {
    _stopManualScroll();
    await ref.read(teleprompterProvider.notifier).stopSession();
  }

  Future<void> _exitPresentation() async {
    if (_closingPresentation) return;
    final navigator = Navigator.of(context);
    final returnWordIndex = ref.read(teleprompterProvider).confirmedWordIndex;
    if (mounted) {
      _setTeleprompterState(() => _closingPresentation = true);
    } else {
      _closingPresentation = true;
    }
    await _setPresenterFullscreen(false);
    await _stopPresentationSession();
    if (mounted) navigator.pop(returnWordIndex);
  }

  Future<void> _editCurrentPresenterPosition() async {
    await _exitPresentation();
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fullscreen is unavailable.')),
        );
      }
    }
  }

  Future<void> _initWebViewController() async {
    try {
      // By using this environment variable, we force WebView2 (Chromium) to
      // automatically grant microphone and camera permissions for the app.
      // This is the standard secure way to bypass the missing Permission API
      // in the current Windows WebView plugin.
      const envKey = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';
      const envVal =
          '--use-fake-ui-for-media-stream --unsafely-treat-insecure-origin-as-secure=http://localhost:8082 --autoplay-policy=no-user-gesture-required';

      // We'll set it via setx to ensure it persists across the session
      await Process.run('setx', [envKey, envVal], runInShell: true);

      final controller = WebviewController();
      await controller.initialize();

      if (mounted) _setTeleprompterState(() => _webviewController = controller);
    } catch (_) {}
  }

  Future<void> _loadSttWebView(String url) async {
    _loadedWebViewUrl = url;
    if (_webviewController == null) await _initWebViewController();
    try {
      await _webviewController?.loadUrl(url);
    } catch (_) {}
  }

  void _scheduleHideControls() {
    if (Platform.isWindows) {
      _hideControlsTimer?.cancel();
      final tState = ref.read(teleprompterProvider);
      final speechActive = tState.isListening || tState.isStarting;
      if (!speechActive) {
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

  /// Show a dialog when Google speech recognition fails
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
                child: Text('Windows Built-In STT',
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
                Process.run('cmd', ['/c', 'start', 'ms-settings:speech']);
              },
              child: const Text('Download Packs',
                  style: TextStyle(color: Color(0xFF4DA8DA))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Process.run(
                    'cmd', ['/c', 'start', 'ms-settings:privacy-speech']);
              },
              child: const Text('Online Fallback',
                  style: TextStyle(color: Color(0xFF4DA8DA))),
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
                    'An internet connection (WiFi or mobile data) is required for this language.',
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
              '1. Connect to WiFi or enable mobile data\n\n'
              '2. Make sure the Google app is installed and updated\n\n'
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
      return 'Microphone permission denied. Please enable it in your device settings: Settings → Apps → AutoTeleprompter → Permissions → Microphone';
    }
    if (error.contains('error_language')) {
      return 'Language not available for speech recognition. Please connect to WiFi or mobile data — some languages require an internet connection.';
    }
    if (error.contains('error_audio')) {
      return 'Microphone not available. Check that no other app is using the microphone.';
    }
    if (error.contains('not available') || error.contains('init failed')) {
      return 'Speech recognition not available. Make sure the Google app is installed and updated.';
    }
    return error;
  }

  void _showControls() {
    if (Platform.isWindows) {
      final tState = ref.read(teleprompterProvider);
      final speechActive = tState.isListening || tState.isStarting;
      if (speechActive && !_windowsControlsHovering) return;
      _setTeleprompterState(() => _controlsVisible = true);
      if (speechActive) _scheduleHideControls();
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

  void _syncWindowsControlsForSpeech(bool speechActive) {
    if (!Platform.isWindows || !mounted) return;
    _hideControlsTimer?.cancel();
    _windowsControlsHovering = false;
    _setTeleprompterState(() => _controlsVisible = !speechActive);
  }

  Future<void> _requestAndStart() async {
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
              'Microphone permission was denied. Please enable it in your device settings:\n\nSettings → Apps → AutoTeleprompter → Permissions → Microphone',
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
      await ref.read(teleprompterProvider.notifier).startSession(script);
      final currentIndex = ref
          .read(teleprompterProvider)
          .confirmedWordIndex
          .clamp(0, script.words.isEmpty ? 0 : script.words.length - 1)
          .toInt();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToWordIndex(currentIndex, anticipate: true);
      });
    }
  }

  // ── Smooth pixel-based manual scroll ───────────────────────────────────────
}
