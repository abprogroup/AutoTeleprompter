part of 'content_creator_screen.dart';

extension _ContentCreatorSettingsUi on _ContentCreatorScreenState {
  /// Feed-appearance sliders shown contextually for the active feed mode
  /// (Mac parity: bubble size/opacity/roundness, camera opacity, blur, scrim,
  /// vignette).
  List<Widget> _creatorFeedTuningSliders(
    WidgetRef ref,
    AppSettings settings, {
    required bool enabled,
  }) {
    final notifier = ref.read(settingsProvider.notifier);
    final mode = settings.contentCreatorFeedMode;
    final sliders = <Widget>[];

    if (mode == AppSettings.contentCreatorFeedBubble) {
      sliders.addAll([
        _CreatorSlider(
          label: 'Bubble size',
          value: settings.contentCreatorBubbleSize,
          min: 0.04,
          max: 0.60,
          enabled: enabled,
          onChanged: notifier.setContentCreatorBubbleSize,
        ),
        _CreatorSlider(
          label: 'Bubble opacity',
          value: settings.contentCreatorBubbleOpacity,
          min: 0.25,
          max: 1.0,
          enabled: enabled,
          onChanged: notifier.setContentCreatorBubbleOpacity,
        ),
        _CreatorSlider(
          label: 'Bubble roundness',
          value: settings.contentCreatorBubbleRoundness,
          min: 0.0,
          max: 1.0,
          enabled: enabled,
          onChanged: notifier.setContentCreatorBubbleRoundness,
        ),
      ]);
    } else if (mode == AppSettings.contentCreatorFeedFull) {
      sliders.addAll([
        _CreatorSlider(
          label: 'Camera opacity',
          value: settings.contentCreatorCameraOpacity,
          min: 0.2,
          max: 1.0,
          enabled: enabled,
          onChanged: notifier.setContentCreatorCameraOpacity,
        ),
        _CreatorSlider(
          label: 'Feed blur',
          value: settings.contentCreatorFeedBlur,
          min: 0.0,
          max: 30.0,
          enabled: enabled,
          onChanged: notifier.setContentCreatorFeedBlur,
        ),
        _CreatorSlider(
          label: 'Text scrim',
          value: settings.contentCreatorTextScrim,
          min: 0.0,
          max: 0.9,
          enabled: enabled,
          onChanged: notifier.setContentCreatorTextScrim,
        ),
      ]);
    } else {
      // strip
      sliders.addAll([
        _CreatorSlider(
          label: 'Vignette',
          value: settings.contentCreatorVignetteIntensity,
          min: 0.0,
          max: 1.0,
          enabled: enabled,
          onChanged: notifier.setContentCreatorVignetteIntensity,
        ),
        _CreatorSlider(
          label: 'Feed blur',
          value: settings.contentCreatorFeedBlur,
          min: 0.0,
          max: 30.0,
          enabled: enabled,
          onChanged: notifier.setContentCreatorFeedBlur,
        ),
      ]);
    }
    return sliders;
  }

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
                  if (!audioOnly &&
                      settings.contentCreatorFeedMode ==
                          AppSettings.contentCreatorFeedBubble)
                    _CreatorBubbleShapeSelector(
                      value: settings.contentCreatorBubbleShape,
                      enabled: !_isRecording && !_recordStartInFlight,
                      onChanged: (value) => unawaited(ref
                          .read(settingsProvider.notifier)
                          .setContentCreatorBubbleShape(value)),
                    ),
                  if (!audioOnly)
                    ..._creatorFeedTuningSliders(
                      ref,
                      settings,
                      enabled: !_isRecording && !_recordStartInFlight,
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

class _CreatorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _CreatorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pct = ((value - min) / (max - min) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$pct%',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            activeColor: const Color(0xFFFFBF00),
            inactiveColor: Colors.white24,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _CreatorBubbleShapeSelector extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CreatorBubbleShapeSelector({
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
          'Bubble shape',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Drag the bubble on screen to reposition it.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: AppSettings.contentCreatorBubbleRounded,
              icon: Icon(Icons.crop_square_rounded),
              label: Text('Rounded'),
            ),
            ButtonSegment(
              value: AppSettings.contentCreatorBubbleRectangle,
              icon: Icon(Icons.crop_din),
              label: Text('Square'),
            ),
            ButtonSegment(
              value: AppSettings.contentCreatorBubbleCircle,
              icon: Icon(Icons.circle_outlined),
              label: Text('Circle'),
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
