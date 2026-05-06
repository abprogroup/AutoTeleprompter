part of 'teleprompter_screen.dart';

class TeleprompterSettingsPanel extends ConsumerWidget {
  final ValueChanged<double>? onFontSizeChanged;

  const TeleprompterSettingsPanel({super.key, this.onFontSizeChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tState = ref.watch(teleprompterProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final manualSttProfile = settings.sttManualProfileEnabled;
    final visibleSkipControlsEnabled = !manualSttProfile;
    final hardSkipControlsEnabled =
        !manualSttProfile && settings.sttVisibleSkipEnabled;
    void applyPresenterFontSize(double size) {
      final clamped = size.clamp(14.0, 120.0).toDouble();
      ref.read(teleprompterProvider.notifier).setVisibleWordWindow(null, null);
      unawaited(notifier.setFontSize(clamped));
      unawaited(
        ref.read(scriptProvider.notifier).updateStyleMetadata(
              fontSize: clamped,
            ),
      );
      onFontSizeChanged?.call(clamped);
    }

    void applyPresenterLineSpacing(double spacing) {
      final clamped = spacing.clamp(0.5, 3.0).toDouble();
      unawaited(notifier.setLineSpacing(clamped));
      unawaited(
        ref.read(scriptProvider.notifier).updateStyleMetadata(
              lineSpacing: clamped,
            ),
      );
    }

    void applyPresenterWordSpacing(double spacing) {
      final clamped = spacing.clamp(-5.0, 20.0).toDouble();
      unawaited(notifier.setWordSpacing(clamped));
      unawaited(
        ref.read(scriptProvider.notifier).updateStyleMetadata(
              wordSpacing: clamped,
            ),
      );
    }

    void applyPresenterLetterSpacing(double spacing) {
      final clamped = spacing.clamp(-2.0, 5.0).toDouble();
      unawaited(notifier.setLetterSpacing(clamped));
      unawaited(
        ref.read(scriptProvider.notifier).updateStyleMetadata(
              letterSpacing: clamped,
            ),
      );
    }

    String formatDefaultOffset(double value, double defaultValue) {
      final delta = value - defaultValue;
      if (delta.abs() < 0.05) return '0.0';
      final sign = delta > 0 ? '+' : '';
      return '$sign${delta.toStringAsFixed(1)}';
    }

    const labelStyle = TextStyle(color: Colors.white70, fontSize: 14);
    const sectionStyle = TextStyle(
        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.80,
      maxChildSize: 0.97,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // ── Scroll mode ─────────────────────────────────────────────────────
          const Text('Scroll Mode', style: sectionStyle),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'auto',
                  label: Text('Speech Auto'),
                  icon: Icon(Icons.mic)),
              ButtonSegment(
                  value: 'manual',
                  label: Text('Manual Speed'),
                  icon: Icon(Icons.speed)),
            ],
            selected: {settings.scrollMode},
            onSelectionChanged: (val) => notifier.setScrollMode(val.first),
            style: _segmentStyle(settings),
          ),
          const SizedBox(height: 16),

          if (Platform.isWindows) ...[
            const Text('Speech Input', style: sectionStyle),
            const SizedBox(height: 8),
            _WindowsMicSelector(
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
                  'Advanced: set exact STT thresholds yourself. This turns off Bullet, Visible Skip, and Hard Skip buttons.',
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
              _SttThresholdSlider(
                title: 'Words to start advancing',
                subtitle:
                    'How much ordered text is needed before normal reading starts moving.',
                value: settings.sttManualStartAdvanceSmallWords,
                min: 2,
                max: 8,
                allowOff: false,
                accentColor: Color(settings.currentWordColor),
                onChanged: notifier.setSttManualStartAdvanceSmallWords,
              ),
              const SizedBox(height: 12),
              _SttThresholdSlider(
                title: 'Safety recovery',
                subtitle:
                    'How much ordered evidence can recover from 1-2 misrecognized words.',
                value: settings.sttManualSafetySmallWords,
                min: 1,
                max: 5,
                allowOff: false,
                accentColor: Color(settings.currentWordColor),
                onChanged: notifier.setSttManualSafetySmallWords,
              ),
              const SizedBox(height: 12),
              _SttThresholdSlider(
                title: 'Visible-area skip',
                subtitle:
                    'Off disables jumping. Higher values make visible jumps stricter.',
                value: settings.sttManualVisibleSkipSmallWords,
                min: 2,
                max: 8,
                allowOff: true,
                accentColor: Color(settings.currentWordColor),
                onChanged: notifier.setSttManualVisibleSkipSmallWords,
              ),
            ],
            const SizedBox(height: 16),
          ],

          if (settings.scrollMode == 'manual') ...[
            Row(children: [
              const Text('Manual Scroll Speed', style: labelStyle),
              const Spacer(),
              Text(
                  '${settings.scrollSpeed.round() > 0 ? "+" : ""}${settings.scrollSpeed.round()} wpm',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ]),
            Slider(
              value: settings.scrollSpeed,
              min: -300,
              max: 300,
              divisions: 120,
              activeColor: Color(settings.currentWordColor),
              inactiveColor: Colors.white24,
              onChanged: (v) => notifier.setScrollSpeed(v),
            ),
            const SizedBox(height: 8),
          ],

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Text ───────────────────────────────────────────────────────────
          Row(children: [
            const Text('Override Text Alignment', style: sectionStyle),
            const Spacer(),
            Switch.adaptive(
              value: settings.showAlignmentOverride,
              activeColor: Color(settings.currentWordColor),
              onChanged: (v) => notifier.setShowAlignmentOverride(v),
            ),
          ]),
          const SizedBox(height: 8),
          AnimatedOpacity(
            opacity: settings.showAlignmentOverride ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !settings.showAlignmentOverride,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'left', icon: Icon(Icons.format_align_left)),
                  ButtonSegment(
                      value: 'center', icon: Icon(Icons.format_align_center)),
                  ButtonSegment(
                      value: 'right', icon: Icon(Icons.format_align_right)),
                ],
                selected: {settings.textAlign},
                onSelectionChanged: (val) => notifier.setTextAlign(val.first),
                style: _segmentStyle(settings),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text('Layout & Typography', style: sectionStyle),
          const SizedBox(height: 14),

          // V3 Professional: Broadcast Profiles
          const Text('Broadcast Profile', style: labelStyle),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetBtn(
                    label: 'Classic',
                    icon: Icons.document_scanner,
                    onTap: () => notifier.applyPreset('Classic')),
                const SizedBox(width: 8),
                _PresetBtn(
                    label: 'High-Contrast',
                    icon: Icons.visibility,
                    onTap: () => notifier.applyPreset('High Contrast')),
                const SizedBox(width: 8),
                _PresetBtn(
                    label: 'Modern Soft',
                    icon: Icons.auto_awesome_mosaic,
                    onTap: () => notifier.applyPreset('Modern Soft')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(children: [
            const Text('Font Size', style: labelStyle),
            const Spacer(),
            Text('${settings.fontSize.round()}px',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.fontSize.clamp(14.0, 120.0).toDouble(),
            min: 14,
            max: 120,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: applyPresenterFontSize,
          ),

          Row(children: [
            const Text('Line Spacing', style: labelStyle),
            const Spacer(),
            Text(formatDefaultOffset(settings.lineSpacing, 1.2),
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.lineSpacing.clamp(0.5, 3.0).toDouble(),
            min: 0.5,
            max: 3.0,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: applyPresenterLineSpacing,
          ),

          Row(children: [
            const Text('Word Spacing', style: labelStyle),
            const Spacer(),
            Text('${settings.wordSpacing.toStringAsFixed(1)}px',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.wordSpacing.clamp(-5.0, 20.0).toDouble(),
            min: -5.0,
            max: 20.0,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: applyPresenterWordSpacing,
          ),

          Row(children: [
            const Text('Letter Spacing', style: labelStyle),
            const Spacer(),
            Text('${settings.letterSpacing.toStringAsFixed(1)}px',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.letterSpacing.clamp(-2.0, 5.0).toDouble(),
            min: -2.0,
            max: 5.0,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: applyPresenterLetterSpacing,
          ),

          Row(children: [
            const Text('Reading Line Position', style: labelStyle),
            const Spacer(),
            Text('${(settings.scrollLead * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.scrollLead,
            min: 0.15,
            max: 0.60,
            divisions: 18,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setScrollLead(v),
          ),

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Colors ─────────────────────────────────────────────────────────
          const Text('Colors', style: sectionStyle),
          const SizedBox(height: 14),

          const Text('Script Background', style: labelStyle),
          const SizedBox(height: 8),
          _ColorGrid(
            selected: settings.scriptBgColor,
            onSelected: notifier.setScriptBgColor,
          ),
          const SizedBox(height: 16),

          Row(children: [
            const Text('Current Word (reading focus)', style: labelStyle),
            const Spacer(),
            Switch.adaptive(
              value: settings.showCurrentWordHighlight,
              activeColor: Color(settings.currentWordColor),
              onChanged: (v) => notifier.setShowCurrentWordHighlight(v),
            ),
          ]),
          const SizedBox(height: 8),
          _ColorGrid(
            selected: settings.currentWordColor,
            onSelected: notifier.setCurrentWordColor,
          ),
          const SizedBox(height: 16),

          Row(children: [
            const Text('Upcoming Text Color', style: labelStyle),
            const Spacer(),
            Switch.adaptive(
              value: settings.showUpcomingWordColor,
              activeColor: Color(settings.currentWordColor),
              onChanged: (v) => notifier.setShowUpcomingWordColor(v),
            ),
          ]),
          const SizedBox(height: 8),
          _ColorGrid(
            selected: settings.futureWordColor,
            onSelected: notifier.setFutureWordColor,
          ),
          const SizedBox(height: 16),

          Row(children: [
            const Text('Past Words Opacity', style: labelStyle),
            const Spacer(),
            Text('${(settings.pastWordOpacity * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.pastWordOpacity,
            min: 0.05,
            max: 1.0,
            divisions: 19,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setPastWordOpacity(v),
          ),

          Row(children: [
            const Text('Fade Past Lines', style: labelStyle),
            const Spacer(),
            Text(
                settings.readFadeIntensity == 0
                    ? 'Off'
                    : '${(settings.readFadeIntensity * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          Slider(
            value: settings.readFadeIntensity,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            activeColor: Color(settings.currentWordColor),
            inactiveColor: Colors.white24,
            onChanged: (v) => notifier.setReadFadeIntensity(v),
          ),

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Display ────────────────────────────────────────────────────────
          Row(
            children: [
              const Text('Mirror Horizontal', style: sectionStyle),
              const Spacer(),
              Switch(
                value: settings.mirrorHorizontal,
                activeColor: Color(settings.currentWordColor),
                onChanged: (v) => notifier.setMirrorHorizontal(v),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Mirror Vertical (Flip)', style: sectionStyle),
              const Spacer(),
              Switch(
                value: settings.mirrorVertical,
                activeColor: Color(settings.currentWordColor),
                onChanged: (v) => notifier.setMirrorVertical(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Screen Rotation', style: sectionStyle),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('0°')),
              ButtonSegment(value: 90, label: Text('90°')),
              ButtonSegment(value: 180, label: Text('180°')),
              ButtonSegment(value: 270, label: Text('270°')),
            ],
            selected: {settings.flipRotation},
            onSelectionChanged: (val) => notifier.setFlipRotation(val.first),
            style: _segmentStyle(settings),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  ButtonStyle _segmentStyle(AppSettings settings) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected))
          return Color(settings.currentWordColor);
        return const Color(0xFF2A2A2A);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.black;
        return Colors.white70;
      }),
    );
  }
}
