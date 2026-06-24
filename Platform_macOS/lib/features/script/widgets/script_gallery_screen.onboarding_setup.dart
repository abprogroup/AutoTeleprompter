part of 'script_gallery_screen.dart';

extension _ScriptGalleryOnboardingSetupParts on _ScriptGalleryScreenState {
  // Retained for the next guided-setup route segment after the lobby/editor
  // walkthrough was split into a continuous cross-screen flow.
  // ignore: unused_element
  Widget _sttSetupPanel(AppSettings settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return _onboardingPanel(
      icon: Icons.tune_rounded,
      title: 'Speech control profile',
      action: TextButton.icon(
        onPressed: () => unawaited(_applyRecommendedSttProfile()),
        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
        label: const Text('Recommended'),
      ),
      child: Column(
        children: [
          _setupSwitch(
            title: 'Use custom speech thresholds',
            value: settings.sttManualProfileEnabled,
            onChanged: notifier.setSttManualProfileEnabled,
          ),
          _setupIntSlider(
            title: 'Long word length',
            subtitle:
                'What word length should count as a long word for speech control?',
            value: settings.sttManualBigWordMinLetters,
            min: 3,
            max: 10,
            onChanged: notifier.setSttManualBigWordMinLetters,
          ),
          _setupIntSlider(
            title: 'Short words before scrolling',
            subtitle:
                'How many recognized short words should AutoTeleprompter hear before it starts scrolling?',
            value: settings.sttManualStartAdvanceSmallWords,
            min: 2,
            max: 8,
            onChanged: notifier.setSttManualStartAdvanceSmallWords,
          ),
          _setupIntSlider(
            title: 'Long words before scrolling',
            subtitle:
                'How many recognized long words should be enough to start scrolling?',
            value: settings.sttManualStartAdvanceBigWords,
            min: 1,
            max: 8,
            onChanged: notifier.setSttManualStartAdvanceBigWords,
          ),
          _setupIntSlider(
            title: 'Missed short words before pause',
            subtitle:
                'If recognition drifts away, how many missed short words should it tolerate?',
            value: settings.sttManualSafetySmallWords,
            min: 1,
            max: 5,
            onChanged: notifier.setSttManualSafetySmallWords,
          ),
          _setupIntSlider(
            title: 'Missed long words before pause',
            subtitle:
                'How many missed long words should it tolerate before pausing?',
            value: settings.sttManualSafetyBigWords,
            min: 1,
            max: 5,
            onChanged: notifier.setSttManualSafetyBigWords,
          ),
          _setupSwitch(
            title: 'Jump to visible text',
            subtitle:
                'Let speech control jump forward when you skip to text already visible on screen.',
            value: settings.sttVisibleSkipEnabled,
            onChanged: notifier.setSttVisibleSkipEnabled,
          ),
          if (settings.sttVisibleSkipEnabled) ...[
            _setupIntSlider(
              title: 'Visible jump short-word match',
              subtitle: 'How many matching short words should confirm a jump?',
              value: settings.sttManualVisibleSkipSmallWords == 0
                  ? 4
                  : settings.sttManualVisibleSkipSmallWords,
              min: 2,
              max: 8,
              onChanged: notifier.setSttManualVisibleSkipSmallWords,
            ),
            _setupIntSlider(
              title: 'Visible jump long-word match',
              subtitle: 'How many matching long words should confirm a jump?',
              value: settings.sttManualVisibleSkipBigWords == 0
                  ? 3
                  : settings.sttManualVisibleSkipBigWords,
              min: 1,
              max: 8,
              onChanged: notifier.setSttManualVisibleSkipBigWords,
            ),
          ],
          _setupSwitch(
            title: 'Allow manual scrolling during STT',
            subtitle:
                'Keep trackpad or mouse scrolling available while speech control is active.',
            value: settings.allowScrollDuringActiveSession,
            onChanged: notifier.setAllowScrollDuringActiveSession,
          ),
        ],
      ),
    );
  }

  // Retained for the next guided-setup route segment after the lobby/editor
  // walkthrough was split into a continuous cross-screen flow.
  // ignore: unused_element
  Widget _contentCreatorSetupPanel(AppSettings settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return _onboardingPanel(
      icon: Icons.video_settings_outlined,
      title: 'Content Creator defaults',
      action: TextButton.icon(
        onPressed: () => unawaited(_applyRecommendedCreatorProfile()),
        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
        label: const Text('Recommended'),
      ),
      child: Column(
        children: [
          _setupChoice<String>(
            title: 'Camera source',
            value: settings.contentCreatorCameraSourceMode,
            choices: const {
              AppSettings.contentCreatorSourceNative: 'Native',
              AppSettings.contentCreatorSourceAll: 'All',
              AppSettings.contentCreatorSourceUsb: 'USB',
              AppSettings.contentCreatorSourceVirtual: 'Virtual',
            },
            onChanged: notifier.setContentCreatorCameraSourceMode,
          ),
          _setupChoice<String>(
            title: 'Layout',
            value: settings.contentCreatorLayoutPreset,
            choices: const {
              AppSettings.contentCreatorLayoutReading: 'Reading',
              AppSettings.contentCreatorLayoutBalanced: 'Balanced',
              AppSettings.contentCreatorLayoutCamera: 'Camera',
            },
            onChanged: notifier.setContentCreatorLayoutPreset,
          ),
          _setupChoice<String>(
            title: 'Feed mode',
            value: settings.contentCreatorFeedMode,
            choices: const {
              AppSettings.contentCreatorFeedBubble: 'Bubble',
              AppSettings.contentCreatorFeedFull: 'Full',
            },
            onChanged: notifier.setContentCreatorFeedMode,
          ),
          _setupChoice<String>(
            title: 'Bubble position',
            value: settings.contentCreatorBubblePosition,
            choices: const {
              AppSettings.contentCreatorBubbleBottomRight: 'Bottom right',
              AppSettings.contentCreatorBubbleBottomLeft: 'Bottom left',
              AppSettings.contentCreatorBubbleTopRight: 'Top right',
              AppSettings.contentCreatorBubbleTopLeft: 'Top left',
            },
            onChanged: notifier.setContentCreatorBubblePosition,
          ),
          _setupChoice<String>(
            title: 'Bubble shape',
            value: settings.contentCreatorBubbleShape,
            choices: const {
              AppSettings.contentCreatorBubbleShapeRounded: 'Rounded',
              AppSettings.contentCreatorBubbleShapeRectangle: 'Rectangle',
              AppSettings.contentCreatorBubbleShapeCircle: 'Circle',
            },
            onChanged: notifier.setContentCreatorBubbleShape,
          ),
          _setupDoubleSlider(
            title: 'Bubble size',
            value: settings.contentCreatorBubbleSize,
            min: 0.04,
            max: 0.60,
            label: '${(settings.contentCreatorBubbleSize * 100).round()}%',
            onChanged: notifier.setContentCreatorBubbleSize,
          ),
          _setupDoubleSlider(
            title: 'Bubble opacity',
            value: settings.contentCreatorBubbleOpacity,
            min: 0.25,
            max: 1.0,
            label: '${(settings.contentCreatorBubbleOpacity * 100).round()}%',
            onChanged: notifier.setContentCreatorBubbleOpacity,
          ),
          _setupDoubleSlider(
            title: 'Text scrim',
            value: settings.contentCreatorTextScrim,
            min: 0.0,
            max: 0.9,
            label: '${(settings.contentCreatorTextScrim * 100).round()}%',
            onChanged: notifier.setContentCreatorTextScrim,
          ),
          _setupDoubleSlider(
            title: 'Background blur',
            value: settings.contentCreatorFeedBlur,
            min: 0.0,
            max: 30.0,
            label: settings.contentCreatorFeedBlur.toStringAsFixed(0),
            onChanged: notifier.setContentCreatorFeedBlur,
          ),
          _setupChoice<String>(
            title: 'Recording format',
            value: settings.contentCreatorRecordingFormat,
            choices: const {
              AppSettings.contentCreatorRecordingFormatMp4: 'MP4',
              AppSettings.contentCreatorRecordingFormatWav: 'Audio',
            },
            onChanged: notifier.setContentCreatorRecordingFormat,
          ),
          _setupChoice<String>(
            title: 'Resolution',
            value: settings.videoResolution,
            choices: const {
              '480p': '480p',
              '720p': '720p',
              '1080p': '1080p',
            },
            onChanged: notifier.setVideoResolution,
          ),
          _setupSwitch(
            title: 'Record starts speech control',
            value: settings.contentCreatorRecordingControlsSpeech,
            onChanged: notifier.setContentCreatorRecordingControlsSpeech,
          ),
          _setupSwitch(
            title: 'Auto-backup recordings',
            value: settings.recordingAutoBackup,
            onChanged: notifier.setRecordingAutoBackup,
          ),
        ],
      ),
    );
  }

  Future<void> _applyRecommendedSttProfile() async {
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setSttManualProfileEnabled(true);
    await notifier.setSttManualBigWordMinLetters(5);
    await notifier.setSttManualStartAdvanceSmallWords(4);
    await notifier.setSttManualStartAdvanceBigWords(3);
    await notifier.setSttManualSafetySmallWords(2);
    await notifier.setSttManualSafetyBigWords(1);
    await notifier.setSttVisibleSkipEnabled(true);
    await notifier.setSttManualVisibleSkipSmallWords(4);
    await notifier.setSttManualVisibleSkipBigWords(3);
    await notifier.setAllowScrollDuringActiveSession(false);
  }

  Future<void> _applyRecommendedCreatorProfile() async {
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setContentCreatorCameraSourceMode(
      AppSettings.contentCreatorSourceNative,
    );
    await notifier.setContentCreatorLayoutPreset(
      AppSettings.contentCreatorLayoutReading,
    );
    await notifier.setContentCreatorFeedMode(
      AppSettings.contentCreatorFeedBubble,
    );
    await notifier.setContentCreatorBubblePosition(
      AppSettings.contentCreatorBubbleBottomRight,
    );
    await notifier.setContentCreatorBubbleShape(
      AppSettings.contentCreatorBubbleShapeRounded,
    );
    await notifier.setContentCreatorBubbleSize(0.24);
    await notifier.setContentCreatorBubbleOpacity(1.0);
    await notifier.setContentCreatorTextScrim(0.55);
    await notifier.setContentCreatorFeedBlur(14.0);
    await notifier.setVideoResolution('720p');
    await notifier.setContentCreatorRecordingFormat(
      AppSettings.contentCreatorRecordingFormatMp4,
    );
    await notifier.setContentCreatorRecordingControlsSpeech(true);
    await notifier.setRecordingAutoBackup(false);
  }

  Widget _onboardingPanel({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFFBF00), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _setupSwitch({
    required String title,
    String? subtitle,
    required bool value,
    required FutureOr<void> Function(bool) onChanged,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      activeColor: const Color(0xFFFFBF00),
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: Colors.white54)),
      onChanged: (next) => _runOnboardingWrite(() => onChanged(next)),
    );
  }

  Widget _setupIntSlider({
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required FutureOr<void> Function(int) onChanged,
  }) {
    return _setupDoubleSlider(
      title: title,
      subtitle: subtitle,
      value: value.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: max - min,
      label: value.toString(),
      onChanged: (next) => onChanged(next.round()),
    );
  }

  Widget _setupDoubleSlider({
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String label,
    required FutureOr<void> Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFFFBF00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: Colors.white54)),
          ],
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: const Color(0xFFFFBF00),
            inactiveColor: Colors.white12,
            onChanged: (next) => _runOnboardingWrite(() => onChanged(next)),
          ),
        ],
      ),
    );
  }

  Widget _setupChoice<T>({
    required String title,
    required T value,
    required Map<T, String> choices,
    required FutureOr<void> Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.entries.map((entry) {
              final selected = entry.key == value;
              return ChoiceChip(
                label: Text(entry.value),
                selected: selected,
                selectedColor: const Color(0xFFFFBF00),
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) =>
                    _runOnboardingWrite(() => onChanged(entry.key)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _runOnboardingWrite(FutureOr<void> Function() action) {
    final result = action();
    if (result is Future<void>) {
      unawaited(result);
    }
  }
}
