part of 'content_creator_screen.dart';

extension _ContentCreatorRecording on _ContentCreatorScreenState {
  Future<void> _playRecordingCountdownTick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      if (kDebugMode) debugPrint('Countdown tick cue failed: $e');
    }
  }

  Future<void> _playRecordingStartCue() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      if (kDebugMode) debugPrint('Recording start cue failed: $e');
    }
  }

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
      _showContentSnack('Camera is not ready.');
      return;
    }
    if (!await _ensureCameraAndMicrophonePermission()) return;
    _setContentCreatorState(() => _recordStartInFlight = true);
    try {
      await _startContentSpeechSessionForRecording(settings);
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
      if (kDebugMode) debugPrint('Recording start error: $e');
      await _stopContentSpeechSessionIfOwnedByRecording();
      if (mounted) {
        _setContentCreatorState(() => _recordStartInFlight = false);
        _showContentSnack('Recording could not start.');
      }
    }
  }

  Future<void> _startAudioRecording(AppSettings settings) async {
    if (!await _ensureMicrophonePermission()) return;
    _setContentCreatorState(() => _recordStartInFlight = true);
    try {
      await _startContentSpeechSessionForRecording(settings);
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
      _showContentSnack('Audio recording started: $savedPath');
    } catch (e) {
      if (kDebugMode) debugPrint('Audio recording start error: $e');
      await _stopContentSpeechSessionIfOwnedByRecording();
      if (mounted) {
        _setContentCreatorState(() => _recordStartInFlight = false);
        _showContentSnack('Audio recording could not start.');
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_isAudioOnlyRecording) {
      await _stopAudioRecording();
    } else {
      await _stopVideoRecording();
    }
  }

  Future<void> _stopVideoRecording() async {
    final rawFile = await _cameraController!.stopVideoRecording();
    await _stopContentSpeechSessionIfOwnedByRecording();
    _recordTimer?.cancel();
    _setContentCreatorState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });
    try {
      final tempDir = await getTemporaryDirectory();
      final export = await const RecordingExportService().exportMp4(
        sourceFile: File(rawFile.path),
        destinationDirectory:
            Directory('${tempDir.path}${Platform.pathSeparator}recordings'),
      );
      final probe = await const RecordingMediaProbeService()
          .inspect(File(export.outputPath));
      final assessment = const RecordingMediaProbePolicy().assess(
        probe: probe,
        savedPath: export.outputPath,
        expectVideo: true,
        expectAudio: true,
      );
      await Gal.putVideo(export.outputPath);
      try {
        await File(export.outputPath).delete();
      } catch (_) {}
      if (mounted) {
        _showContentSnack(
          assessment.hasWarning
              ? assessment.message
              : 'Video saved to gallery!',
          backgroundColor: assessment.hasWarning ? Colors.orange : Colors.green,
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingSave',
      );
      if (mounted) {
        _showContentSnack('Could not save the recording.',
            backgroundColor: Colors.red);
      }
    }
  }

  Future<void> _stopAudioRecording() async {
    await _stopContentSpeechSessionIfOwnedByRecording();
    _recordTimer?.cancel();
    _setContentCreatorState(() {
      _isRecording = false;
      _isAudioOnlyRecording = false;
      _recordSeconds = 0;
    });
    try {
      final savedPath = await _audioRecorder.stop();
      if (mounted) {
        _showContentSnack('Audio recording saved: $savedPath',
            backgroundColor: Colors.green);
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.audioRecordingSave',
      );
      if (mounted) {
        _showContentSnack('Could not save the audio recording.',
            backgroundColor: Colors.red);
      }
    }
  }

  Future<void> _runCountdown() async {
    for (int i = 3; i > 0; i--) {
      if (!mounted || !_recordStartInFlight) return;
      _setContentCreatorState(() => _countdown = i);
      await _playRecordingCountdownTick();
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted || !_recordStartInFlight) return;
    _setContentCreatorState(() => _countdown = 0);
    await _playRecordingStartCue();
  }

  void _startRecordTimer() {
    _recordSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) _setContentCreatorState(() => _recordSeconds = t.tick);
    });
    unawaited(ref.read(settingsProvider.notifier).setScrollSpeed(100));
    _onCreatorSessionActivated();
  }

  Future<void> _toggleSpeechSession() async {
    final tState = ref.read(teleprompterProvider);
    if (tState.isListening || tState.isStarting) {
      await ref.read(teleprompterProvider.notifier).stopSession();
      return;
    }
    await _requestAndStartContentSpeech();
    _onCreatorSessionActivated();
  }

  Future<bool> _ensureCameraAndMicrophonePermission() async {
    var cameraStatus = await Permission.camera.status;
    if (!mounted) return false;
    if (cameraStatus.isPermanentlyDenied) {
      _showContentSnack('Camera permission is blocked. Open Settings.');
      await openAppSettings();
      if (!mounted) return false;
      return false;
    }
    if (!cameraStatus.isGranted) {
      cameraStatus = await Permission.camera.request();
      if (!mounted) return false;
    }
    if (!cameraStatus.isGranted) {
      _showContentSnack('Camera permission is required for video recording.');
      return false;
    }
    return _ensureMicrophonePermission();
  }

  Future<bool> _ensureMicrophonePermission() async {
    var micStatus = await Permission.microphone.status;
    if (!mounted) return false;
    if (micStatus.isPermanentlyDenied) {
      _showContentSnack('Microphone permission is blocked. Open Settings.');
      await openAppSettings();
      if (!mounted) return false;
      return false;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!mounted) return false;
    }
    if (!micStatus.isGranted) {
      _showContentSnack('Microphone permission is required.');
      return false;
    }
    return true;
  }

  Future<void> _exitContentCreator() async {
    if (_isRecording || _recordStartInFlight) {
      _showContentSnack('Stop recording before returning to the editor.');
      return;
    }
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(ref.read(teleprompterProvider.notifier).stopSession());
  }

  void _resetCreatorPosition() {
    _smoothScrollTimer?.cancel();
    _smoothScrollActive = false;
    _lastFollowedWordIndex = 0;
    ref.read(teleprompterProvider.notifier).resetPosition();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
