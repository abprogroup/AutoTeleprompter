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

  void _disposeTeleprompterScreenBody() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _hideControlsTimer?.cancel();
    _smoothScrollTimer?.cancel();
    _scrollController.dispose();
    _presentationFocusNode.dispose();
    _remoteCmdSub?.cancel();
    ref.read(teleprompterProvider.notifier).stopSession();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// Show a dialog when Google speech recognition fails
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
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  Future<void> _offerResumeOrRestart(int currentIndex) async {
    if (_resumePromptShown || currentIndex <= 0 || !mounted) return;
    _resumePromptShown = true;
    _scrollToWordIndex(currentIndex);

    final shouldRestart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Resume presentation?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Continue from the last reading point, or restart this script from the beginning?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue',
                style: TextStyle(color: Color(0xFFFFBF00))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Restart', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (shouldRestart == true) {
      ref.read(teleprompterProvider.notifier).resetPosition();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } else {
      _scrollToWordIndex(ref.read(teleprompterProvider).confirmedWordIndex);
    }
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
    }
  }
}
