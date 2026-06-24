part of 'content_creator_screen.dart';

extension _ContentCreatorRecordingFlow on _ContentCreatorScreenState {
  Future<void> _playRecordingCountdownTick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingCountdownTick',
      );
    }
  }

  Future<void> _playRecordingStartCue() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingStartCue',
      );
    }
  }

  Future<bool> _prepareCameraAudioForRecording({
    required bool recordCameraAudio,
  }) async {
    if (!recordCameraAudio) {
      if (_cameraAudioEnabled) {
        await _releaseCameraAudioAfterRecording();
      }
      return _isActiveCameraInitialized();
    }

    if (_cameraAudioEnabled && _isActiveCameraInitialized()) {
      return true;
    }

    await _initializeCamera(
      preferredCamera: _selectedCameraDescription(),
      enableAudio: true,
    );
    return mounted &&
        _recordStartInFlight &&
        _isActiveCameraInitialized() &&
        _cameraAudioEnabled;
  }

  Future<void> _releaseCameraAudioAfterRecording() async {
    if (!_cameraAudioEnabled || !mounted) return;
    await _initializeCamera(preferredCamera: _selectedCameraDescription());
  }

  Future<void> _toggleRecording() async {
    if (_recordStartInFlight && !_isRecording) {
      _updateContentCreatorState(() {
        _recordStartInFlight = false;
        _countdown = 0;
      });
      await _stopContentSpeechSessionIfOwnedByRecording();
      await _releaseCameraAudioAfterRecording();
      if (!mounted) return;
      _syncContentControlsForActiveSession(false);
      _showSnack('Recording countdown canceled.');
      _logContentDebug('recording countdown canceled');
      return;
    }

    final settings = ref.read(settingsProvider);
    if (_isAudioOnlyRecording ||
        settings.contentCreatorRecordingFormat ==
            AppSettings.contentCreatorRecordingFormatWav) {
      await _toggleAudioOnlyRecording();
      return;
    }

    if (!_isActiveCameraInitialized()) {
      _showSnack(
        _cameraError ?? 'Camera is still preparing. Try again in a moment.',
      );
      return;
    }

    if (_isRecording) {
      final filePath = Platform.isMacOS
          ? await _macCameraController!.stopVideoRecording()
          : (await _cameraController!.stopVideoRecording()).path;
      if (!mounted) return;
      final recordedSeconds = _recordSeconds;
      _recordTimer?.cancel();
      _updateContentCreatorState(() {
        _isRecording = false;
        _recordStartInFlight = false;
        _recordSeconds = 0;
      });
      await _stopContentSpeechSessionIfOwnedByRecording();
      await _releaseCameraAudioAfterRecording();
      if (!mounted) return;
      _syncContentControlsForActiveSession(false);
      try {
        _updateContentCreatorState(() => _recordExportProgress = 0.0);
        final savedPath = await _saveRecordingToChosenFolder(filePath);
        if (!mounted) return;
        await _backupRecordingIfEnabled(savedPath);
        final saveMessage = await _recordingSaveMessage(
          savedPath,
          format: settings.contentCreatorRecordingFormat,
          expectAudio: settings.contentCreatorRecordingAudioMode ==
              AppSettings.contentCreatorRecordingAudioCamera,
          expectVideo: true,
        );
        _showSnack(saveMessage);
      } catch (e, stack) {
        if (kDebugMode) debugPrint('Save error: $e');
        _showSnack('Recording stopped, but saving to the folder failed.');
        LightweightDiagnostics.instance.recordError(
          e,
          stack,
          source: 'contentCreator.recordingSave',
        );
      } finally {
        if (mounted) {
          _updateContentCreatorState(() => _recordExportProgress = null);
        }
      }
      _logContentDebug('recording stopped seconds=$recordedSeconds');
    } else {
      const recordingExporter = RecordingExportService();
      if (!await recordingExporter.canExport(
        settings.contentCreatorRecordingFormat,
      )) {
        await ref
            .read(settingsProvider.notifier)
            .setContentCreatorRecordingFormat(
              AppSettings.contentCreatorRecordingFormatMp4,
            );
        _showSnack(
          'This app records MP4 video and WAV audio directly. Extra video '
          'file types require platform-specific recording support.',
        );
        _logContentDebug('recording reset unsupported format='
            '${settings.contentCreatorRecordingFormat}');
        return;
      }
      final recordCameraAudio = settings.contentCreatorRecordingAudioMode ==
          AppSettings.contentCreatorRecordingAudioCamera;
      _commitContentVisibleReadingLine(reason: 'video recording start');
      _updateContentCreatorState(() {
        _recordStartInFlight = true;
        _countdown = 3;
        _contentControlsVisible = true;
      });
      _hideContentControlsTimer?.cancel();
      await _startContentSpeechSessionForRecording(settings);
      if (!mounted || !_recordStartInFlight) {
        await _stopContentSpeechSessionIfOwnedByRecording();
        await _releaseCameraAudioAfterRecording();
        _syncContentControlsForActiveSession(false);
        return;
      }
      _logContentDebug('recording start preparing camera '
          'audio=${recordCameraAudio ? 'camera' : 'silent'}');
      final cameraReady = await _prepareCameraAudioForRecording(
        recordCameraAudio: recordCameraAudio,
      );
      if (!mounted || !_recordStartInFlight) {
        await _stopContentSpeechSessionIfOwnedByRecording();
        await _releaseCameraAudioAfterRecording();
        _syncContentControlsForActiveSession(false);
        return;
      }
      if (!cameraReady) {
        _updateContentCreatorState(() {
          _recordStartInFlight = false;
          _countdown = 0;
        });
        await _stopContentSpeechSessionIfOwnedByRecording();
        await _releaseCameraAudioAfterRecording();
        _syncContentControlsForActiveSession(false);
        _showSnack(
          recordCameraAudio
              ? 'Recording could not start with sound. Check microphone '
                  'permission or the camera audio device.'
              : 'Recording could not start because the camera is not ready.',
        );
        _logContentDebug('recording blocked camera audio ready=false '
            'audio=${recordCameraAudio ? 'camera' : 'silent'}');
        return;
      }
      for (int i = 3; i > 0; i--) {
        if (!mounted) return;
        if (!_recordStartInFlight) return;
        _updateContentCreatorState(() => _countdown = i);
        await _playRecordingCountdownTick();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      if (!_recordStartInFlight) return;
      _updateContentCreatorState(() => _countdown = 0);
      await _playRecordingStartCue();

      if (!mounted || !_recordStartInFlight) return;
      try {
        if (Platform.isMacOS) {
          final tempDir = await getTemporaryDirectory();
          await _macCameraController!.startVideoRecording(
            '${tempDir.path}/${_recordingBaseName()}.mov',
          );
        } else {
          await _cameraController!.startVideoRecording();
        }
      } catch (e, stack) {
        _updateContentCreatorState(() => _recordStartInFlight = false);
        await _stopContentSpeechSessionIfOwnedByRecording();
        await _releaseCameraAudioAfterRecording();
        _syncContentControlsForActiveSession(false);
        _showSnack('Recording could not start.');
        _logContentDebug('recording start failed error=$e');
        LightweightDiagnostics.instance.recordError(
          e,
          stack,
          source: 'contentCreator.recordingStart',
        );
        return;
      }
      _recordSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) _updateContentCreatorState(() => _recordSeconds = t.tick);
      });
      _updateContentCreatorState(() {
        _isRecording = true;
        _recordStartInFlight = false;
        _activeWordIndex = ref.read(teleprompterProvider).confirmedWordIndex;
      });
      _syncContentControlsForActiveSession(true);
      _logContentDebug('recording started word=$_activeWordIndex '
          'audio=${recordCameraAudio ? 'camera' : 'silent'}');
    }
  }

  Future<void> _toggleAudioOnlyRecording() async {
    if (_isRecording && _isAudioOnlyRecording) {
      String? savedPath;
      try {
        savedPath = await _wavAudioRecorder.stop();
      } catch (e, stack) {
        _showSnack('Audio recording could not be stopped cleanly.');
        _logContentDebug('wav recording stop failed $e');
        LightweightDiagnostics.instance.recordError(
          e,
          stack,
          source: 'contentCreator.wavRecordingStop',
        );
      }
      final recordedSeconds = _recordSeconds;
      if (!mounted) return;
      _recordTimer?.cancel();
      _updateContentCreatorState(() {
        _isRecording = false;
        _isAudioOnlyRecording = false;
        _recordStartInFlight = false;
        _recordSeconds = 0;
      });
      await _stopContentSpeechSessionIfOwnedByRecording();
      _syncContentControlsForActiveSession(false);
      await _backupRecordingIfEnabled(savedPath);
      if (savedPath != null) _showSnack('Audio recording saved: $savedPath');
      _logContentDebug('wav recording stopped seconds=$recordedSeconds');
      return;
    }

    if (Platform.isMacOS) {
      final micStatus = await MacOSPermissions.requestMicrophone();
      if (!mounted) return;
      if (!micStatus.isGranted) {
        _showSnack('Microphone permission is required for WAV recording.');
        if (micStatus.isBlocked) {
          await MacOSPermissions.openMicrophoneSettings();
        }
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
      if (!micStatus.isGranted) {
        _showSnack('Microphone permission is required for WAV recording.');
        return;
      }
    }
    if (!mounted) return;

    _updateContentCreatorState(() {
      _recordStartInFlight = true;
      _countdown = 3;
      _contentControlsVisible = true;
    });
    _commitContentVisibleReadingLine(reason: 'audio recording start');
    _hideContentControlsTimer?.cancel();
    final settings = ref.read(settingsProvider);
    await _startContentSpeechSessionForRecording(settings);
    if (!mounted || !_recordStartInFlight) {
      await _stopContentSpeechSessionIfOwnedByRecording();
      _syncContentControlsForActiveSession(false);
      return;
    }
    _logContentDebug('wav recording countdown started');

    for (int i = 3; i > 0; i--) {
      if (!mounted || !_recordStartInFlight) return;
      _updateContentCreatorState(() => _countdown = i);
      await _playRecordingCountdownTick();
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted || !_recordStartInFlight) return;
    _updateContentCreatorState(() => _countdown = 0);
    await _playRecordingStartCue();

    try {
      final directory = Directory(await _effectiveRecordingFolderPath());
      final savedPath = await _wavAudioRecorder.start(
        destinationDirectory: directory,
        createdAt: DateTime.now(),
      );
      if (!mounted) {
        await _wavAudioRecorder.cancel();
        await _stopContentSpeechSessionIfOwnedByRecording();
        return;
      }
      _recordSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) _updateContentCreatorState(() => _recordSeconds = t.tick);
      });
      _updateContentCreatorState(() {
        _isRecording = true;
        _isAudioOnlyRecording = true;
        _recordStartInFlight = false;
      });
      _syncContentControlsForActiveSession(true);
      _showSnack('Audio recording started: $savedPath');
      _logContentDebug('wav recording started path=$savedPath');
    } catch (e, stack) {
      _updateContentCreatorState(() {
        _isRecording = false;
        _isAudioOnlyRecording = false;
        _recordStartInFlight = false;
        _countdown = 0;
      });
      await _stopContentSpeechSessionIfOwnedByRecording();
      _syncContentControlsForActiveSession(false);
      _showSnack('Audio recording could not start. Check microphone access.');
      _logContentDebug('wav recording start failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.wavRecordingStart',
      );
    }
  }

  Future<String> _recordingSaveMessage(
    String savedPath, {
    required String format,
    required bool expectVideo,
    required bool expectAudio,
  }) async {
    const probeableFormats = {
      AppSettings.contentCreatorRecordingFormatMp4,
    };
    if (!probeableFormats.contains(format)) {
      return 'Recording saved: $savedPath';
    }
    try {
      final probe =
          await const RecordingMediaProbeService().inspect(File(savedPath));
      _logContentDebug(
        'recording media probe video=${probe.hasVideoTrack} '
        'audio=${probe.hasAudioTrack} bytes=${probe.bytesScanned}',
      );
      LightweightDiagnostics.instance.record(
        'contentCreator',
        'recording media probe',
        data: {
          'format': format,
          'expectedVideo': expectVideo,
          'expectedAudio': expectAudio,
          'hasVideoTrack': probe.hasVideoTrack,
          'hasAudioTrack': probe.hasAudioTrack,
          'bytesScanned': probe.bytesScanned,
        },
      );
      return const RecordingMediaProbePolicy()
          .assess(
            probe: probe,
            savedPath: savedPath,
            expectVideo: expectVideo,
            expectAudio: expectAudio,
          )
          .message;
    } catch (error, stack) {
      _logContentDebug('recording media probe failed $error');
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingMediaProbe',
      );
    }
    return 'Recording saved: $savedPath';
  }

  Future<String> _saveRecordingToChosenFolder(String sourcePath) async {
    final settings = ref.read(settingsProvider);
    final format = settings.contentCreatorRecordingFormat;
    final folder = await _effectiveRecordingFolderPath();
    final directory = Directory(folder);
    var lastLoggedProgress = -10;
    final result = await const RecordingExportService().export(
      sourceFile: File(sourcePath),
      destinationDirectory: directory,
      format: format,
      createdAt: DateTime.now(),
      onProgress: (progress) {
        final percent = (progress * 100).round();
        if (percent == 100 || percent >= lastLoggedProgress + 10) {
          lastLoggedProgress = percent;
          if (mounted) {
            _updateContentCreatorState(() => _recordExportProgress = progress);
          }
          _logContentDebug('recording export progress $percent%');
        }
      },
    );
    _logContentDebug(
      'recording saved path=${result.outputPath} '
      'bytes=${result.bytesWritten} sourceDeleted=${result.sourceDeleted}',
    );
    return result.outputPath;
  }

  Future<String> _effectiveRecordingFolderPath() async {
    final configured =
        ref.read(settingsProvider).contentCreatorRecordingFolder.trim();
    if (configured.isNotEmpty) return configured;
    return _defaultRecordingFolderPath();
  }

  Future<void> _backupRecordingIfEnabled(String? savedPath) async {
    if (savedPath == null || savedPath.trim().isEmpty) return;
    if (!ref.read(settingsProvider).recordingAutoBackup) return;
    final accounts = await CloudOAuthService().loadAccounts();
    if (accounts.isEmpty) {
      _logContentDebug('recording cloud backup skipped: no cloud account');
      return;
    }
    try {
      final sync = CloudAppFolderSyncService();
      var uploaded = 0;
      final failures = <String>[];
      for (final providerId in accounts.keys) {
        final result = await sync.uploadRecording(
          providerId: providerId,
          sourcePath: savedPath,
        );
        if (result.ok) {
          uploaded++;
        } else {
          failures.add(result.message);
        }
      }
      _logContentDebug(
        'recording cloud backup uploaded=$uploaded '
        'failed=${failures.length} path=$savedPath',
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'contentCreator.recordingCloudBackup',
        data: {'path': savedPath},
      );
      _logContentDebug('recording cloud backup failed $error');
    }
  }
}
