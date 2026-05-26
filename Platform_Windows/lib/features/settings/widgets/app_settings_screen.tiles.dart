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

class _SpeechEngineTile extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SpeechEngineTile({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = {
      AppSettings.sttEngineAuto,
      AppSettings.sttEngineWindowsOffline,
      AppSettings.sttEngineBrowserOnline,
    }.contains(value)
        ? value
        : AppSettings.sttEngineAuto;
    final hasUnsupportedSavedValue = value != normalizedValue;

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
          const Row(
            children: [
              Icon(
                Icons.record_voice_over_outlined,
                color: Colors.white54,
                size: 22,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Speech Recognition Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Controls the sound-to-text system used in Present mode',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // Flutter 3.32 on GitHub Actions still requires value.
            // ignore: deprecated_member_use
            value: normalizedValue,
            dropdownColor: const Color(0xFF1A1A1A),
            iconEnabledColor: const Color(0xFFFFBF00),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF111111),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFFBF00)),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: AppSettings.sttEngineAuto,
                child: Text('Auto: offline English / online fallback'),
              ),
              DropdownMenuItem(
                value: AppSettings.sttEngineWindowsOffline,
                child: Text('Windows offline speech'),
              ),
              DropdownMenuItem(
                value: AppSettings.sttEngineBrowserOnline,
                child: Text('Online browser speech'),
              ),
            ],
            onChanged: (engine) {
              if (engine == null) return;
              onChanged(engine);
            },
          ),
          if (hasUnsupportedSavedValue) ...[
            const SizedBox(height: 8),
            const Text(
              'Offline Whisper was saved in an older build, but it is not '
              'enabled for this Windows beta. Auto speech recognition will '
              'be used instead.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onChanged(AppSettings.sttEngineAuto),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Use auto engine'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFBF00),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteControlTile extends StatelessWidget {
  final bool isRunning;
  final bool isBusy;
  final String url;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  const _RemoteControlTile({
    required this.isRunning,
    required this.isBusy,
    required this.url,
    required this.error,
    required this.onStart,
    required this.onStop,
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local Remote Control',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Start a phone/browser controller for Present mode',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
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
