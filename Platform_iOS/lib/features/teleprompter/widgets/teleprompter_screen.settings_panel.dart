part of 'teleprompter_screen.dart';

class TeleprompterSettingsPanel extends ConsumerWidget {
  const TeleprompterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    void applyPresenterFontSize(double size) {
      final clamped = size.clamp(14.0, 120.0).toDouble();
      unawaited(notifier.setFontSize(clamped));
      unawaited(
        ref.read(scriptProvider.notifier).updateStyleMetadata(
              fontSize: clamped,
            ),
      );
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
      builder: (_, controller) => DecoratedBox(
        // Solid panel so the script behind it never bleeds through and makes
        // the settings hard to read/change.
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
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
          const _SpeechProfileSettingsSection(),
          const SizedBox(height: 16),
          Opacity(
            opacity: settings.scrollMode == 'manual' ? 0.45 : 1.0,
            child: AbsorbPointer(
              absorbing: settings.scrollMode == 'manual',
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pan_tool_alt_outlined,
                      color: Color(settings.currentWordColor),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Allow manual scrolling while listening',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Drag the script during speech recognition; release to resume from the reading line.',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: settings.allowScrollDuringActiveSession &&
                          settings.scrollMode != 'manual',
                      activeColor: Color(settings.currentWordColor),
                      onChanged: notifier.setAllowScrollDuringActiveSession,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

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

          // Professional: Broadcast Profiles
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
            value: settings.fontSize.clamp(14.0, 120.0),
            min: 14,
            max: 120,
            divisions: 53,
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
      ),
    );
  }

  ButtonStyle _segmentStyle(AppSettings settings) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Color(settings.currentWordColor);
        }
        return const Color(0xFF2A2A2A);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.black;
        return Colors.white70;
      }),
    );
  }
}

class _IosMicSelector extends StatelessWidget {
  final String selectedDeviceId;
  final String selectedLabel;
  final List<SttAudioInputDevice> devices;
  final Color accentColor;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String deviceId, String label) onSelected;

  const _IosMicSelector({
    required this.selectedDeviceId,
    required this.selectedLabel,
    required this.devices,
    required this.accentColor,
    required this.onRefresh,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final knownIds = devices.map((device) => device.id).toSet();
    final value = knownIds.contains(selectedDeviceId) ? selectedDeviceId : '';
    final entries = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: '',
        child: Text('System default microphone'),
      ),
      ...devices.map(
        (device) => DropdownMenuItem(
          value: device.id,
          child: Text(device.label, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          iconEnabledColor: accentColor,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.mic_external_on, color: accentColor),
            helperText: devices.isEmpty
                ? 'Connect a mic, then refresh or start STT once.'
                : 'Uses iOS current/preferred audio input route.',
            helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: const Color(0xFF111111),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: accentColor),
            ),
          ),
          items: entries,
          selectedItemBuilder: (_) => entries
              .map(
                (entry) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    entry.value == ''
                        ? 'System default microphone'
                        : selectedLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: (deviceId) {
            if (deviceId == null) return;
            final label = deviceId.isEmpty
                ? 'System default microphone'
                : devices
                    .firstWhere(
                      (device) => device.id == deviceId,
                      orElse: () => SttAudioInputDevice(
                        id: deviceId,
                        label: selectedLabel,
                      ),
                    )
                    .label;
            unawaited(onSelected(deviceId, label));
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Refresh iOS audio inputs'),
            style: TextButton.styleFrom(foregroundColor: accentColor),
            onPressed: () => unawaited(onRefresh()),
          ),
        ),
      ],
    );
  }
}

class _PresetBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PresetBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFFFBF00), size: 18),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ── Full color palette grid ────────────────────────────────────────────────────

class _ColorGrid extends StatelessWidget {
  final int selected;
  final void Function(int) onSelected;

  const _ColorGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GlobalColorButton(
      color: selected,
      onColorChanged: onSelected,
      title: 'Select Color',
    );
  }
}
