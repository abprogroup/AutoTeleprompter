part of 'teleprompter_screen.dart';

class _WindowsMicSelector extends StatelessWidget {
  final String selectedDeviceId;
  final String selectedLabel;
  final List<SttAudioInputDevice> devices;
  final Color accentColor;
  final Future<void> Function(String deviceId, String label) onSelected;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onUseDefault;

  const _WindowsMicSelector({
    required this.selectedDeviceId,
    required this.selectedLabel,
    required this.devices,
    required this.accentColor,
    required this.onSelected,
    required this.onRefresh,
    required this.onUseDefault,
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
          child: Text(
            device.label,
            overflow: TextOverflow.ellipsis,
          ),
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
                ? 'Start the mic once to discover connected inputs.'
                : 'Switches the active WebView2 audio input when available.',
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
              .map((entry) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      entry.value == ''
                          ? 'System default microphone'
                          : selectedLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ))
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
            onSelected(deviceId, label);
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(foregroundColor: accentColor),
              onPressed: () => unawaited(onRefresh()),
            ),
            TextButton.icon(
              icon: const Icon(Icons.settings_input_component, size: 17),
              label: const Text('Open Windows input settings'),
              style: TextButton.styleFrom(foregroundColor: accentColor),
              onPressed: () {
                Process.run('cmd', ['/c', 'start', 'ms-settings:sound']);
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 17),
              label: const Text('Use Default'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => unawaited(onUseDefault()),
            ),
          ],
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accentColor;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const _SwitchRow({
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
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.42,
      duration: const Duration(milliseconds: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeColor: accentColor,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SttThresholdPairSliders extends StatelessWidget {
  final String title;
  final String subtitle;
  final int smallValue;
  final int bigValue;
  final int smallMin;
  final int smallMax;
  final int bigMin;
  final int bigMax;
  final bool allowOff;
  final Color accentColor;
  final ValueChanged<int> onSmallChanged;
  final ValueChanged<int> onBigChanged;
  final VoidCallback onReset;

  const _SttThresholdPairSliders({
    required this.title,
    required this.subtitle,
    required this.smallValue,
    required this.bigValue,
    required this.smallMin,
    required this.smallMax,
    required this.bigMin,
    required this.bigMax,
    required this.allowOff,
    required this.accentColor,
    required this.onSmallChanged,
    required this.onBigChanged,
    required this.onReset,
  });

  static String labelFor(int smallWords, int bigWords) {
    if (smallWords <= 0 || bigWords <= 0) return 'Off';
    return '$smallWords small words / $bigWords big words';
  }

  @override
  Widget build(BuildContext context) {
    final isOff = smallValue <= 0 || bigValue <= 0;
    final displayLabel = labelFor(smallValue, bigValue);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                displayLabel,
                style: TextStyle(
                  color: isOff ? Colors.white38 : accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Reset to default',
                child: IconButton(
                  icon: const Icon(Icons.restart_alt, size: 17),
                  color: Colors.white70,
                  splashRadius: 17,
                  visualDensity: VisualDensity.compact,
                  onPressed: onReset,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 6),
          _thresholdSliderRow(
            label: 'Small words',
            value: smallValue,
            min: smallMin,
            max: smallMax,
            allowOff: allowOff,
            accentColor: accentColor,
            onChanged: onSmallChanged,
          ),
          _thresholdSliderRow(
            label: 'Big words',
            value: bigValue,
            min: bigMin,
            max: bigMax,
            allowOff: allowOff,
            accentColor: accentColor,
            onChanged: onBigChanged,
          ),
        ],
      ),
    );
  }

  Widget _thresholdSliderRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required bool allowOff,
    required Color accentColor,
    required ValueChanged<int> onChanged,
  }) {
    final sliderMin = allowOff ? 0.0 : min.toDouble();
    final safeValue =
        value <= 0 && allowOff ? 0.0 : value.clamp(min, max).toDouble();
    final displayValue = value <= 0 && allowOff ? 'Off' : value.toString();

    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            '$label: $displayValue',
            style: TextStyle(
              color: value <= 0 && allowOff ? Colors.white38 : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: safeValue,
            min: sliderMin,
            max: max.toDouble(),
            divisions: max - sliderMin.toInt(),
            activeColor: accentColor,
            inactiveColor: Colors.white24,
            label: displayValue,
            onChanged: (next) {
              var rounded = next.round();
              if (allowOff && rounded > 0 && rounded < min) rounded = min;
              onChanged(rounded);
            },
          ),
        ),
      ],
    );
  }
}

class _SttBigWordLengthSlider extends StatelessWidget {
  final int value;
  final Color accentColor;
  final ValueChanged<int> onChanged;
  final VoidCallback onReset;

  const _SttBigWordLengthSlider({
    required this.value,
    required this.accentColor,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(3, 10).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Big word length',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$value+ letters',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Reset to default',
                child: IconButton(
                  icon: const Icon(Icons.restart_alt, size: 17),
                  color: Colors.white70,
                  splashRadius: 17,
                  visualDensity: VisualDensity.compact,
                  onPressed: onReset,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Words with this many letters count as big words in all manual thresholds.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          Slider(
            value: safeValue,
            min: 3,
            max: 10,
            divisions: 7,
            activeColor: accentColor,
            inactiveColor: Colors.white24,
            label: '$value+ letters',
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      ),
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
