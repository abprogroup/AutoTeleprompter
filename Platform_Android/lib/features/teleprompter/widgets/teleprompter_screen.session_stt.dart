part of 'teleprompter_screen.dart';

extension _TeleprompterSessionSttParts on _TeleprompterScreenState {
  void _initRemoteListener() {
    _remoteCmdSub?.cancel();
    _remoteCmdSub = ref.read(remoteControlProvider).onCommand.listen((cmd) {
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
    if (mounted) {
      setState(() => _closingPresentation = true);
    } else {
      _closingPresentation = true;
    }
    await _stopPresentationSession();
    if (mounted) navigator.pop();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// Show a dialog when speech recognition cannot use the requested language.
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
              '$languageName is not available for on-device (offline) speech recognition on this phone.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.wifi_rounded, color: Color(0xFFFFBF00), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'An internet connection (WiFi or mobile data) may help if this device falls back to online recognition.',
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
              '2. Check Settings > System > Languages & input > On-device speech '
              'recognition and confirm this language is downloaded\n\n'
              '3. Confirm microphone and speech-recognition permissions for this app\n\n'
              '4. Restart the teleprompter session',
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: some manufacturers restrict which offline languages can be '
              'installed, or route speech recognition through their own app '
              'instead of stock Android settings.',
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
      return 'Microphone permission denied. Please enable it in macOS Settings -> Privacy & Security -> Microphone.';
    }
    if (error.contains('error_language')) {
      return 'Language not available for speech recognition. Please connect to WiFi or mobile data - some languages require an internet connection.';
    }
    if (error.contains('error_audio')) {
      return 'Microphone not available. Check that no other app is using the microphone.';
    }
    if (error.contains('not available') || error.contains('init failed')) {
      return 'Speech recognition not available. Please confirm macOS speech-recognition permission and try again.';
    }
    return error;
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
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
              'Microphone permission was denied. Please enable it in macOS Settings -> Privacy & Security -> Microphone.',
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
