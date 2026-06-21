part of 'content_creator_screen.dart';

extension _ContentCreatorRecording on _ContentCreatorScreenState {
  Future<void> _toggleRecording() async {
    if (_recordStartInFlight) return;

    if (_isRecording) {
      await _stopRecording();
      return;
    }

    final settings = ref.read(settingsProvider);
    if (_contentAudioOnlyMode(settings)) {
      await _startAudioRecording(settings);
    } else {
      await _startVideoRecording(settings);
    }
  }

  Future<void> _startVideoRecording(AppSettings settings) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showSnack('Camera is not ready.');
      return;
    }
    if (!await _ensureCameraAndMicrophonePermission()) return;
    _setContentCreatorState(() => _recordStartInFlight = true);
    try {
      await _startSpeechForRecordingIfNeeded(settings);
      if (!mounted) return;
      await _runCountdown();
      if (!mounted || !_recordStartInFlight) return;
      await _cameraController!.startVideoRecording();
      _startRecordTimer();
      _setContentCreatorState(() {
        _isRecording = true;
        _isAudioOnlyRecording = false;
        _recordStartInFlight = false;
      });
    } catch (e) {
      debugPrint('Recording start error: $e');
      await _stopSpeechIfOwnedByRecording();
      if (mounted) {
        _setContentCreatorState(() => _recordStartInFlight = false);
        _showSnack('Recording could not start.');
      }
    }
  }

  Future<void> _startAudioRecording(AppSettings settings) async {
    if (!await _ensureMicrophonePermission()) return;
    _setContentCreatorState(() => _recordStartInFlight = true);
    try {
      await _startSpeechForRecordingIfNeeded(settings);
      if (!mounted) return;
      await _runCountdown();
      if (!mounted || !_recordStartInFlight) return;
      final savedPath = await _audioRecorder.start();
      _startRecordTimer();
      _setContentCreatorState(() {
        _isRecording = true;
        _isAudioOnlyRecording = true;
        _recordStartInFlight = false;
      });
      _showSnack('Audio recording started: $savedPath');
    } catch (e) {
      debugPrint('Audio recording start error: $e');
      await _stopSpeechIfOwnedByRecording();
      if (mounted) {
        _setContentCreatorState(() => _recordStartInFlight = false);
        _showSnack('Audio recording could not start.');
      }
    }
  }

  Future<void> _stopRecording() async {
    final wasAudioOnly = _isAudioOnlyRecording;
    var savedToPhotos = wasAudioOnly;
    try {
      final String? savedPath;
      if (wasAudioOnly) {
        savedPath = await _audioRecorder.stop();
      } else {
        final file = await _cameraController!.stopVideoRecording();
        savedPath = file.path;
        try {
          await Gal.putVideo(file.path);
          savedToPhotos = true;
        } catch (e) {
          debugPrint('Save error: $e');
          savedToPhotos = false;
        }
      }
      _recordTimer?.cancel();
      await _stopSpeechIfOwnedByRecording();
      if (!mounted) return;
      _setContentCreatorState(() {
        _isRecording = false;
        _isAudioOnlyRecording = false;
        _recordSeconds = 0;
      });
      _showSnack(
        wasAudioOnly
            ? 'Audio recording saved: $savedPath'
            : savedToPhotos
                ? 'Video saved to Photos.'
                : 'Video recorded, but Photos save failed.',
        backgroundColor: wasAudioOnly || savedToPhotos
            ? Colors.green
            : Colors.orangeAccent,
      );
    } catch (e) {
      debugPrint('Recording stop error: $e');
      if (mounted) _showSnack('Recording could not stop cleanly.');
    }
  }

  Future<void> _runCountdown() async {
    for (int i = 3; i > 0; i--) {
      if (!mounted || !_recordStartInFlight) return;
      _setContentCreatorState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (mounted) _setContentCreatorState(() => _countdown = 0);
  }

  void _startRecordTimer() {
    _recordSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) _setContentCreatorState(() => _recordSeconds = t.tick);
    });
    unawaited(ref.read(settingsProvider.notifier).setScrollSpeed(100));
  }

  Future<void> _startSpeechForRecordingIfNeeded(AppSettings settings) async {
    if (!settings.contentCreatorRecordingControlsSpeech) {
      _recordingStartedSpeechSession = false;
      return;
    }
    final tState = ref.read(teleprompterProvider);
    if (tState.isListening || tState.isStarting) {
      _recordingStartedSpeechSession = false;
      return;
    }
    _recordingStartedSpeechSession = true;
    await _requestAndStartSpeechSession();
    final afterStart = ref.read(teleprompterProvider);
    if (!afterStart.isListening && !afterStart.isStarting) {
      _recordingStartedSpeechSession = false;
    }
  }

  Future<void> _stopSpeechIfOwnedByRecording() async {
    if (!_recordingStartedSpeechSession) return;
    _recordingStartedSpeechSession = false;
    await _teleprompterNotifier.stopSession();
  }

  Future<void> _toggleSpeechSession() async {
    final tState = ref.read(teleprompterProvider);
    if (tState.isListening || tState.isStarting) {
      await _teleprompterNotifier.stopSession();
      return;
    }
    await _requestAndStartSpeechSession();
  }

  Future<void> _requestAndStartSpeechSession() async {
    if (!await _ensureMicrophonePermission()) return;
    if (PlatformPermissions.requiresSpeechPermissionCheck) {
      var speechStatus = await Permission.speech.status;
      if (speechStatus.isPermanentlyDenied) {
        _showSnack('Speech permission is blocked. Open Settings.');
        await openAppSettings();
        return;
      }
      if (!speechStatus.isGranted) {
        speechStatus = await Permission.speech.request();
      }
      if (!speechStatus.isGranted) {
        _showSnack('Speech recognition permission is required.');
        return;
      }
    }

    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) {
      _showSnack('Load a script before starting speech.');
      return;
    }
    await _teleprompterNotifier.startSession(script);
  }

  Future<bool> _ensureCameraAndMicrophonePermission() async {
    var cameraStatus = await Permission.camera.status;
    if (cameraStatus.isPermanentlyDenied) {
      _showSnack('Camera permission is blocked. Open Settings.');
      await openAppSettings();
      return false;
    }
    if (!cameraStatus.isGranted) {
      cameraStatus = await Permission.camera.request();
    }
    if (!cameraStatus.isGranted) {
      _showSnack('Camera permission is required for video recording.');
      return false;
    }
    return _ensureMicrophonePermission();
  }

  Future<bool> _ensureMicrophonePermission() async {
    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      _showSnack('Microphone permission is blocked. Open Settings.');
      await openAppSettings();
      return false;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    if (!micStatus.isGranted) {
      _showSnack('Microphone permission is required.');
      return false;
    }
    return true;
  }

  bool _contentAudioOnlyMode(AppSettings settings) {
    return widget.audioOnlyEntry ||
        settings.contentCreatorRecordingFormat ==
            AppSettings.contentCreatorRecordingFormatAudio;
  }

  Future<void> _exitContentCreator() async {
    if (_isRecording || _recordStartInFlight) {
      _showSnack('Stop recording before returning to the editor.');
      return;
    }
    final navigator = Navigator.of(context);
    final notifier = _teleprompterNotifier;
    navigator.pop();
    unawaited(notifier.stopSession());
  }

  void _resetCreatorPosition() {
    _teleprompterNotifier.resetPosition();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _showSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  String _formatTimer(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
}
