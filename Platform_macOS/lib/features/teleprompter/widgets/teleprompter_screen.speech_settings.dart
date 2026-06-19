part of 'teleprompter_screen.dart';

class _WindowsSpeechSettingsSection extends ConsumerWidget {
  const _WindowsSpeechSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final manualSttProfile = settings.sttManualProfileEnabled;
    final visibleSkipControlsEnabled = !manualSttProfile;
    final hardSkipControlsEnabled =
        !manualSttProfile && settings.sttVisibleSkipEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Speech Input', style: _presenterSectionStyle),
        const SizedBox(height: 8),
        _DesktopMicSelector(
          selectedDeviceId: settings.sttInputDeviceId,
          selectedLabel: settings.sttInputDeviceLabel,
          devices: tState.audioInputDevices,
          accentColor: Color(settings.currentWordColor),
          onSelected: (deviceId, label) async {
            await notifier.setSttInputDevice(deviceId, label);
            ref
                .read(teleprompterProvider.notifier)
                .setSttInputDevice(deviceId, label);
          },
          onRefresh: () async {
            await ref
                .read(teleprompterProvider.notifier)
                .refreshAudioInputDevices();
          },
          onUseDefault: () async {
            await notifier.setSttInputDevice(
              '',
              'System default microphone',
            );
            ref
                .read(teleprompterProvider.notifier)
                .setSttInputDevice('', 'System default microphone');
          },
        ),
        const SizedBox(height: 16),
        _SwitchRow(
          icon: Icons.tune_outlined,
          title: 'Manual Profile',
          subtitle:
              'Advanced: set exact speech-to-text thresholds yourself. This turns off Bullet, Visible Skip, and Hard Skip buttons.',
          value: manualSttProfile,
          accentColor: Color(settings.currentWordColor),
          onChanged: notifier.setSttManualProfileEnabled,
        ),
        const SizedBox(height: 12),
        _SwitchRow(
          icon: Icons.visibility_outlined,
          title: 'Visible Skip',
          subtitle:
              'Allows deliberate jumps only to text currently visible on screen.',
          value: settings.sttVisibleSkipEnabled,
          accentColor: Color(settings.currentWordColor),
          enabled: visibleSkipControlsEnabled,
          onChanged: notifier.setSttVisibleSkipEnabled,
        ),
        const SizedBox(height: 12),
        _SwitchRow(
          icon: Icons.security_outlined,
          title: 'Hard Skip',
          subtitle:
              'Requires more words before visible jumps: 5 small words or 4 big words.',
          value: settings.sttHardVisibleSkipEnabled &&
              settings.sttVisibleSkipEnabled,
          accentColor: Color(settings.currentWordColor),
          enabled: hardSkipControlsEnabled,
          onChanged: notifier.setSttHardVisibleSkipEnabled,
        ),
        const SizedBox(height: 12),
        _SwitchRow(
          icon: Icons.subject_outlined,
          title: 'Bullet Mode',
          subtitle:
              'Strict header/bullet reading. Stops on off-script speech instead of guessing ahead.',
          value: settings.sttStrictBulletMode,
          accentColor: Color(settings.currentWordColor),
          enabled: visibleSkipControlsEnabled,
          onChanged: notifier.setSttStrictBulletMode,
        ),
        if (manualSttProfile) ...[
          const SizedBox(height: 12),
          _SttBigWordLengthSlider(
            value: settings.sttManualBigWordMinLetters,
            accentColor: Color(settings.currentWordColor),
            onChanged: notifier.setSttManualBigWordMinLetters,
            onReset: () => notifier.setSttManualBigWordMinLetters(5),
          ),
          const SizedBox(height: 12),
          _SttThresholdPairSliders(
            title: 'Words to start advancing',
            subtitle:
                'How much ordered text is needed before normal reading starts moving.',
            smallValue: settings.sttManualStartAdvanceSmallWords,
            bigValue: settings.sttManualStartAdvanceBigWords,
            smallMin: 2,
            smallMax: 8,
            bigMin: 1,
            bigMax: 8,
            allowOff: false,
            accentColor: Color(settings.currentWordColor),
            onSmallChanged: notifier.setSttManualStartAdvanceSmallWords,
            onBigChanged: notifier.setSttManualStartAdvanceBigWords,
            onReset: () {
              unawaited(notifier.setSttManualStartAdvanceSmallWords(4));
              unawaited(notifier.setSttManualStartAdvanceBigWords(3));
            },
          ),
          const SizedBox(height: 12),
          _SttThresholdPairSliders(
            title: 'Safety recovery',
            subtitle:
                'How much ordered evidence can recover after misrecognized words.',
            smallValue: settings.sttManualSafetySmallWords,
            bigValue: settings.sttManualSafetyBigWords,
            smallMin: 1,
            smallMax: 5,
            bigMin: 1,
            bigMax: 5,
            allowOff: false,
            accentColor: Color(settings.currentWordColor),
            onSmallChanged: notifier.setSttManualSafetySmallWords,
            onBigChanged: notifier.setSttManualSafetyBigWords,
            onReset: () {
              unawaited(notifier.setSttManualSafetySmallWords(2));
              unawaited(notifier.setSttManualSafetyBigWords(1));
            },
          ),
          const SizedBox(height: 12),
          _SttThresholdPairSliders(
            title: 'Visible-area skip',
            subtitle:
                'Off disables jumping. Higher values make visible jumps stricter.',
            smallValue: settings.sttManualVisibleSkipSmallWords,
            bigValue: settings.sttManualVisibleSkipBigWords,
            smallMin: 2,
            smallMax: 8,
            bigMin: 1,
            bigMax: 8,
            allowOff: true,
            accentColor: Color(settings.currentWordColor),
            onSmallChanged: notifier.setSttManualVisibleSkipSmallWords,
            onBigChanged: notifier.setSttManualVisibleSkipBigWords,
            onReset: () {
              unawaited(notifier.setSttManualVisibleSkipSmallWords(0));
              unawaited(notifier.setSttManualVisibleSkipBigWords(0));
            },
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
