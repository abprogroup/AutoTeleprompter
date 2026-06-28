part of 'teleprompter_screen.dart';

class _SpeechProfileSettingsSection extends ConsumerWidget {
  const _SpeechProfileSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final accent = Color(settings.currentWordColor);
    final manualProfile = settings.sttManualProfileEnabled;
    final visibleControlsEnabled = !manualProfile;
    final hardSkipEnabled =
        visibleControlsEnabled && settings.sttVisibleSkipEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Speech Input',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _IosMicSelector(
          selectedDeviceId: settings.sttInputDeviceId,
          selectedLabel: settings.sttInputDeviceLabel,
          devices: tState.audioInputDevices,
          accentColor: accent,
          onRefresh: () => ref
              .read(teleprompterProvider.notifier)
              .refreshAudioInputDevices(),
          onSelected: (deviceId, label) async {
            await ref
                .read(teleprompterProvider.notifier)
                .setSttInputDevice(deviceId, label);
            await notifier.setSttInputDevice(deviceId, label);
          },
        ),
        const SizedBox(height: 14),
        _SpeechSwitchRow(
          icon: Icons.tune_outlined,
          title: 'Manual Profile',
          subtitle: 'Use exact STT thresholds instead of preset modes.',
          value: manualProfile,
          accentColor: accent,
          onChanged: notifier.setSttManualProfileEnabled,
        ),
        const SizedBox(height: 10),
        _SpeechSwitchRow(
          icon: Icons.visibility_outlined,
          title: 'Visible Skip',
          subtitle: 'Allow deliberate jumps only to words currently visible.',
          value: settings.sttVisibleSkipEnabled,
          accentColor: accent,
          enabled: visibleControlsEnabled,
          onChanged: notifier.setSttVisibleSkipEnabled,
        ),
        const SizedBox(height: 10),
        _SpeechSwitchRow(
          icon: Icons.security_outlined,
          title: 'Hard Skip',
          subtitle: 'Require stronger evidence before visible jumps.',
          value: settings.sttHardVisibleSkipEnabled &&
              settings.sttVisibleSkipEnabled,
          accentColor: accent,
          enabled: hardSkipEnabled,
          onChanged: notifier.setSttHardVisibleSkipEnabled,
        ),
        const SizedBox(height: 10),
        _SpeechSwitchRow(
          icon: Icons.subject_outlined,
          title: 'Bullet Mode',
          subtitle: 'Strict bullet/header reading with less guessing.',
          value: settings.sttStrictBulletMode,
          accentColor: accent,
          enabled: visibleControlsEnabled,
          onChanged: notifier.setSttStrictBulletMode,
        ),
        const SizedBox(height: 10),
        _SpeechSwitchRow(
          icon: Icons.graphic_eq_rounded,
          title: 'Listening Meter',
          subtitle: 'Show the microphone level bar while listening.',
          value: settings.showSoundLevelMeter,
          accentColor: accent,
          onChanged: notifier.setShowSoundLevelMeter,
        ),
        const SizedBox(height: 10),
        _SpeechSwitchRow(
          icon: Icons.pan_tool_alt_outlined,
          title: 'Manual Scroll While Listening',
          subtitle: 'Releasing a manual scroll relocks to the reading line.',
          value: settings.allowScrollDuringActiveSession,
          accentColor: accent,
          onChanged: notifier.setAllowScrollDuringActiveSession,
        ),
        if (manualProfile) ...[
          const SizedBox(height: 12),
          _SpeechStepperCard(
            title: 'Big word length',
            subtitle: 'Words at this length count as big words.',
            value: settings.sttManualBigWordMinLetters,
            min: 3,
            max: 10,
            accentColor: accent,
            onChanged: notifier.setSttManualBigWordMinLetters,
            onReset: () => notifier.setSttManualBigWordMinLetters(5),
          ),
          const SizedBox(height: 10),
          _SpeechThresholdCard(
            title: 'Start advancing',
            subtitle: 'Evidence needed before normal reading begins moving.',
            smallValue: settings.sttManualStartAdvanceSmallWords,
            bigValue: settings.sttManualStartAdvanceBigWords,
            smallMin: 2,
            smallMax: 8,
            bigMin: 1,
            bigMax: 8,
            accentColor: accent,
            onSmallChanged: notifier.setSttManualStartAdvanceSmallWords,
            onBigChanged: notifier.setSttManualStartAdvanceBigWords,
            onReset: () {
              unawaited(notifier.setSttManualStartAdvanceSmallWords(4));
              unawaited(notifier.setSttManualStartAdvanceBigWords(3));
            },
          ),
          const SizedBox(height: 10),
          _SpeechThresholdCard(
            title: 'Safety recovery',
            subtitle: 'Evidence needed after misrecognized words.',
            smallValue: settings.sttManualSafetySmallWords,
            bigValue: settings.sttManualSafetyBigWords,
            smallMin: 1,
            smallMax: 5,
            bigMin: 1,
            bigMax: 5,
            accentColor: accent,
            onSmallChanged: notifier.setSttManualSafetySmallWords,
            onBigChanged: notifier.setSttManualSafetyBigWords,
            onReset: () {
              unawaited(notifier.setSttManualSafetySmallWords(2));
              unawaited(notifier.setSttManualSafetyBigWords(1));
            },
          ),
          const SizedBox(height: 10),
          _SpeechThresholdCard(
            title: 'Visible-area skip',
            subtitle: 'Set both values to zero to disable jumping.',
            smallValue: settings.sttManualVisibleSkipSmallWords,
            bigValue: settings.sttManualVisibleSkipBigWords,
            smallMin: 0,
            smallMax: 8,
            bigMin: 0,
            bigMax: 8,
            accentColor: accent,
            onSmallChanged: notifier.setSttManualVisibleSkipSmallWords,
            onBigChanged: notifier.setSttManualVisibleSkipBigWords,
            onReset: () {
              unawaited(notifier.setSttManualVisibleSkipSmallWords(0));
              unawaited(notifier.setSttManualVisibleSkipBigWords(0));
            },
          ),
        ],
      ],
    );
  }
}

class _SpeechSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accentColor;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SpeechSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accentColor,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? 1.0 : .42;
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled && value,
              activeColor: accentColor,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechThresholdCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int smallValue;
  final int bigValue;
  final int smallMin;
  final int smallMax;
  final int bigMin;
  final int bigMax;
  final Color accentColor;
  final ValueChanged<int> onSmallChanged;
  final ValueChanged<int> onBigChanged;
  final VoidCallback onReset;

  const _SpeechThresholdCard({
    required this.title,
    required this.subtitle,
    required this.smallValue,
    required this.bigValue,
    required this.smallMin,
    required this.smallMax,
    required this.bigMin,
    required this.bigMax,
    required this.accentColor,
    required this.onSmallChanged,
    required this.onBigChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return _SpeechCardFrame(
      title: title,
      subtitle: subtitle,
      onReset: onReset,
      children: [
        _SpeechStepperRow(
          label: 'Small words',
          value: smallValue,
          min: smallMin,
          max: smallMax,
          accentColor: accentColor,
          onChanged: onSmallChanged,
        ),
        _SpeechStepperRow(
          label: 'Big words',
          value: bigValue,
          min: bigMin,
          max: bigMax,
          accentColor: accentColor,
          onChanged: onBigChanged,
        ),
      ],
    );
  }
}

class _SpeechStepperCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final Color accentColor;
  final ValueChanged<int> onChanged;
  final VoidCallback onReset;

  const _SpeechStepperCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.accentColor,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return _SpeechCardFrame(
      title: title,
      subtitle: subtitle,
      onReset: onReset,
      children: [
        _SpeechStepperRow(
          label: 'Letters',
          value: value,
          min: min,
          max: max,
          accentColor: accentColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SpeechCardFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback onReset;

  const _SpeechCardFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(onPressed: onReset, child: const Text('Reset')),
            ],
          ),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SpeechStepperRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final Color accentColor;
  final ValueChanged<int> onChanged;

  const _SpeechStepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        IconButton(
          onPressed: value <= min ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_rounded),
          color: Colors.white70,
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accentColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          onPressed: value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_rounded),
          color: Colors.white70,
        ),
      ],
    );
  }
}
