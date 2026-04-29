part of 'teleprompter_screen.dart';

class _WindowsMicSelector extends StatelessWidget {
  final String selectedDeviceId;
  final String selectedLabel;
  final List<SttAudioInputDevice> devices;
  final Color accentColor;
  final Future<void> Function(String deviceId, String label) onSelected;

  const _WindowsMicSelector({
    required this.selectedDeviceId,
    required this.selectedLabel,
    required this.devices,
    required this.accentColor,
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.settings_input_component, size: 17),
            label: const Text('Open Windows input settings'),
            style: TextButton.styleFrom(foregroundColor: accentColor),
            onPressed: () {
              Process.run('cmd', ['/c', 'start', 'ms-settings:sound']);
            },
          ),
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
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            onChanged: onChanged,
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
