part of 'teleprompter_screen.dart';

Future<void> _openMacSoundInputSettings() async {
  final targets = [
    'x-apple.systempreferences:com.apple.Sound-Settings.extension?input',
    'x-apple.systempreferences:com.apple.preference.sound?Input',
    'x-apple.systempreferences:com.apple.Sound-Settings.extension',
  ];

  for (final target in targets) {
    try {
      final result = await Process.run('open', [target]);
      if (result.exitCode == 0) return;
    } catch (_) {}
  }
}

class _MacMicSelector extends StatelessWidget {
  final String selectedLabel;
  final List<SttAudioInputDevice> devices;
  final Color accentColor;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onUseDefault;

  const _MacMicSelector({
    required this.selectedLabel,
    required this.devices,
    required this.accentColor,
    required this.onRefresh,
    required this.onUseDefault,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedLabel.trim().isEmpty
        ? 'System default microphone'
        : selectedLabel.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.mic_external_on, color: accentColor, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            devices.length <= 1
                ? 'Apple Speech uses the macOS Sound Input device.'
                : 'Apple Speech follows the input selected in macOS Sound settings.',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (devices.length > 1) ...[
            const SizedBox(height: 8),
            for (final device in devices)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  device.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: device.label == label ? accentColor : Colors.white54,
                    fontSize: 11,
                    fontWeight: device.label == label
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(foregroundColor: accentColor),
                onPressed: () => unawaited(onRefresh()),
              ),
              TextButton.icon(
                icon: const Icon(Icons.settings_input_component, size: 16),
                label: const Text('Open Input Settings'),
                style: TextButton.styleFrom(foregroundColor: accentColor),
                onPressed: () => unawaited(_openMacSoundInputSettings()),
              ),
              TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Use Default'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: () => unawaited(onUseDefault()),
              ),
            ],
          ),
        ],
      ),
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
