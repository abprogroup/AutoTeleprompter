import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../feedback/providers/beta_consent_provider.dart';
import '../../feedback/widgets/beta_consent_gate.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../remote/services/remote_control_service.dart';
import '../providers/settings_provider.dart';
import 'cloud_sync_screen.dart';

part 'app_settings_screen.tiles.dart';

enum AppSettingsTab { general, account, remote, editor, present }

extension AppSettingsTabIndex on AppSettingsTab {
  int get index => AppSettingsTab.values.indexOf(this);
}

class AppSettingsScreen extends ConsumerStatefulWidget {
  final AppSettingsTab initialTab;

  const AppSettingsScreen({
    super.key,
    this.initialTab = AppSettingsTab.general,
  });

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  bool _remoteBusy = false;
  String? _remoteUrl;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRemoteUrl());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final remote = Platform.isWindows ? ref.read(remoteControlProvider) : null;

    return DefaultTabController(
      length: AppSettingsTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          title: Text(
            'Settings',
            style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 1.5),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Color(0xFFFFBF00),
            unselectedLabelColor: Colors.white54,
            indicatorColor: Color(0xFFFFBF00),
            tabs: [
              Tab(icon: Icon(Icons.tune_rounded), text: 'General'),
              Tab(icon: Icon(Icons.person_outline), text: 'Account'),
              Tab(icon: Icon(Icons.settings_remote_outlined), text: 'Remote'),
              Tab(icon: Icon(Icons.edit_note_rounded), text: 'Editor'),
              Tab(icon: Icon(Icons.present_to_all_rounded), text: 'Present'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _settingsList(_generalTab(settings)),
            _settingsList(_accountTab(settings)),
            _settingsList(_remoteTab(remote)),
            _settingsList(_editorTab()),
            _settingsList(_presentTab(settings)),
          ],
        ),
      ),
    );
  }

  Widget _settingsList(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: children,
    );
  }

  List<Widget> _generalTab(AppSettings settings) {
    return [
      const _SectionHeader(title: 'DIAGNOSTICS'),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.bug_report_outlined,
        title: 'Debug Mode',
        subtitle: settings.debugMode
            ? 'Detailed logs and trace tools are visible'
            : 'Normal mode: heavy debug traces stay off',
        value: settings.debugMode,
        onChanged: (_) => ref.read(settingsProvider.notifier).toggleDebugMode(),
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'CLOUD SYNC'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.cloud_sync_outlined,
        title: 'Cloud Sync',
        subtitle: 'Coming soon: connect storage and sync scripts',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
        ),
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
    ];
  }

  List<Widget> _accountTab(AppSettings settings) {
    return [
      const _SectionHeader(title: 'PROFILE'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.person_outline,
        title: 'Display Name',
        subtitle: settings.displayName,
        onTap: () => _editDisplayName(context),
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'BETA PRIVACY'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.privacy_tip_outlined,
        title: 'Beta Privacy Consent',
        subtitle: 'Review device key, policy version, and consent status',
        onTap: () => _showBetaConsentDetails(context),
      ),
    ];
  }

  List<Widget> _remoteTab(RemoteControlService? remote) {
    if (!Platform.isWindows || remote == null) {
      return const [
        _SectionHeader(title: 'REMOTE CONTROL'),
        SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.settings_remote_outlined,
          title: 'Local Remote Control',
          subtitle: 'Available on Windows in this beta',
        ),
      ];
    }

    return [
      const _SectionHeader(title: 'REMOTE CONTROL'),
      const SizedBox(height: 8),
      _RemoteControlTile(
        isRunning: remote.isRunning,
        isBusy: _remoteBusy,
        url: _remoteUrl ?? remote.localUrl,
        error: _remoteError,
        onStart: _startRemote,
        onStop: _stopRemote,
        onCopy: _copyRemoteUrl,
        onOpen: _openRemoteUrl,
      ),
    ];
  }

  List<Widget> _editorTab() {
    return const [
      _SectionHeader(title: 'EDITOR'),
      SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.edit_note_rounded,
        title: 'Editor Tools',
        subtitle: 'Text, layout, color, search, and selection tools live in '
            'the editor toolbar.',
      ),
    ];
  }

  List<Widget> _presentTab(AppSettings settings) {
    if (!Platform.isWindows) {
      return const [
        _SectionHeader(title: 'PRESENT MODE'),
        SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.present_to_all_rounded,
          title: 'Presenter Settings',
          subtitle: 'Presenter controls are available inside Present mode.',
        ),
      ];
    }

    return [
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
        onTap: () => Process.run('cmd', ['/c', 'start', 'ms-settings:sound']),
      ),
    ];
  }

  Future<void> _refreshRemoteUrl() async {
    if (!mounted || !Platform.isWindows) return;
    final remote = ref.read(remoteControlProvider);
    final url =
        remote.isRunning ? await remote.preferredUrl() : remote.localUrl;
    if (!mounted) return;
    setState(() {
      _remoteUrl = url;
      _remoteError = null;
    });
  }

  Future<void> _startRemote() async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    final remote = ref.read(remoteControlProvider);
    try {
      await remote.start();
      final url = await remote.preferredUrl();
      if (!mounted) return;
      setState(() => _remoteUrl = url);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _remoteError = 'Remote control could not start. Ports 8080-8090 may '
            'already be in use.';
      });
    } finally {
      if (mounted) setState(() => _remoteBusy = false);
    }
  }

  Future<void> _stopRemote() async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    await ref.read(remoteControlProvider).stop();
    if (!mounted) return;
    setState(() {
      _remoteBusy = false;
      _remoteUrl = ref.read(remoteControlProvider).localUrl;
    });
  }

  Future<void> _copyRemoteUrl() async {
    final url = _remoteUrl ?? ref.read(remoteControlProvider).localUrl;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Remote URL copied: $url')),
    );
  }

  Future<void> _openRemoteUrl() async {
    final url = _remoteUrl ?? ref.read(remoteControlProvider).localUrl;
    await Process.run('cmd', ['/c', 'start', url]);
  }

  void _showBetaConsentDetails(BuildContext context) {
    final consent = ref.read(betaConsentProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Beta Privacy Consent',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConsentDetailRow(
              label: 'Status',
              value: consent.hasAcceptedCurrentPolicy
                  ? 'Accepted'
                  : 'Not accepted',
            ),
            _ConsentDetailRow(
              label: 'Policy',
              value: consent.acceptedPolicyVersion.isEmpty
                  ? betaPrivacyPolicyVersion
                  : consent.acceptedPolicyVersion,
            ),
            _ConsentDetailRow(
              label: 'Accepted',
              value: consent.acceptedAtIso.isEmpty
                  ? 'Not recorded'
                  : consent.acceptedAtIso,
            ),
            _ConsentDetailRow(
              label: 'App version',
              value: consent.acceptedAppVersion.isEmpty
                  ? betaAppVersion
                  : consent.acceptedAppVersion,
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Device key: ${consent.deviceKey}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            const Text(
              'Withdrawing consent keeps your device key for support and '
              'deletion requests, then returns the app to the beta consent gate.',
              style: TextStyle(color: Colors.white54, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final dialogNavigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(
                ClipboardData(text: consent.deviceKey),
              );
              dialogNavigator.pop();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Device key copied.')),
              );
            },
            child: const Text('Copy key'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: consent.hasAcceptedCurrentPolicy
                ? () => _confirmWithdrawConsent(ctx)
                : null,
            child: const Text(
              'Withdraw',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmWithdrawConsent(BuildContext dialogContext) {
    Navigator.pop(dialogContext);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Withdraw beta consent?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The beta app cannot be used without accepting the current privacy '
          'notice. You can accept again from the consent screen.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(betaConsentProvider.notifier).withdrawConsent();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const BetaConsentGate()),
                (_) => false,
              );
            },
            child: const Text(
              'Withdraw',
              style: TextStyle(color: Colors.orangeAccent),
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
