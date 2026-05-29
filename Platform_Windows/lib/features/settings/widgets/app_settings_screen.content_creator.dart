part of 'app_settings_screen.dart';

extension _ContentCreatorSettingsTab on _AppSettingsScreenState {
  List<Widget> _contentCreatorTab(AppSettings settings) {
    return [
      const _SectionHeader(title: 'CAMERA DEFAULTS'),
      const SizedBox(height: 8),
      _SettingsControlTile(
        icon: Icons.video_camera_front_outlined,
        title: 'Default camera source',
        subtitle: _creatorSourceLabel(settings.contentCreatorCameraSourceMode),
        children: [
          _SettingsChipGroup<String>(
            selected: settings.contentCreatorCameraSourceMode,
            values: const [
              AppSettings.contentCreatorSourceNative,
              AppSettings.contentCreatorSourceUsb,
              AppSettings.contentCreatorSourceVirtual,
              AppSettings.contentCreatorSourceAll,
            ],
            labelFor: _creatorSourceLabel,
            onSelected: ref
                .read(settingsProvider.notifier)
                .setContentCreatorCameraSourceMode,
          ),
        ],
      ),
      const SizedBox(height: 16),
      _SettingsControlTile(
        icon: Icons.high_quality_outlined,
        title: 'Video quality',
        subtitle: settings.videoResolution,
        children: [
          _SettingsChipGroup<String>(
            selected: settings.videoResolution,
            values: const ['480p', '720p', '1080p'],
            labelFor: (value) => value,
            onSelected: ref.read(settingsProvider.notifier).setVideoResolution,
          ),
        ],
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'LAYOUT AND READABILITY'),
      const SizedBox(height: 8),
      _SettingsControlTile(
        icon: Icons.picture_in_picture_alt_outlined,
        title: 'Camera feed mode',
        subtitle: _creatorFeedModeLabel(settings.contentCreatorFeedMode),
        children: [
          _SettingsChipGroup<String>(
            selected: settings.contentCreatorFeedMode,
            values: const [
              AppSettings.contentCreatorFeedBubble,
              AppSettings.contentCreatorFeedFull,
            ],
            labelFor: _creatorFeedModeLabel,
            onSelected:
                ref.read(settingsProvider.notifier).setContentCreatorFeedMode,
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (settings.contentCreatorFeedMode ==
          AppSettings.contentCreatorFeedBubble) ...[
        _SettingsControlTile(
          icon: Icons.open_with_outlined,
          title: 'Bubble position',
          subtitle: _creatorBubblePositionLabel(
            settings.contentCreatorBubblePosition,
          ),
          children: [
            _SettingsChipGroup<String>(
              selected: settings.contentCreatorBubblePosition,
              values: const [
                AppSettings.contentCreatorBubbleBottomRight,
                AppSettings.contentCreatorBubbleBottomLeft,
                AppSettings.contentCreatorBubbleTopRight,
                AppSettings.contentCreatorBubbleTopLeft,
              ],
              labelFor: _creatorBubblePositionLabel,
              onSelected: ref
                  .read(settingsProvider.notifier)
                  .setContentCreatorBubblePosition,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSliderTile(
          icon: Icons.aspect_ratio_outlined,
          title: 'Bubble size',
          subtitle: 'Controls the camera bubble size in the prompter',
          value: settings.contentCreatorBubbleSize,
          displayValue: '${(settings.contentCreatorBubbleSize * 100).round()}%',
          min: 0.04,
          max: 0.60,
          divisions: 20,
          onChanged:
              ref.read(settingsProvider.notifier).setContentCreatorBubbleSize,
        ),
        const SizedBox(height: 16),
        _SettingsControlTile(
          icon: Icons.category_outlined,
          title: 'Bubble shape',
          subtitle:
              _creatorBubbleShapeLabel(settings.contentCreatorBubbleShape),
          children: [
            _SettingsChipGroup<String>(
              selected: settings.contentCreatorBubbleShape,
              values: const [
                AppSettings.contentCreatorBubbleShapeRectangle,
                AppSettings.contentCreatorBubbleShapeRounded,
                AppSettings.contentCreatorBubbleShapeCircle,
                AppSettings.contentCreatorBubbleShapeTriangle,
              ],
              labelFor: _creatorBubbleShapeLabel,
              onSelected: ref
                  .read(settingsProvider.notifier)
                  .setContentCreatorBubbleShape,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSliderTile(
          icon: Icons.opacity_outlined,
          title: 'Bubble opacity',
          subtitle: 'Fades the camera bubble so text remains visible nearby',
          value: settings.contentCreatorBubbleOpacity,
          displayValue:
              '${(settings.contentCreatorBubbleOpacity * 100).round()}%',
          min: 0.25,
          max: 1.0,
          divisions: 15,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorBubbleOpacity,
        ),
        const SizedBox(height: 16),
        if (settings.contentCreatorBubbleShape ==
            AppSettings.contentCreatorBubbleShapeRounded) ...[
          _SettingsSliderTile(
            icon: Icons.rounded_corner_outlined,
            title: 'Bubble roundness',
            subtitle: 'Rounds the rectangle without changing its shape',
            value: settings.contentCreatorBubbleRoundness,
            displayValue:
                '${(settings.contentCreatorBubbleRoundness * 100).round()}%',
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: ref
                .read(settingsProvider.notifier)
                .setContentCreatorBubbleRoundness,
          ),
          const SizedBox(height: 16),
        ],
        _SettingsSliderTile(
          icon: Icons.swap_horiz_outlined,
          title: 'Bubble horizontal offset',
          subtitle: 'Move the bubble left or right from its chosen corner',
          value: settings.contentCreatorBubbleOffsetX,
          displayValue:
              '${(settings.contentCreatorBubbleOffsetX * 100).round()}%',
          min: -0.25,
          max: 0.25,
          divisions: 20,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorBubbleOffsetX,
        ),
        const SizedBox(height: 16),
        _SettingsSliderTile(
          icon: Icons.swap_vert_outlined,
          title: 'Bubble vertical offset',
          subtitle: 'Move the bubble up or down from its chosen corner',
          value: settings.contentCreatorBubbleOffsetY,
          displayValue:
              '${(settings.contentCreatorBubbleOffsetY * 100).round()}%',
          min: -0.25,
          max: 0.25,
          divisions: 20,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorBubbleOffsetY,
        ),
        const SizedBox(height: 16),
      ] else ...[
        _SettingsSliderTile(
          icon: Icons.opacity_outlined,
          title: 'Camera visibility',
          subtitle: 'Controls how strongly the full feed appears',
          value: settings.contentCreatorCameraOpacity,
          displayValue:
              '${(settings.contentCreatorCameraOpacity * 100).round()}%',
          min: 0.2,
          max: 1.0,
          divisions: 16,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorCameraOpacity,
        ),
        const SizedBox(height: 16),
        _SettingsSliderTile(
          icon: Icons.vignette_outlined,
          title: 'Vignette',
          subtitle: 'Darkens the feed edges for readability',
          value: settings.contentCreatorVignetteIntensity,
          displayValue:
              '${(settings.contentCreatorVignetteIntensity * 100).round()}%',
          min: 0.0,
          max: 1.0,
          divisions: 20,
          onChanged: ref
              .read(settingsProvider.notifier)
              .setContentCreatorVignetteIntensity,
        ),
        const SizedBox(height: 16),
        _SettingsSliderTile(
          icon: Icons.blur_on_outlined,
          title: 'Background blur',
          subtitle: 'Blurs the fill layer behind the real camera feed',
          value: settings.contentCreatorFeedBlur,
          displayValue: settings.contentCreatorFeedBlur.toStringAsFixed(0),
          min: 0.0,
          max: 30.0,
          divisions: 15,
          onChanged:
              ref.read(settingsProvider.notifier).setContentCreatorFeedBlur,
        ),
        const SizedBox(height: 16),
        _SettingsSliderTile(
          icon: Icons.contrast_outlined,
          title: 'Text scrim',
          subtitle: 'Adds darkness behind the script text',
          value: settings.contentCreatorTextScrim,
          displayValue: '${(settings.contentCreatorTextScrim * 100).round()}%',
          min: 0.0,
          max: 0.9,
          divisions: 18,
          onChanged:
              ref.read(settingsProvider.notifier).setContentCreatorTextScrim,
        ),
        const SizedBox(height: 16),
        _SettingsControlTile(
          icon: Icons.space_dashboard_outlined,
          title: 'Layout preset',
          subtitle: _creatorLayoutLabel(settings.contentCreatorLayoutPreset),
          children: [
            _SettingsChipGroup<String>(
              selected: settings.contentCreatorLayoutPreset,
              values: const [
                AppSettings.contentCreatorLayoutReading,
                AppSettings.contentCreatorLayoutBalanced,
                AppSettings.contentCreatorLayoutCamera,
              ],
              labelFor: _creatorLayoutLabel,
              onSelected: ref
                  .read(settingsProvider.notifier)
                  .setContentCreatorLayoutPreset,
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      _SettingsTile(
        icon: Icons.display_settings_outlined,
        title: 'Prompter typography and colors',
        subtitle: 'Uses the same display controls as Present mode',
        onTap: _showPresenterSettingsPanel,
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'RECORDING'),
      const SizedBox(height: 8),
      _SettingsControlTile(
        icon: Icons.movie_filter_outlined,
        title: 'Recording output',
        subtitle: _creatorRecordingOutputLabel(settings),
        children: [
          _recordingOutputSection(
            title: 'MP4 video',
            options: const [
              MapEntry('video_sound_mp4', 'Video with sound'),
              MapEntry('video_silent_mp4', 'Video without sound'),
            ],
            settings: settings,
          ),
          const SizedBox(height: 10),
          const Text(
            'MP4 records directly through the camera system. Native WebM, '
            'MOV ProRes, and audio-only WAV recording are planned for v6 '
            'research so this beta stays light.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _SettingsControlTile(
        icon: Icons.folder_open_outlined,
        title: 'Recording folder',
        subtitle: settings.contentCreatorRecordingFolder.trim().isEmpty
            ? 'Videos/AutoTeleprompter'
            : settings.contentCreatorRecordingFolder,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _chooseCreatorRecordingFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose folder'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openCreatorRecordingFolder(settings),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open folder'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Exported recordings are normal video/audio files. They are saved '
            'outside encrypted script storage so you can share, move, or delete '
            'them from Windows.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
          ),
        ],
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'FUTURE CAMERA SUPPORT'),
      const SizedBox(height: 8),
      const _SettingsTile(
        icon: Icons.wifi_tethering_outlined,
        title: 'Wi-Fi / IP camera',
        subtitle: 'Planned for v6. v5.0.4 supports IP/phone feeds only when '
            'Windows exposes them as virtual camera devices.',
      ),
    ];
  }

  void _showPresenterSettingsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TeleprompterSettingsPanel(),
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
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option.value),
                selected: _creatorRecordingOutputKey(settings) == option.key,
                selectedColor: const Color(0xFFFFBF00),
                backgroundColor: const Color(0xFF111111),
                side: BorderSide(
                  color: _creatorRecordingOutputKey(settings) == option.key
                      ? const Color(0xFFFFBF00)
                      : Colors.white24,
                ),
                labelStyle: TextStyle(
                  color: _creatorRecordingOutputKey(settings) == option.key
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: _creatorRecordingOutputKey(settings) == option.key
                      ? FontWeight.bold
                      : FontWeight.w500,
                ),
                onSelected: (_) => unawaited(
                  _setCreatorRecordingOutput(option.key),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _creatorRecordingOutputKey(AppSettings settings) {
    final prefix = settings.contentCreatorRecordingAudioMode ==
            AppSettings.contentCreatorRecordingAudioSilent
        ? 'video_silent'
        : 'video_sound';
    return '${prefix}_${AppSettings.contentCreatorRecordingFormatMp4}';
  }

  String _creatorRecordingOutputLabel(AppSettings settings) {
    final key = _creatorRecordingOutputKey(settings);
    return switch (key) {
      'video_silent_mp4' => 'MP4 video without sound',
      _ => 'MP4 video with sound',
    };
  }

  Future<void> _setCreatorRecordingOutput(String key) async {
    final notifier = ref.read(settingsProvider.notifier);
    switch (key) {
      case 'video_silent_mp4':
        await notifier.setContentCreatorRecordingFormat(
          AppSettings.contentCreatorRecordingFormatMp4,
        );
        await notifier.setContentCreatorRecordingAudioMode(
          AppSettings.contentCreatorRecordingAudioSilent,
        );
        return;
      case 'video_sound_mp4':
      default:
        await notifier.setContentCreatorRecordingFormat(
          AppSettings.contentCreatorRecordingFormatMp4,
        );
        await notifier.setContentCreatorRecordingAudioMode(
          AppSettings.contentCreatorRecordingAudioCamera,
        );
        return;
    }
  }

  String _creatorSourceLabel(String source) {
    return switch (source) {
      AppSettings.contentCreatorSourceUsb => 'USB',
      AppSettings.contentCreatorSourceVirtual => 'Virtual / NDI / OBS',
      AppSettings.contentCreatorSourceAll => 'All',
      _ => 'Native',
    };
  }

  String _creatorLayoutLabel(String layout) {
    return switch (layout) {
      AppSettings.contentCreatorLayoutBalanced => 'Balanced',
      AppSettings.contentCreatorLayoutCamera => 'Camera',
      _ => 'Reading',
    };
  }

  String _creatorFeedModeLabel(String mode) {
    return switch (mode) {
      AppSettings.contentCreatorFeedFull => 'Full feed background',
      _ => 'Bubble feed',
    };
  }

  String _creatorBubblePositionLabel(String position) {
    return switch (position) {
      AppSettings.contentCreatorBubbleBottomLeft => 'Bottom left',
      AppSettings.contentCreatorBubbleTopRight => 'Top right',
      AppSettings.contentCreatorBubbleTopLeft => 'Top left',
      _ => 'Bottom right',
    };
  }

  String _creatorBubbleShapeLabel(String shape) {
    return switch (shape) {
      AppSettings.contentCreatorBubbleShapeRectangle => 'Rectangle',
      AppSettings.contentCreatorBubbleShapeCircle => 'Circle',
      AppSettings.contentCreatorBubbleShapeTriangle => 'Triangle',
      _ => 'Rounded',
    };
  }

  Future<void> _chooseCreatorRecordingFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose AutoTeleprompter recording folder',
      );
      if (path == null || path.trim().isEmpty) return;
      await ref
          .read(settingsProvider.notifier)
          .setContentCreatorRecordingFolder(path);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.contentCreatorRecordingFolderSelect',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Recording folder could not be selected.')),
      );
    }
  }

  Future<void> _openCreatorRecordingFolder(AppSettings settings) async {
    try {
      final path = settings.contentCreatorRecordingFolder.trim().isEmpty
          ? _defaultCreatorRecordingFolder()
          : settings.contentCreatorRecordingFolder;
      final directory = Directory(path);
      if (!await directory.exists()) await directory.create(recursive: true);
      await Process.start('explorer.exe', [directory.path]);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.contentCreatorRecordingFolderOpen',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording folder could not be opened.')),
      );
    }
  }

  String _defaultCreatorRecordingFolder() {
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.trim().isNotEmpty) {
      return '$profile${Platform.pathSeparator}Videos'
          '${Platform.pathSeparator}AutoTeleprompter';
    }
    return 'Videos${Platform.pathSeparator}AutoTeleprompter';
  }
}

class _SettingsSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final String displayValue;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SettingsSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.displayValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white54, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                displayValue,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
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
      ),
    );
  }
}
