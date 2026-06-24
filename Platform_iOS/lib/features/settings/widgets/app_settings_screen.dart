import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/providers/auth_provider.dart';
import '../../auth/services/account_backend_models.dart';
import '../../auth/widgets/login_screen.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../remote/services/remote_control_service.dart';
import '../../remote/widgets/remote_controller_screen.dart';
import '../../../platform/system/external_url_launcher.dart';
import '../providers/settings_provider.dart';
import '../services/settings_error_sanitizer.dart';
import '../services/update_check_service.dart';
import 'cloud_sync_screen.dart';

part 'app_settings_screen.account.dart';
part 'app_settings_screen.sections.dart';
part 'app_settings_screen.tiles.dart';

enum AppSettingsTab { general, account, remote, cloud }

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
  static const _tabs = [
    _SettingsTabSpec('General', Icons.tune_rounded),
    _SettingsTabSpec('Account', Icons.account_circle_outlined),
    _SettingsTabSpec('Remote', Icons.settings_remote_rounded),
    _SettingsTabSpec('Cloud', Icons.cloud_outlined),
  ];

  // Cache of resolved LAN URLs per remote profile so the tab shows/copies the
  // address other devices can actually reach (not localhost).
  final Map<String, String> _remoteLanUrls = {};

  // Update check state (GitHub Releases manifest). iOS can't self-install, so
  // the UI opens the release page on an available update.
  final UpdateCheckService _updateService = UpdateCheckService();
  UpdateCheckResult? _updateResult;
  bool _checkingForUpdate = false;

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    try {
      final result = await _updateService.check(channel: UpdateChannels.beta);
      if (!mounted) return;
      setState(() => _updateResult = result);
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  Future<void> _openUpdateDownload(String url) async {
    final opened = await ExternalUrlLauncher.openUrl(url);
    if (!opened) _showSnack('Could not open the release page.');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final remote = ref.read(remoteControlProvider);
      for (final profile in remote.controllerProfiles) {
        if (profile.isRunning) unawaited(_refreshRemoteUrl(profile.id));
      }
    });
  }

  /// Returns the best URL another device can use to reach [profileId]: the
  /// resolved LAN address when known, falling back to the loopback URL.
  String _remoteUrlFor(RemoteControlService remote, String profileId) {
    return _remoteLanUrls[profileId] ?? remote.remoteUrlForProfile(profileId);
  }

  Future<void> _refreshRemoteUrl(String profileId) async {
    final remote = ref.read(remoteControlProvider);
    try {
      final url = await remote.preferredUrlForProfile(profileId);
      if (!mounted) return;
      setState(() => _remoteLanUrls[profileId] = url);
    } catch (_) {
      // Network interface lookup can fail transiently; keep prior value.
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final screen = DefaultTabController(
      length: _tabs.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          title: Text(
            'Settings',
            style: GoogleFonts.bebasNeue(
              fontSize: 24,
              letterSpacing: 1.5,
              color: const Color(0xFFFFBF00),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: const Color(0xFFFFBF00),
            labelColor: const Color(0xFFFFBF00),
            unselectedLabelColor: Colors.white54,
            tabs: [
              for (final tab in _tabs)
                Tab(icon: Icon(tab.icon, size: 20), text: tab.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _settingsList(_buildGeneralTab()),
            _settingsList(_buildAccountTab()),
            _settingsList(_buildRemoteTab()),
            const CloudSyncScreen(embedded: true),
          ],
        ),
      ),
    );
    final media = MediaQuery.maybeOf(context);
    if (media == null) return screen;
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(settings.uiScale)),
      child: screen,
    );
  }

  Widget _settingsList(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: children,
    );
  }

  Future<void> _resetGuidedWalkthrough(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('iosFeedbackOnboardingVersionSeen');
    await prefs.remove('iosEditorSampleWalkthroughSeen');
    await prefs.remove('iosPresenterWalkthroughSeen');
    await prefs.remove('iosContentCreatorWalkthroughSeen');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All iPhone walkthrough steps will replay from lobby.'),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsTabSpec {
  final String label;
  final IconData icon;

  const _SettingsTabSpec(this.label, this.icon);
}
