part of 'content_creator_screen.dart';

/// Links Content Creator's recording start/stop to a real STT session, and
/// offers to resume from a saved reading position. Ported from Windows'
/// `content_creator_screen.session.dart`, scoped down to what's portable:
/// Android has no desktop webcam-device-selection UI or fullscreen-linking
/// concept, so only the recording<->speech-session link and the resume
/// prompt were ported - camera settings presets and fullscreen linking are
/// tracked separately, not part of this pass.
extension _ContentCreatorSessionParts on _ContentCreatorScreenState {
  void _showContentSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  Future<void> _requestAndStartContentSpeech() async {
    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      _showContentSnack(
          'Microphone permission is blocked. Enable it in system Settings.');
      await openAppSettings();
      return;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    if (!micStatus.isGranted) {
      _showContentSnack(
          'Microphone permission is required for speech-to-text.');
      return;
    }

    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await ref.read(teleprompterProvider.notifier).startSession(script);
  }

  Future<void> _startContentSpeechSessionForRecording(
    AppSettings settings,
  ) async {
    if (!settings.contentCreatorRecordingControlsSpeech) {
      _recordingStartedSpeechSession = false;
      return;
    }
    final live = ref.read(teleprompterProvider);
    if (live.isListening || live.isStarting) {
      _recordingStartedSpeechSession = false;
      return;
    }
    _recordingStartedSpeechSession = true;
    await _requestAndStartContentSpeech();
    final afterStart = ref.read(teleprompterProvider);
    if (!afterStart.isListening && !afterStart.isStarting) {
      _recordingStartedSpeechSession = false;
    }
  }

  Future<void> _stopContentSpeechSessionIfOwnedByRecording() async {
    if (!_recordingStartedSpeechSession) return;
    _recordingStartedSpeechSession = false;
    try {
      await ref.read(teleprompterProvider.notifier).stopSession();
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingSpeechStop',
      );
    }
  }

  /// Shown once per Content Creator entry when the shared teleprompter
  /// session already has a non-zero reading position (e.g. the user was
  /// presenting before opening Content Creator, or a previous Content
  /// Creator session left off partway through the script).
  void _maybeShowContentResumePrompt(Script script) {
    if (_resumeDialogShown || script.words.isEmpty) return;
    final savedIndex = ref.read(teleprompterProvider).confirmedWordIndex;
    if (savedIndex <= 0) return;
    _resumeDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
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
      if (!mounted || restart != true) return;
      ref.read(teleprompterProvider.notifier).resetPosition();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }
}
