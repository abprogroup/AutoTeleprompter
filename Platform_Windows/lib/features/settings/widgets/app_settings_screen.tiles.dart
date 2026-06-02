part of 'app_settings_screen.dart';

class _ConsentDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ConsentDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteControlTile extends StatelessWidget {
  final String title;
  final bool isRunning;
  final bool isBusy;
  final String url;
  final String pairingPin;
  final int connectedClientCount;
  final DateTime? sessionExpiresAt;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRename;
  final VoidCallback onRevoke;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  const _RemoteControlTile({
    required this.title,
    required this.isRunning,
    required this.isBusy,
    required this.url,
    required this.pairingPin,
    required this.connectedClientCount,
    required this.sessionExpiresAt,
    required this.error,
    required this.onStart,
    required this.onStop,
    required this.onRename,
    required this.onRevoke,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final status = isRunning ? 'Running at $url' : 'Stopped';
    final statusColor = isRunning ? const Color(0xFFFFBF00) : Colors.white38;

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
              Icon(
                isRunning
                    ? Icons.settings_remote_rounded
                    : Icons.settings_remote_outlined,
                color: Colors.white54,
                size: 22,
              ),
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
                    const Text(
                      'Phone/browser controller for Present mode',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Rename selected remote',
                visualDensity: VisualDensity.compact,
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFFBF00),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(status, style: TextStyle(color: statusColor, fontSize: 12)),
          if (isRunning && pairingPin.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Pairing PIN: $pairingPin',
              style: const TextStyle(
                color: Color(0xFFFFBF00),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Only devices with this session PIN can control the prompter.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Connected remotes: $connectedClientCount',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (sessionExpiresAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Session token expires: ${_formatRemoteExpiry(sessionExpiresAt!)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 8),
          const Text(
            'Use only on a trusted local network. Stop remote control when the '
            'phone/browser controller is no longer needed.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isBusy ? null : (isRunning ? onStop : onStart),
                icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow),
                label: Text(isRunning ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
              ),
              OutlinedButton.icon(
                onPressed: isRunning ? onCopy : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy URL'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFBF00),
                  side: const BorderSide(color: Color(0xFFFFBF00)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: isRunning && !isBusy ? onRevoke : null,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('New PIN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              OutlinedButton.icon(
                onPressed: isRunning ? onOpen : null,
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text('Open'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRemoteExpiry(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(
          color: Color(0xFFFFBF00),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ));
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white54, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
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
              Switch.adaptive(
                value: value,
                // Flutter 3.32 on GitHub Actions still requires activeColor.
                // ignore: deprecated_member_use
                activeColor: const Color(0xFFFFBF00),
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsChoice<T> {
  final String label;
  final T value;

  const _SettingsChoice({
    required this.label,
    required this.value,
  });
}

class _SettingsChoiceTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<_SettingsChoice<T>> choices;
  final ValueChanged<T> onChanged;

  const _SettingsChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.choices,
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
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.map((choice) {
              final selected = choice.value == value;
              return ChoiceChip(
                selected: selected,
                showCheckmark: true,
                checkmarkColor: Colors.black,
                selectedColor: const Color(0xFFFFBF00),
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: selected ? Colors.transparent : Colors.white54,
                ),
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                label: Text(choice.label),
                onSelected: (_) => onChanged(choice.value),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _SettingsSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
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
                valueLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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

class _SettingsAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SettingsAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
}

class _SettingsActionsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<_SettingsAction> actions;

  const _SettingsActionsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
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
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: actions
                .map(
                  (action) => TextButton.icon(
                    onPressed: action.onPressed,
                    icon: Icon(action.icon, size: 18),
                    label: Text(action.label),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFBF00),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
