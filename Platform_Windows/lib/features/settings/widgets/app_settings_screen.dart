import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../providers/settings_provider.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: Text('Settings',
            style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Profile ──
          const _SectionHeader(title: 'PROFILE'),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Display Name',
            subtitle: settings.displayName,
            onTap: () => _editDisplayName(context),
          ),

          if (Platform.isWindows) ...[
            const SizedBox(height: 22),
            const _SectionHeader(title: 'SPEECH INPUT'),
            const SizedBox(height: 8),
            _SpeechEngineTile(
              value: settings.sttEngine,
              onChanged: (engine) =>
                  ref.read(settingsProvider.notifier).setSttEngine(engine),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.mic_external_on_outlined,
              title: 'Preferred Microphone',
              subtitle: settings.sttInputDeviceId.isEmpty
                  ? 'System default microphone'
                  : settings.sttInputDeviceLabel,
              onTap: settings.sttInputDeviceId.isEmpty
                  ? null
                  : () => ref
                      .read(settingsProvider.notifier)
                      .setSttInputDevice('', 'System default microphone'),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.settings_input_component_outlined,
              title: 'Windows Input Settings',
              subtitle: 'Choose or test the default external mic',
              onTap: () =>
                  Process.run('cmd', ['/c', 'start', 'ms-settings:sound']),
            ),
          ],
          const SizedBox(height: 22),
          const _SectionHeader(title: 'DIAGNOSTICS'),
          const SizedBox(height: 8),
          _SettingsSwitchTile(
            icon: Icons.bug_report_outlined,
            title: 'Debug Mode',
            subtitle: settings.debugMode
                ? 'Detailed logs and trace tools are visible'
                : 'Normal mode: heavy debug traces stay off',
            value: settings.debugMode,
            onChanged: (_) =>
                ref.read(settingsProvider.notifier).toggleDebugMode(),
          ),

          const SizedBox(height: 22),
          const _SectionHeader(title: 'BETA FEEDBACK'),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.bug_report_outlined,
            title: 'Send Feedback',
            subtitle: 'Includes full active script and diagnostics',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FeedbackReportScreen()),
            ),
          ),
        ],
      ),
    );
  }

  void _editDisplayName(BuildContext context) {
    final controller =
        TextEditingController(text: ref.read(settingsProvider).displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Display Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Your name',
            hintStyle: const TextStyle(color: Colors.white24),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(settingsProvider.notifier).setDisplayName(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save',
                style: TextStyle(
                    color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
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
    final normalizedValue = value == 'google' ? value : 'google';
    final hasUnsupportedSavedValue = value != 'google';

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
                value: 'google',
                child: Text('Online speech recognition'),
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
              'enabled for this Windows beta. Online speech recognition will '
              'be used until the Windows offline engine returns.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onChanged('google'),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Use online engine'),
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

  const _SettingsTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});

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
                activeThumbColor: const Color(0xFFFFBF00),
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
