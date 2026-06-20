part of 'content_creator_screen.dart';

extension _ContentCreatorSession on _ContentCreatorScreenState {
  Future<void> _exitContentCreator({bool returnCurrentPosition = false}) async {
    if (_isRecording || _recordStartInFlight) {
      _showSnack('Stop recording before returning to the editor.');
      return;
    }
    final navigator = Navigator.of(context);
    final teleprompterNotifier = _teleprompterNotifier;
    final returnWordIndex =
        returnCurrentPosition ? _activeContentIndex() : null;
    _stopAutoScroll();
    // Return to the editor IMMEDIATELY (pop before any await) so a stalled
    // speech-session stop or native fullscreen exit can never trap the user in
    // Content Creator / record mode. Cleanup runs afterwards, best-effort.
    navigator.pop(returnWordIndex);
    unawaited(teleprompterNotifier.stopSession().catchError((error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.exitStopSession',
      );
    }));
    try {
      await _setContentFullscreen(false);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.exitFullscreenCleanup',
      );
    }
  }

  Future<void> _exitContentCreatorAtCurrentPosition() async {
    await _exitContentCreator(returnCurrentPosition: true);
  }

  Future<void> _toggleContentFullscreen() async {
    await _setContentFullscreen(!_contentFullscreen);
    _showContentControlsFromHotZone();
  }

  Future<void> _setContentFullscreen(bool enabled) async {
    if (enabled == _contentFullscreen) return;
    try {
      final applied = await PresenterFullscreenService.setEnabled(enabled);
      if (!mounted) {
        _contentFullscreen = applied;
        return;
      }
      _updateContentCreatorState(() => _contentFullscreen = applied);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.fullscreen',
      );
      if (mounted) _showSnack('Fullscreen is unavailable.');
    }
  }

  Future<void> _toggleContentSpeechSession() async {
    final tState = ref.read(teleprompterProvider);
    if (tState.isListening || tState.isStarting) {
      _hideContentSttStartAffordance();
      _stopAutoScroll();
      await _teleprompterNotifier.stopSession();
      if (!mounted) return;
      _syncContentControlsForActiveSession(
          _isRecording || _recordStartInFlight);
      _logContentDebug('reader speech session stopped');
      return;
    }

    final settings = ref.read(settingsProvider);
    if (settings.scrollMode == 'manual') {
      if (_contentManualScrolling) {
        _stopAutoScroll();
        _syncContentControlsForActiveSession(
            _isRecording || _recordStartInFlight);
        _logContentDebug('reader manual scroll stopped');
      } else {
        _startContentManualScroll();
        _logContentDebug('reader manual scroll started');
      }
      _showContentControlsFromHotZone();
      return;
    }
    await _requestAndStartContentSpeech();
  }

  Future<void> _requestAndStartContentSpeech() async {
    if (Platform.isMacOS) {
      final micStatus = await MacOSPermissions.requestMicrophone();
      if (!mounted) return;
      if (!micStatus.isGranted) {
        _showSnack('Microphone permission is required for speech-to-text.');
        if (micStatus.isBlocked) {
          await MacOSPermissions.openMicrophoneSettings();
        }
        return;
      }
      final speechStatus = await MacOSPermissions.requestSpeech();
      if (!mounted) return;
      if (!speechStatus.isGranted) {
        _showSnack('Speech recognition permission is required.');
        if (speechStatus.isBlocked) await MacOSPermissions.openSpeechSettings();
        return;
      }
    } else {
      var micStatus = await Permission.microphone.status;
      if (!mounted) return;
      if (micStatus.isPermanentlyDenied) {
        _showSnack('Microphone permission is blocked. Open System Settings.');
        await openAppSettings();
        return;
      }
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
        if (!mounted) return;
      }
      if (PlatformPermissions.requiresSpeechPermissionCheck) {
        final speechStatus = await Permission.speech.request();
        if (!mounted) return;
        if (!speechStatus.isGranted) {
          _showSnack('Speech recognition permission is required.');
          return;
        }
      }
      if (!micStatus.isGranted) {
        _showSnack('Microphone permission is required for speech-to-text.');
        return;
      }
    }
    if (!mounted) return;

    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    _stopAutoScroll();
    _showContentSttStartAffordance();
    await _teleprompterNotifier.startSession(script);
    if (!mounted) return;
    final currentIndex = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    _updateContentCreatorState(() => _activeWordIndex = currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToContentWordIndex(currentIndex, immediate: true);
      _syncContentControlsForActiveSession(true);
    });
    _logContentDebug('reader speech session started word=$currentIndex');
  }

  Future<void> _startContentSpeechSessionForRecording(
    AppSettings settings,
  ) async {
    if (!settings.contentCreatorRecordingControlsSpeech) {
      _recordingStartedSpeechSession = false;
      _logContentDebug('recording start keeps speech session separate');
      return;
    }
    final live = ref.read(teleprompterProvider);
    if (live.isListening || live.isStarting) {
      _recordingStartedSpeechSession = true;
      _logContentDebug('recording linked to existing speech session');
      return;
    }
    _recordingStartedSpeechSession = true;
    await _requestAndStartContentSpeech();
    if (!mounted) return;
    final afterStart = ref.read(teleprompterProvider);
    if (!afterStart.isListening && !afterStart.isStarting) {
      _recordingStartedSpeechSession = false;
      _logContentDebug('recording speech link did not start session');
    } else {
      _logContentDebug('recording speech session started');
    }
  }

  Future<void> _stopContentSpeechSessionIfOwnedByRecording() async {
    if (!_recordingStartedSpeechSession) return;
    _recordingStartedSpeechSession = false;
    _hideContentSttStartAffordance();
    try {
      await _teleprompterNotifier.stopSession();
      _logContentDebug('recording speech session stopped');
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingSpeechStop',
      );
      _logContentDebug('recording speech stop failed $error');
    }
  }

  void _confirmContentFrame() {
    _updateContentCreatorState(() {
      _contentFrameConfirmed = true;
      _contentResumeDecisionPending = _contentEntryResumeIndex > 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final script = ref.read(scriptProvider);
      if (script != null) _maybeShowContentResumePrompt(script);
    });
  }

  void _maybeShowContentResumePrompt(Script script) {
    if (_resumeDialogShown || script.words.isEmpty) return;
    final savedIndex = _contentEntryResumeIndex;
    if (savedIndex <= 0) return;

    _resumeDialogShown = true;
    _updateContentCreatorState(() => _contentResumeDecisionPending = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_contentResumeDecisionPending) return;
      final target = savedIndex.clamp(0, script.words.length - 1).toInt();
      _updateContentCreatorState(() => _activeWordIndex = target);
      _scrollToContentWordIndex(target, immediate: true);
      _logContentDebug('resume prompt shown savedWord=$target');

      final restart = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Resume reading?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Continue Content Creator from the saved reading position, or '
            'restart this script from the beginning.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restart'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      _updateContentCreatorState(() => _contentResumeDecisionPending = false);
      if (restart == false) {
        _logContentDebug('resume prompt choice continue word=$target');
        _jumpToContentWordIndex(target, immediate: true);
      } else {
        _logContentDebug('resume prompt choice restart');
        _resetContentPosition();
      }
    });
  }
}
