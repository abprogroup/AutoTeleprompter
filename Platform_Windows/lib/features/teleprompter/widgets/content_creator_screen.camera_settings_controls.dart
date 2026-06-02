part of 'content_creator_screen.dart';

extension _ContentCreatorCameraSettingsControls on _ContentCreatorScreenState {
  Widget _buildContentFeedModeSelector(AppSettings settings) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Bubble feed'),
          selected: settings.contentCreatorFeedMode ==
              AppSettings.contentCreatorFeedBubble,
          onSelected: (_) => ref
              .read(settingsProvider.notifier)
              .setContentCreatorFeedMode(AppSettings.contentCreatorFeedBubble),
          selectedColor: const Color(0xFFFFBF00),
          backgroundColor: const Color(0xFF1E1E1E),
          labelStyle: TextStyle(
            color: settings.contentCreatorFeedMode ==
                    AppSettings.contentCreatorFeedBubble
                ? Colors.black
                : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        ChoiceChip(
          label: const Text('Full feed background'),
          selected: settings.contentCreatorFeedMode ==
              AppSettings.contentCreatorFeedFull,
          onSelected: (_) => ref
              .read(settingsProvider.notifier)
              .setContentCreatorFeedMode(AppSettings.contentCreatorFeedFull),
          selectedColor: const Color(0xFFFFBF00),
          backgroundColor: const Color(0xFF1E1E1E),
          labelStyle: TextStyle(
            color: settings.contentCreatorFeedMode ==
                    AppSettings.contentCreatorFeedFull
                ? Colors.black
                : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingOutputSelector(AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _recordingOutputSection(
          title: 'Recording type',
          options: const [
            MapEntry('video_sound_mp4', 'Video with Sound (MP4)'),
            MapEntry('audio_only_wav', 'Audio Only (WAV)'),
          ],
          settings: settings,
        ),
        const SizedBox(height: 8),
        const Text(
          'MP4 video and WAV audio are recorded directly. WebM and MOV ProRes '
          'need native platform recording support before they are enabled.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
        ),
      ],
    );
  }

  Widget _recordingOutputSection({
    required String title,
    required List<MapEntry<String, String>> options,
    required AppSettings settings,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option.value),
                selected: _recordingOutputKey(settings) == option.key,
                selectedColor: const Color(0xFFFFBF00),
                backgroundColor: const Color(0xFF1E1E1E),
                labelStyle: TextStyle(
                  color: _recordingOutputKey(settings) == option.key
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: _isRecording || _recordStartInFlight
                    ? null
                    : (_) => unawaited(_setRecordingOutput(option.key)),
              ),
          ],
        ),
      ],
    );
  }

  String _recordingOutputKey(AppSettings settings) {
    if (settings.contentCreatorRecordingFormat ==
        AppSettings.contentCreatorRecordingFormatWav) {
      return 'audio_only_wav';
    }
    return 'video_sound_${AppSettings.contentCreatorRecordingFormatMp4}';
  }

  Future<void> _setRecordingOutput(String key) async {
    if (_isRecording || _recordStartInFlight) {
      _showSnack('Stop recording before changing output type.');
      return;
    }
    final notifier = ref.read(settingsProvider.notifier);
    switch (key) {
      case 'audio_only_wav':
        await notifier.setContentCreatorRecordingFormat(
          AppSettings.contentCreatorRecordingFormatWav,
        );
        await notifier.setContentCreatorRecordingAudioMode(
          AppSettings.contentCreatorRecordingAudioCamera,
        );
        break;
      case 'video_sound_mp4':
      default:
        await notifier.setContentCreatorRecordingFormat(
          AppSettings.contentCreatorRecordingFormatMp4,
        );
        await notifier.setContentCreatorRecordingAudioMode(
          AppSettings.contentCreatorRecordingAudioCamera,
        );
        break;
    }
    _logContentDebug('recording output selected $key');
    if (key == 'audio_only_wav') {
      final previousController = _cameraController;
      _updateContentCreatorState(() {
        _cameraController = null;
        _isInit = false;
        _cameraAudioEnabled = false;
        _isCameraInitializing = false;
        _cameraError = null;
        _contentFrameConfirmed = true;
      });
      await previousController?.dispose();
    } else {
      await _initializeCamera();
    }
  }

  Widget _buildContentFeedControls(AppSettings settings) {
    if (settings.contentCreatorFeedMode == AppSettings.contentCreatorFeedFull) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _contentSlider(
            title: 'Camera visibility',
            value: settings.contentCreatorCameraOpacity,
            display: '${(settings.contentCreatorCameraOpacity * 100).round()}%',
            min: 0.2,
            max: 1.0,
            divisions: 16,
            onChanged: ref
                .read(settingsProvider.notifier)
                .setContentCreatorCameraOpacity,
          ),
          _contentSlider(
            title: 'Vignette',
            value: settings.contentCreatorVignetteIntensity,
            display:
                '${(settings.contentCreatorVignetteIntensity * 100).round()}%',
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: ref
                .read(settingsProvider.notifier)
                .setContentCreatorVignetteIntensity,
          ),
          _contentSlider(
            title: 'Background blur',
            value: settings.contentCreatorFeedBlur,
            display: settings.contentCreatorFeedBlur.toStringAsFixed(0),
            min: 0.0,
            max: 30.0,
            divisions: 15,
            onChanged:
                ref.read(settingsProvider.notifier).setContentCreatorFeedBlur,
          ),
          _contentSlider(
            title: 'Text scrim',
            value: settings.contentCreatorTextScrim,
            display: '${(settings.contentCreatorTextScrim * 100).round()}%',
            min: 0.0,
            max: 0.9,
            divisions: 18,
            onChanged:
                ref.read(settingsProvider.notifier).setContentCreatorTextScrim,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Bubble position',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildBubblePositionSelector(settings),
        const SizedBox(height: 10),
        _contentSlider(
          title: 'Bubble size',
          value: settings.contentCreatorBubbleSize,
          display: '${(settings.contentCreatorBubbleSize * 100).round()}%',
          min: 0.04,
          max: 0.60,
          divisions: 28,
          onChanged:
              ref.read(settingsProvider.notifier).setContentCreatorBubbleSize,
        ),
        const SizedBox(height: 2),
        const Text(
          'Bubble shape',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildBubbleShapeSelector(settings),
        const SizedBox(height: 10),
        _contentSlider(
          title: 'Bubble opacity',
          value: settings.contentCreatorBubbleOpacity,
          display: '${(settings.contentCreatorBubbleOpacity * 100).round()}%',
          min: 0.25,
          max: 1.0,
          divisions: 15,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorBubbleOpacity,
        ),
        if (settings.contentCreatorBubbleShape ==
            AppSettings.contentCreatorBubbleShapeRounded)
          _contentSlider(
            title: 'Bubble roundness',
            value: settings.contentCreatorBubbleRoundness,
            display:
                '${(settings.contentCreatorBubbleRoundness * 100).round()}%',
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: ref
                .read(settingsProvider.notifier)
                .setContentCreatorBubbleRoundness,
          ),
        _contentSlider(
          title: 'Horizontal offset',
          value: settings.contentCreatorBubbleOffsetX,
          display: '${(settings.contentCreatorBubbleOffsetX * 100).round()}%',
          min: -0.25,
          max: 0.25,
          divisions: 20,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorBubbleOffsetX,
        ),
        _contentSlider(
          title: 'Vertical offset',
          value: settings.contentCreatorBubbleOffsetY,
          display: '${(settings.contentCreatorBubbleOffsetY * 100).round()}%',
          min: -0.25,
          max: 0.25,
          divisions: 20,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorBubbleOffsetY,
        ),
      ],
    );
  }

  Widget _buildBubblePositionSelector(AppSettings settings) {
    const positions = [
      AppSettings.contentCreatorBubbleBottomRight,
      AppSettings.contentCreatorBubbleBottomLeft,
      AppSettings.contentCreatorBubbleTopRight,
      AppSettings.contentCreatorBubbleTopLeft,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final position in positions)
          ChoiceChip(
            label: Text(_bubblePositionLabel(position)),
            selected: settings.contentCreatorBubblePosition == position,
            selectedColor: const Color(0xFFFFBF00),
            backgroundColor: const Color(0xFF1E1E1E),
            labelStyle: TextStyle(
              color: settings.contentCreatorBubblePosition == position
                  ? Colors.black
                  : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => ref
                .read(settingsProvider.notifier)
                .setContentCreatorBubblePosition(position),
          ),
      ],
    );
  }

  Widget _buildBubbleShapeSelector(AppSettings settings) {
    const shapes = [
      AppSettings.contentCreatorBubbleShapeRectangle,
      AppSettings.contentCreatorBubbleShapeRounded,
      AppSettings.contentCreatorBubbleShapeCircle,
      AppSettings.contentCreatorBubbleShapeTriangle,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final shape in shapes)
          ChoiceChip(
            label: Text(_bubbleShapeLabel(shape)),
            selected: settings.contentCreatorBubbleShape == shape,
            selectedColor: const Color(0xFFFFBF00),
            backgroundColor: const Color(0xFF1E1E1E),
            labelStyle: TextStyle(
              color: settings.contentCreatorBubbleShape == shape
                  ? Colors.black
                  : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => ref
                .read(settingsProvider.notifier)
                .setContentCreatorBubbleShape(shape),
          ),
      ],
    );
  }

  String _bubbleShapeLabel(String shape) {
    return switch (shape) {
      AppSettings.contentCreatorBubbleShapeRectangle => 'Rectangle',
      AppSettings.contentCreatorBubbleShapeCircle => 'Circle',
      AppSettings.contentCreatorBubbleShapeTriangle => 'Triangle',
      _ => 'Rounded',
    };
  }

  Widget _buildRecordingFolderControls(AppSettings settings) {
    final label = settings.contentCreatorRecordingFolder.trim().isEmpty
        ? 'Videos/AutoTeleprompter'
        : settings.contentCreatorRecordingFolder;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: _chooseRecordingFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Choose folder'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFBF00),
                ),
              ),
              TextButton.icon(
                onPressed: _openRecordingFolder,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open folder'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFBF00),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contentSlider({
    required String title,
    required double value,
    required String display,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(color: Colors.white70)),
            const Spacer(),
            Text(display, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: const Color(0xFFFFBF00),
          inactiveColor: Colors.white24,
          onChanged: onChanged,
        ),
      ],
    );
  }

  String _bubblePositionLabel(String position) {
    return switch (position) {
      AppSettings.contentCreatorBubbleBottomLeft => 'Bottom left',
      AppSettings.contentCreatorBubbleTopRight => 'Top right',
      AppSettings.contentCreatorBubbleTopLeft => 'Top left',
      _ => 'Bottom right',
    };
  }

  Widget _buildWifiIpFutureNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_tethering_outlined,
              color: Color(0xFFFFBF00), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Wi-Fi / IP cameras work when Windows exposes them as camera '
              'devices. Phone, NDI, OBS, Lightform, and bridge cameras use '
              'the same Windows camera-device path.',
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCreatorLayoutSelector(AppSettings settings) {
    const presets = [
      AppSettings.contentCreatorLayoutReading,
      AppSettings.contentCreatorLayoutBalanced,
      AppSettings.contentCreatorLayoutCamera,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in presets)
          ChoiceChip(
            label: Text(_contentCreatorLayoutLabel(preset)),
            selected: settings.contentCreatorLayoutPreset == preset,
            onSelected: (_) {
              ref
                  .read(settingsProvider.notifier)
                  .setContentCreatorLayoutPreset(preset);
              _logContentDebug('layout preset selected $preset');
            },
            selectedColor: const Color(0xFFFFBF00),
            backgroundColor: const Color(0xFF1E1E1E),
            labelStyle: TextStyle(
              color: settings.contentCreatorLayoutPreset == preset
                  ? Colors.black
                  : Colors.white70,
              fontWeight: settings.contentCreatorLayoutPreset == preset
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
      ],
    );
  }

  String _contentCreatorLayoutLabel(String preset) {
    return switch (preset) {
      AppSettings.contentCreatorLayoutBalanced => 'Balanced',
      AppSettings.contentCreatorLayoutCamera => 'Camera',
      _ => 'Reading',
    };
  }
}
