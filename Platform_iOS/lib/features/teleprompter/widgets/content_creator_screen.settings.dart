part of 'content_creator_screen.dart';

extension _ContentCreatorSettingsUi on _ContentCreatorScreenState {
  Widget _buildCameraFallback() {
    if (_isCameraInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_outlined,
              color: Colors.white54, size: 34),
          const SizedBox(height: 10),
          Text(
            _cameraError ?? 'Camera is unavailable.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _initializeCamera,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry camera'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFBF00),
              side: const BorderSide(color: Color(0xFFFFBF00)),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatorSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Consumer(
        builder: (sheetContext, ref, _) {
          final settings = ref.watch(settingsProvider);
          final audioOnly = _contentAudioOnlyMode(settings);
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Creator',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: AppSettings.contentCreatorRecordingFormatMp4,
                        icon: Icon(Icons.videocam_outlined),
                        label: Text('Video'),
                      ),
                      ButtonSegment(
                        value: AppSettings.contentCreatorRecordingFormatAudio,
                        icon: Icon(Icons.mic_none_outlined),
                        label: Text('Audio'),
                      ),
                    ],
                    selected: {
                      audioOnly
                          ? AppSettings.contentCreatorRecordingFormatAudio
                          : AppSettings.contentCreatorRecordingFormatMp4,
                    },
                    onSelectionChanged: _isRecording || _recordStartInFlight
                        ? null
                        : (values) {
                            final format = values.first;
                            unawaited(ref
                                .read(settingsProvider.notifier)
                                .setContentCreatorRecordingFormat(format));
                            if (format ==
                                AppSettings
                                    .contentCreatorRecordingFormatAudio) {
                              _cameraInitGeneration++;
                              final controller = _cameraController;
                              _cameraController = null;
                              unawaited(controller?.dispose());
                              _setContentCreatorState(() => _isInit = true);
                            } else {
                              unawaited(_initializeCamera());
                            }
                          },
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile.adaptive(
                    value: settings.contentCreatorRecordingControlsSpeech,
                    onChanged: _isRecording || _recordStartInFlight
                        ? null
                        : (value) => unawaited(ref
                            .read(settingsProvider.notifier)
                            .setContentCreatorRecordingControlsSpeech(value)),
                    activeColor: const Color(0xFFFFBF00),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Start speech with recording',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'The record button starts and stops the reader STT session.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!audioOnly)
                    _CreatorFeedModeSelector(
                      value: settings.contentCreatorFeedMode,
                      enabled: !_isRecording && !_recordStartInFlight,
                      onChanged: (value) => unawaited(ref
                          .read(settingsProvider.notifier)
                          .setContentCreatorFeedMode(value)),
                    ),
                  _CreatorResolutionSelector(
                    value: settings.videoResolution,
                    enabled: !_isRecording && !_recordStartInFlight,
                    onChanged: (value) => unawaited(
                      ref.read(settingsProvider.notifier).setVideoResolution(
                            value,
                          ),
                    ),
                  ),
                  if (!audioOnly && _availableCameras.isNotEmpty)
                    _CameraSelector(
                      cameras: _availableCameras,
                      selectedIndex: _selectedCameraIndex,
                      enabled: !_isRecording && !_recordStartInFlight,
                      onSelected: (index) {
                        _setContentCreatorState(
                            () => _selectedCameraIndex = index);
                        unawaited(_initializeCamera());
                      },
                    ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const TeleprompterSettingsPanel(),
                      );
                    },
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Reader settings'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFBF00),
                      side: const BorderSide(color: Color(0xFFFFBF00)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreatorFeedModeSelector extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CreatorFeedModeSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Camera feed',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: AppSettings.contentCreatorFeedStrip,
              icon: Icon(Icons.view_stream_outlined),
              label: Text('Strip'),
            ),
            ButtonSegment(
              value: AppSettings.contentCreatorFeedBubble,
              icon: Icon(Icons.circle_outlined),
              label: Text('Bubble'),
            ),
            ButtonSegment(
              value: AppSettings.contentCreatorFeedFull,
              icon: Icon(Icons.fullscreen),
              label: Text('Full'),
            ),
          ],
          selected: {value},
          onSelectionChanged:
              enabled ? (values) => onChanged(values.first) : null,
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _CreatorResolutionSelector extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CreatorResolutionSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resolution',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '480p', label: Text('480')),
            ButtonSegment(value: '720p', label: Text('720')),
            ButtonSegment(value: '1080p', label: Text('1080')),
          ],
          selected: {value},
          onSelectionChanged:
              enabled ? (values) => onChanged(values.first) : null,
        ),
      ],
    );
  }
}

class _CameraSelector extends StatelessWidget {
  final List<CameraDescription> cameras;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelected;

  const _CameraSelector({
    required this.cameras,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Camera',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: selectedIndex.clamp(0, cameras.length - 1).toInt(),
          dropdownColor: const Color(0xFF202020),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: [
            for (var i = 0; i < cameras.length; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Text(
                  _cameraLabel(cameras[i], i),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
          onChanged: enabled
              ? (index) {
                  if (index != null) onSelected(index);
                }
              : null,
        ),
      ],
    );
  }

  static String _cameraLabel(CameraDescription camera, int index) {
    final direction = switch (camera.lensDirection) {
      CameraLensDirection.front => 'Front',
      CameraLensDirection.back => 'Back',
      CameraLensDirection.external => 'External',
    };
    return '$direction camera ${index + 1}';
  }
}
