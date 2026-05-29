part of 'content_creator_screen.dart';

extension _ContentCreatorSession on _ContentCreatorScreenState {
  Future<void> _stopContentSpeechSessionIfOwnedByRecording() async {
    if (!_recordingStartedSpeechSession) return;
    _recordingStartedSpeechSession = false;
    try {
      await ref.read(teleprompterProvider.notifier).stopSession();
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
      if (restart == true) {
        _logContentDebug('resume prompt choice restart');
        _resetContentPosition();
      } else {
        _logContentDebug('resume prompt choice continue word=$target');
        _jumpToContentWordIndex(target, immediate: true);
      }
    });
  }
}
