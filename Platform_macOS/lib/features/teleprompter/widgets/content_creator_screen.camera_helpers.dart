part of 'content_creator_screen.dart';

extension _ContentCreatorCameraHelpers on _ContentCreatorScreenState {
  Future<void> _initializeMacCamera({
    CameraDescription? preferredCamera,
    bool enableAudio = false,
  }) async {
    final generation = ++_cameraInitGeneration;
    _logContentDebug('mac camera init start gen=$generation mode='
        '${_cameraSourceModeLabel(_cameraSourceMode)} preferred='
        '${preferredCamera?.name ?? 'auto'} audio='
        '${enableAudio ? 'camera' : 'silent'}');
    try {
      final previousController = _macCameraController;
      _updateContentCreatorState(() {
        _cameraController = null;
        _macCameraController = null;
        _isInit = false;
        _cameraAudioEnabled = false;
        _isCameraInitializing = true;
        _cameraError = null;
      });
      await previousController?.dispose();

      final permission = await MacOSPermissions.requestCamera();
      if (!permission.isGranted) {
        if (mounted && generation == _cameraInitGeneration) {
          _updateContentCreatorState(() {
            _availableCameras = const [];
            _macCameraDeviceIdsByName = const {};
            _selectedCameraName = null;
            _cameraWasChosenByUser = false;
            _isInit = false;
            _cameraAudioEnabled = false;
            _isCameraInitializing = false;
            _cameraError = 'Camera permission is required. Open macOS '
                'System Settings and allow camera access.';
          });
        }
        if (permission.isBlocked) await MacOSPermissions.openCameraSettings();
        _logContentDebug('mac camera permission blocked gen=$generation '
            'status=${permission.value}');
        return;
      }

      final devices = await MacOSCameraController.availableCameras().timeout(
        const Duration(seconds: 8),
      );
      if (!mounted || generation != _cameraInitGeneration) return;
      final cameras = _cameraDescriptionsForMacDevices(devices);
      if (cameras.isEmpty) {
        _updateContentCreatorState(() {
          _availableCameras = const [];
          _macCameraDeviceIdsByName = const {};
          _selectedCameraName = null;
          _cameraWasChosenByUser = false;
          _isInit = false;
          _cameraAudioEnabled = false;
          _isCameraInitializing = false;
          _cameraError = 'No camera was found on this Mac.';
        });
        _logContentDebug('mac camera init no devices gen=$generation');
        return;
      }

      final selectedCamera = _resolveCamera(cameras, preferredCamera);
      final selectedDeviceId = _macCameraDeviceIdsByName[selectedCamera.name];
      if (selectedDeviceId == null) {
        throw StateError('No native id found for ${selectedCamera.name}');
      }
      _updateContentCreatorState(() {
        _availableCameras = cameras;
        _selectedCameraName = selectedCamera.name;
      });

      final settings = ref.read(settingsProvider);
      final nextController = MacOSCameraController(
        deviceId: selectedDeviceId,
        deviceName: selectedCamera.name,
        resolution: settings.videoResolution,
        enableAudio: enableAudio,
      );
      await nextController.initialize().timeout(const Duration(seconds: 10));
      if (!mounted || generation != _cameraInitGeneration) {
        await nextController.dispose();
        return;
      }
      _updateContentCreatorState(() {
        _macCameraController = nextController;
        _isInit = true;
        _cameraAudioEnabled = enableAudio;
        _isCameraInitializing = false;
        _cameraError = null;
      });
      _logContentDebug('mac camera init ok gen=$generation device='
          '${selectedCamera.name} resolution=${settings.videoResolution} '
          'audio=${enableAudio ? 'camera' : 'silent'}');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('macOS camera error: $e');
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
      _logContentDebug('mac camera init error gen=$generation error=$e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.macCameraInit',
      );
    }
  }

  List<CameraDescription> _cameraDescriptionsForMacDevices(
    List<MacOSCameraDevice> devices,
  ) {
    final counts = <String, int>{};
    final idsByName = <String, String>{};
    final descriptions = <CameraDescription>[];
    for (final device in devices) {
      final baseName =
          device.name.trim().isEmpty ? 'Camera' : device.name.trim();
      final count = counts[baseName] ?? 0;
      counts[baseName] = count + 1;
      final displayName = count == 0 ? baseName : '$baseName ${count + 1}';
      idsByName[displayName] = device.id;
      descriptions.add(
        CameraDescription(
          name: displayName,
          lensDirection: switch (device.position) {
            'front' => CameraLensDirection.front,
            'back' => CameraLensDirection.back,
            _ => CameraLensDirection.external,
          },
          sensorOrientation: 0,
        ),
      );
    }
    _macCameraDeviceIdsByName = idsByName;
    return descriptions;
  }

  bool _isActiveCameraInitialized() {
    return Platform.isMacOS
        ? _macCameraController?.isInitialized == true
        : _cameraController?.value.isInitialized == true;
  }

  Size? _activeCameraPreviewSize() {
    return Platform.isMacOS
        ? _macCameraController?.previewSize
        : _cameraController?.value.previewSize;
  }

  String _recordingBaseName() {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    return 'AutoTeleprompter_${date}_$time';
  }

  Future<String> _defaultRecordingFolderPath() async {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return '$home${Platform.pathSeparator}Movies'
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
      await Process.start('open', [directory.path]);
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
}
