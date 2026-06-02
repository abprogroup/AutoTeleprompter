part of 'content_creator_screen.dart';

extension _ContentCreatorCamera on _ContentCreatorScreenState {
  Future<void> _initializeCamera({
    CameraDescription? preferredCamera,
    bool enableAudio = false,
  }) async {
    final generation = ++_cameraInitGeneration;
    _logContentDebug('camera init start gen=$generation mode='
        '${_cameraSourceModeLabel(_cameraSourceMode)} preferred='
        '${preferredCamera?.name ?? 'auto'} audio='
        '${enableAudio ? 'camera' : 'silent'}');
    try {
      final previousController = _cameraController;
      _updateContentCreatorState(() {
        _cameraController = null;
        _isInit = false;
        _cameraAudioEnabled = false;
        _isCameraInitializing = true;
        _cameraError = null;
      });
      await previousController?.dispose();
      final discoveredCameras = await availableCameras().timeout(
        const Duration(seconds: 8),
      );
      if (!mounted || generation != _cameraInitGeneration) return;
      final cameras = _orderedCameras(discoveredCameras);
      if (cameras.isEmpty) {
        if (mounted) {
          _updateContentCreatorState(() {
            _availableCameras = const [];
            _selectedCameraName = null;
            _cameraWasChosenByUser = false;
            _isInit = false;
            _cameraAudioEnabled = false;
            _isCameraInitializing = false;
            _cameraError = 'No camera was found on this Windows device.';
          });
        }
        _logContentDebug('camera init no devices gen=$generation');
        return;
      }

      final selectedCamera = _resolveCamera(cameras, preferredCamera);
      if (mounted) {
        _updateContentCreatorState(() {
          _availableCameras = cameras;
          _selectedCameraName = selectedCamera.name;
        });
      }

      final settings = ref.read(settingsProvider);
      ResolutionPreset preset = ResolutionPreset.medium;
      if (settings.videoResolution.contains('1080')) {
        preset = ResolutionPreset.high;
      } else if (settings.videoResolution.contains('480')) {
        preset = ResolutionPreset.low;
      }

      final nextController = CameraController(
        selectedCamera,
        preset,
        enableAudio: enableAudio,
      );
      await nextController.initialize().timeout(
            const Duration(seconds: 10),
          );
      if (!mounted || generation != _cameraInitGeneration) {
        await nextController.dispose();
        return;
      }
      if (mounted) {
        _updateContentCreatorState(() {
          _cameraController = nextController;
          _isInit = true;
          _cameraAudioEnabled = enableAudio;
          _isCameraInitializing = false;
          _cameraError = null;
        });
      }
      _logContentDebug('camera init ok gen=$generation device='
          '${selectedCamera.name} resolution=${settings.videoResolution} '
          'audio=${enableAudio ? 'camera' : 'silent'}');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Camera error: $e');
      if (mounted && generation == _cameraInitGeneration) {
        _updateContentCreatorState(() {
          if (_availableCameras.isEmpty && _selectedCameraName == null) {
            _selectedCameraName = preferredCamera?.name;
          }
          _isInit = false;
          _cameraAudioEnabled = false;
          _isCameraInitializing = false;
          _cameraError = enableAudio
              ? 'Camera could not start. Check Windows camera and microphone permissions.'
              : 'Camera could not start. Check Windows camera permissions.';
        });
      }
      _logContentDebug('camera init error gen=$generation error=$e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.cameraInit',
      );
    }
  }

  CameraDescription _resolveCamera(
    List<CameraDescription> cameras,
    CameraDescription? preferredCamera,
  ) {
    final preferredName = preferredCamera?.name ??
        (_cameraWasChosenByUser ? _selectedCameraName : null);
    if (preferredName != null) {
      for (final camera in cameras) {
        if (camera.name == preferredName) return camera;
      }
    }
    final sourceCameras = _camerasForSourceMode(cameras, _cameraSourceMode);
    return sourceCameras.isNotEmpty ? sourceCameras.first : cameras.first;
  }

  List<CameraDescription> _camerasForSourceMode(
    List<CameraDescription> cameras,
    _ContentCameraSourceMode mode,
  ) {
    if (mode == _ContentCameraSourceMode.all) return cameras;
    return cameras.where((camera) {
      final name = camera.name.toLowerCase();
      return switch (mode) {
        _ContentCameraSourceMode.native => !_isVirtualCameraName(name) &&
            !_isIrOrDepthCameraName(name) &&
            _isIntegratedCameraName(name),
        _ContentCameraSourceMode.usb => !_isVirtualCameraName(name) &&
            !_isIrOrDepthCameraName(name) &&
            !_isIntegratedCameraName(name) &&
            _isUsbCameraName(name),
        _ContentCameraSourceMode.virtual => _isVirtualCameraName(name),
        _ContentCameraSourceMode.all => true,
      };
    }).toList();
  }

  List<CameraDescription> _orderedCameras(List<CameraDescription> cameras) {
    final ordered = List<CameraDescription>.of(cameras);
    ordered.sort((a, b) {
      final priority = _cameraPriority(a).compareTo(_cameraPriority(b));
      if (priority != 0) return priority;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return ordered;
  }

  int _cameraPriority(CameraDescription camera) {
    final name = camera.name.toLowerCase();
    var score = 0;
    if (_isVirtualCameraName(name)) score += 1000;
    if (_isIrOrDepthCameraName(name)) score += 320;
    if (_isIntegratedCameraName(name)) score -= 320;
    if (name.contains('webcam') || name.contains('web camera')) score -= 220;
    if (_isUsbCameraName(name)) score -= 120;
    if (camera.lensDirection == CameraLensDirection.front) score -= 40;
    if (camera.lensDirection == CameraLensDirection.back) score += 40;
    return score;
  }

  bool _isIntegratedCameraName(String name) {
    return ContentCameraDeviceClassifier.isIntegratedName(name);
  }

  bool _isIrOrDepthCameraName(String name) {
    return ContentCameraDeviceClassifier.isIrOrDepthName(name);
  }

  bool _isUsbCameraName(String name) {
    return ContentCameraDeviceClassifier.isUsbName(name);
  }

  bool _isVirtualCameraName(String name) {
    return ContentCameraDeviceClassifier.isVirtualName(name);
  }

  String _cameraSourceType(CameraDescription camera) {
    return ContentCameraDeviceClassifier.sourceTypeLabel(camera.name);
  }

  _ContentCameraSourceMode _cameraSourceModeFromSettings(String value) {
    return switch (value) {
      AppSettings.contentCreatorSourceUsb => _ContentCameraSourceMode.usb,
      AppSettings.contentCreatorSourceVirtual =>
        _ContentCameraSourceMode.virtual,
      AppSettings.contentCreatorSourceAll => _ContentCameraSourceMode.all,
      _ => _ContentCameraSourceMode.native,
    };
  }

  String _cameraSourceModeSettingsValue(_ContentCameraSourceMode mode) {
    return switch (mode) {
      _ContentCameraSourceMode.native => AppSettings.contentCreatorSourceNative,
      _ContentCameraSourceMode.usb => AppSettings.contentCreatorSourceUsb,
      _ContentCameraSourceMode.virtual =>
        AppSettings.contentCreatorSourceVirtual,
      _ContentCameraSourceMode.all => AppSettings.contentCreatorSourceAll,
    };
  }

  String _cameraSourceModeLabel(_ContentCameraSourceMode mode) {
    return switch (mode) {
      _ContentCameraSourceMode.native => 'Native',
      _ContentCameraSourceMode.usb => 'USB',
      _ContentCameraSourceMode.virtual => 'Virtual / NDI / OBS',
      _ContentCameraSourceMode.all => 'All',
    };
  }

  String _cameraSourceModeHelp(_ContentCameraSourceMode mode) {
    return switch (mode) {
      _ContentCameraSourceMode.native => 'Built-in laptop/webcam first.',
      _ContentCameraSourceMode.usb => 'USB cameras exposed by Windows.',
      _ContentCameraSourceMode.virtual =>
        'NDI, OBS, phone bridges, Lightform, or virtual cameras.',
      _ContentCameraSourceMode.all => 'Every Windows camera device.',
    };
  }

  Future<void> _setCameraSourceMode(_ContentCameraSourceMode mode) async {
    if (_isRecording || _recordStartInFlight) {
      _showSnack('Stop recording before changing camera source.');
      return;
    }
    final matching = _camerasForSourceMode(_availableCameras, mode);
    final preferred = matching.isEmpty ? null : matching.first;
    _updateContentCreatorState(() {
      _cameraSourceMode = mode;
      _selectedCameraName = preferred?.name;
      _cameraWasChosenByUser = preferred != null;
    });
    unawaited(
        ref.read(settingsProvider.notifier).setContentCreatorCameraSourceMode(
              _cameraSourceModeSettingsValue(mode),
            ));
    _logContentDebug('camera source mode selected '
        '${_cameraSourceModeLabel(mode)} preferred=${preferred?.name ?? 'none'}');
    await _initializeCamera(preferredCamera: preferred);
  }

  Future<void> _selectCamera(CameraDescription camera) async {
    if (_isRecording || _recordStartInFlight) {
      _showSnack('Stop recording before changing camera.');
      return;
    }
    _updateContentCreatorState(() {
      _selectedCameraName = camera.name;
      _cameraWasChosenByUser = true;
    });
    _logContentDebug('camera selected ${camera.name}');
    await _initializeCamera(preferredCamera: camera);
  }

  String _friendlyCameraName(CameraDescription camera, int index) {
    return _friendlyCameraNameFromRaw(camera.name,
        fallback: 'Camera ${index + 1}');
  }

  String _friendlyCameraNameFromRaw(String raw, {String fallback = 'Camera'}) {
    return ContentCameraDeviceClassifier.friendlyName(
      raw,
      fallback: fallback,
    );
  }

  String _cameraLabel(CameraDescription camera, int index) {
    final rawDirection = camera.lensDirection.name;
    final direction = rawDirection.isEmpty
        ? 'Camera'
        : '${rawDirection[0].toUpperCase()}${rawDirection.substring(1)}';
    return '${_friendlyCameraName(camera, index)} - '
        '${_cameraSourceType(camera)} - $direction';
  }

  CameraDescription? _selectedCameraDescription() {
    final selectedName = _selectedCameraName;
    if (selectedName == null) return null;
    for (final camera in _availableCameras) {
      if (camera.name == selectedName) return camera;
    }
    return null;
  }

  Future<bool> _prepareCameraAudioForRecording({
    required bool recordCameraAudio,
  }) async {
    if (!recordCameraAudio) {
      if (_cameraAudioEnabled) {
        await _releaseCameraAudioAfterRecording();
      }
      return _cameraController?.value.isInitialized == true;
    }

    if (_cameraAudioEnabled && _cameraController?.value.isInitialized == true) {
      return true;
    }

    await _initializeCamera(
      preferredCamera: _selectedCameraDescription(),
      enableAudio: true,
    );
    return mounted &&
        _recordStartInFlight &&
        _cameraController?.value.isInitialized == true &&
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

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showSnack(
        _cameraError ?? 'Camera is still preparing. Try again in a moment.',
      );
      return;
    }

    if (_isRecording) {
      final file = await _cameraController!.stopVideoRecording();
      final recordedSeconds = _recordSeconds;
      _recordTimer?.cancel();
      _updateContentCreatorState(() {
        _isRecording = false;
        _recordStartInFlight = false;
        _recordSeconds = 0;
      });
      await _stopContentSpeechSessionIfOwnedByRecording();
      await _releaseCameraAudioAfterRecording();
      _syncContentControlsForActiveSession(false);
      try {
        _updateContentCreatorState(() => _recordExportProgress = 0.0);
        final savedPath = await _saveRecordingToChosenFolder(file.path);
        final settings = ref.read(settingsProvider);
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
          'This build records MP4 video and WAV audio directly. Extra video '
          'file types are planned for future platform work.',
        );
        _logContentDebug('recording reset unsupported format='
            '${settings.contentCreatorRecordingFormat}');
        return;
      }
      final recordCameraAudio = settings.contentCreatorRecordingAudioMode ==
          AppSettings.contentCreatorRecordingAudioCamera;
      _updateContentCreatorState(() {
        _recordStartInFlight = true;
        _countdown = 3;
        _contentControlsVisible = true;
      });
      _hideContentControlsTimer?.cancel();
      _logContentDebug(
        'recording start keeps speech session separate '
        'audio=${recordCameraAudio ? 'camera' : 'silent'}',
      );
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
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      if (!_recordStartInFlight) return;
      _updateContentCreatorState(() => _countdown = 0);

      if (!mounted || !_recordStartInFlight) return;
      try {
        await _cameraController!.startVideoRecording();
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
      _recordTimer?.cancel();
      _updateContentCreatorState(() {
        _isRecording = false;
        _isAudioOnlyRecording = false;
        _recordStartInFlight = false;
        _recordSeconds = 0;
      });
      _syncContentControlsForActiveSession(false);
      if (savedPath != null) _showSnack('Audio recording saved: $savedPath');
      _logContentDebug('wav recording stopped seconds=$recordedSeconds');
      return;
    }

    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      _showSnack('Microphone permission is blocked. Open Windows Settings.');
      await openAppSettings();
      return;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    if (!micStatus.isGranted) {
      _showSnack('Microphone permission is required for WAV recording.');
      return;
    }

    _updateContentCreatorState(() {
      _recordStartInFlight = true;
      _countdown = 3;
      _contentControlsVisible = true;
    });
    _hideContentControlsTimer?.cancel();
    _logContentDebug('wav recording countdown started');

    for (int i = 3; i > 0; i--) {
      if (!mounted || !_recordStartInFlight) return;
      _updateContentCreatorState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted || !_recordStartInFlight) return;
    _updateContentCreatorState(() => _countdown = 0);

    try {
      final directory = Directory(await _effectiveRecordingFolderPath());
      final savedPath = await _wavAudioRecorder.start(
        destinationDirectory: directory,
        createdAt: DateTime.now(),
      );
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
    final folder = await _effectiveRecordingFolderPath();
    final directory = Directory(folder);
    var lastLoggedProgress = -10;
    final settings = ref.read(settingsProvider);
    final format = settings.contentCreatorRecordingFormat;
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

  Future<String> _defaultRecordingFolderPath() async {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return '$userProfile${Platform.pathSeparator}Videos'
          '${Platform.pathSeparator}AutoTeleprompter';
    }
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}AutoTeleprompter Recordings';
  }

  Future<void> _chooseRecordingFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose AutoTeleprompter recording folder',
      );
      if (path == null || path.trim().isEmpty) return;
      await ref
          .read(settingsProvider.notifier)
          .setContentCreatorRecordingFolder(
            path,
          );
      _logContentDebug('recording folder selected $path');
    } catch (e, stack) {
      _showSnack('Recording folder could not be selected.');
      _logContentDebug('recording folder select failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.recordingFolderSelect',
      );
    }
  }

  Future<void> _openRecordingFolder() async {
    try {
      final path = await _effectiveRecordingFolderPath();
      final directory = Directory(path);
      if (!await directory.exists()) await directory.create(recursive: true);
      await Process.start('explorer.exe', [directory.path]);
    } catch (e, stack) {
      _showSnack('Recording folder could not be opened.');
      _logContentDebug('recording folder open failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.recordingFolderOpen',
      );
    }
  }

  Future<void> _setVideoResolution(String resolution) async {
    if (_isRecording || _recordStartInFlight) {
      _showSnack('Stop recording before changing video resolution.');
      return;
    }
    await ref.read(settingsProvider.notifier).setVideoResolution(resolution);
    _logContentDebug('video resolution selected $resolution');
    await _initializeCamera();
  }

  Future<void> _initContentWebViewController() async {
    if (_contentWebviewController != null) return;
    try {
      final controller = WebviewController();
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _updateContentCreatorState(() {
        _contentWebviewController = controller;
      });
      final url = ref.read(teleprompterProvider).sttWebViewUrl;
      if (url != null && url != _loadedContentWebViewUrl) {
        await _loadContentSttWebView(url);
      }
    } catch (e, stack) {
      _logContentDebug('content webview init failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.webviewInit',
      );
    }
  }

  Future<void> _loadContentSttWebView(String url) async {
    WebView2RuntimeConfig.configureForLocalSttUrl(url);
    _loadedContentWebViewUrl = url;
    if (_contentWebviewController == null) {
      await _initContentWebViewController();
    }
    try {
      await _contentWebviewController?.loadUrl(url);
      _logContentDebug('content webview loaded $url');
    } catch (e, stack) {
      _logContentDebug('content webview load failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.webviewLoad',
      );
    }
  }
}
