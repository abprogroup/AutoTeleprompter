part of 'content_creator_screen.dart';

extension _ContentCreatorCamera on _ContentCreatorScreenState {
  Future<void> _initializeCamera({
    CameraDescription? preferredCamera,
    bool enableAudio = false,
  }) async {
    if (Platform.isMacOS) {
      await _initializeMacCamera(
        preferredCamera: preferredCamera,
        enableAudio: enableAudio,
      );
      return;
    }

    final generation = ++_cameraInitGeneration;
    _logContentDebug('camera init start gen=$generation mode='
        '${_cameraSourceModeLabel(_cameraSourceMode)} preferred='
        '${preferredCamera?.name ?? 'auto'} audio='
        '${enableAudio ? 'camera' : 'silent'}');
    try {
      final previousController = _cameraController;
      _updateContentCreatorState(() {
        _cameraController = null;
        _macCameraController = null;
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
            _cameraError = 'No camera was found on this Mac.';
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
              ? 'Camera could not start. Check macOS camera and microphone permissions.'
              : 'Camera could not start. Check macOS camera permissions.';
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
    final defaultName =
        ref.read(settingsProvider).defaultCameraDeviceName.trim();
    final preferredName = preferredCamera?.name ??
        (_cameraWasChosenByUser ? _selectedCameraName : null) ??
        (defaultName.isEmpty ? null : defaultName);
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
        _ContentCameraSourceMode.native => _isNativeCamera(camera),
        _ContentCameraSourceMode.usb => _isExternalUsbCamera(camera),
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
    if (_isNativeCamera(camera)) score -= 320;
    if (name.contains('webcam') || name.contains('web camera')) score -= 220;
    if (_isUsbCameraName(name)) score -= 120;
    if (camera.lensDirection == CameraLensDirection.front) score -= 40;
    if (camera.lensDirection == CameraLensDirection.back) score += 40;
    return score;
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

  bool _isNativeCamera(CameraDescription camera) {
    final name = camera.name.toLowerCase();
    return ContentCameraDeviceClassifier.isNativeCandidate(
      name,
      isFrontFacing: camera.lensDirection == CameraLensDirection.front,
      isMacOS: Platform.isMacOS,
    );
  }

  bool _isExternalUsbCamera(CameraDescription camera) {
    final name = camera.name.toLowerCase();
    return !_isNativeCamera(camera) &&
        !_isVirtualCameraName(name) &&
        !_isIrOrDepthCameraName(name) &&
        _isUsbCameraName(name);
  }

  String _cameraSourceType(CameraDescription camera) {
    if (_isNativeCamera(camera)) return 'Native camera';
    if (_isExternalUsbCamera(camera)) return 'USB camera';
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
      _ContentCameraSourceMode.usb => 'USB cameras exposed by macOS.',
      _ContentCameraSourceMode.virtual =>
        'NDI, OBS, phone bridges, Lightform, or virtual cameras.',
      _ContentCameraSourceMode.all => 'Every camera device on this Mac.',
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
}
