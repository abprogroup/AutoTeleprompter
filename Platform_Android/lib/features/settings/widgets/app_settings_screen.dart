import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/services/account_backend_models.dart';
import '../../auth/widgets/login_screen.dart';
import '../../feedback/providers/beta_consent_provider.dart';
import '../../feedback/widgets/beta_consent_gate.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../remote/services/remote_control_service.dart';
import '../providers/settings_provider.dart';
import '../services/cloud_connection_store.dart';
import '../services/local_backup_service.dart';
import 'cloud_sync_screen.dart';
import '../services/settings_error_sanitizer.dart';
import '../services/update_check_service.dart';
import '../services/update_download_service.dart';
import '../services/update_install_service.dart';

part 'app_settings_screen.account.dart';
part 'app_settings_screen.local_backup.dart';
part 'app_settings_screen.remote_profiles.dart';
part 'app_settings_screen.updates.dart';

enum AppSettingsTab {
  general,
  account,
  remote,
  cloud,
}

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
  bool _checkingUpdates = false;
  bool _downloadingUpdate = false;
  bool _localBackupEnabled = false;
  String _localBackupPath = '';
  bool _remoteBusy = false;
  String? _remoteUrl;
  String? _remoteUrlProfileId;
  String? _remoteError;
  String? _selectedRemoteProfileId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocalBackupState());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRemoteUrl());
  }

  Future<void> _loadLocalBackupState() async {
    final enabled = await CloudConnectionStore().isLocalBackupEnabled();
    if (!mounted) return;
    setState(() => _localBackupEnabled = enabled);
    await _refreshLocalBackupPath();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final remote = ref.watch(remoteControlProvider);

    return DefaultTabController(
      length: AppSettingsTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          title: Text('Settings',
              style: GoogleFonts.bebasNeue(fontSize: 24, letterSpacing: 1.5)),
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
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Cloud'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _settingsList(_generalTab(settings, auth)),
            _settingsList(_accountTab(settings, auth)),
            _settingsList(_remoteTab(remote)),
            const CloudSyncScreen(embedded: true),
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

  List<Widget> _generalTab(AppSettings settings, AuthState auth) {
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
      const _SectionHeader(title: 'LOCAL BACKUP'),
      const SizedBox(height: 8),
      ..._localBackupSection(settings),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'UPDATES'),
      const SizedBox(height: 8),
      ..._updatesSection(settings, auth),
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
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.privacy_tip_outlined,
        title: 'Privacy Consent',
        subtitle: 'Review device key, policy version, and consent status',
        onTap: () => _showBetaConsentDetails(context),
      ),
    ];
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

  void _showBetaConsentDetails(BuildContext context) {
    final consent = ref.read(betaConsentProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Privacy Consent',
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
              label: 'Feedback notice',
              value: consent.acceptedPolicyVersion.isEmpty
                  ? betaPrivacyPolicyVersion
                  : consent.acceptedPolicyVersion,
            ),
            _ConsentDetailRow(
              label: 'Speech notice',
              value: consent.acceptedSpeechDisclosureVersion.isEmpty
                  ? betaSpeechDisclosureVersion
                  : consent.acceptedSpeechDisclosureVersion,
            ),
            _ConsentDetailRow(
              label: 'Cloud notice',
              value: consent.acceptedCloudDisclosureVersion.isEmpty
                  ? betaCloudDisclosureVersion
                  : consent.acceptedCloudDisclosureVersion,
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
              'deletion requests, then returns the app to the consent screen.',
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
          'Withdraw consent?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The app cannot be used without accepting the current feedback '
          'privacy notice, speech-to-text disclosure, and cloud storage '
          'disclosure. You can accept again from the consent screen.',
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
