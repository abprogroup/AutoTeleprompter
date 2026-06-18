import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../../../platform/camera/macos_camera_controller.dart';
import '../../../platform/stt/abstract_stt_service.dart';
import '../../../platform/system/external_url_launcher.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/services/account_backend_models.dart';
import '../../auth/widgets/login_screen.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../feedback/providers/beta_consent_provider.dart';
import '../../feedback/widgets/beta_consent_gate.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../remote/services/remote_control_service.dart';
import '../../teleprompter/providers/teleprompter_provider.dart';
import '../providers/settings_provider.dart';
import '../services/update_check_service.dart';
import '../services/update_download_service.dart';
import '../services/update_install_service.dart';
import 'cloud_sync_screen.dart';

part 'app_settings_screen.tiles.dart';
part 'app_settings_screen.account_remote.dart';
part 'app_settings_screen.account_subscription.dart';
part 'app_settings_screen.account_danger.dart';
part 'app_settings_screen.remote_profiles.dart';
part 'app_settings_screen.media_defaults.dart';
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
  bool _remoteBusy = false;
  String? _remoteUrl;
  String? _remoteUrlProfileId;
  String? _remoteError;
  String? _selectedRemoteProfileId;
  bool _checkingUpdates = false;
  bool _downloadingUpdate = false;

  void _setCheckingUpdates(bool value) {
    if (mounted) setState(() => _checkingUpdates = value);
  }

  void _setDownloadingUpdate(bool value) {
    if (mounted) setState(() => _downloadingUpdate = value);
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRemoteUrl());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final remote = (Platform.isWindows || Platform.isMacOS)
        ? ref.watch(remoteControlProvider)
        : null;

    final media = MediaQuery.maybeOf(context);
    final screen = DefaultTabController(
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
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Cloud'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _settingsList(_generalTab(settings)),
            _settingsList(_accountTab(settings, auth)),
            _settingsList(_remoteTab(remote)),
            const CloudSyncScreen(embedded: true),
          ],
        ),
      ),
    );
    if (media == null) return screen;
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(settings.uiScale)),
      child: screen,
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
      const _SectionHeader(title: 'IMPORT DEFAULTS'),
      const SizedBox(height: 8),
      _SettingsChoiceTile<String>(
        icon: Icons.file_open_outlined,
        title: 'Imported script colors',
        subtitle:
            settings.importColorMode == AppSettings.importColorModeDocument
                ? 'Keep document-style light page and dark text after import'
                : 'Convert imported scripts to prompter contrast after import',
        value: settings.importColorMode,
        choices: const [
          _SettingsChoice(
            label: 'Prompter contrast',
            value: AppSettings.importColorModePrompter,
          ),
          _SettingsChoice(
            label: 'Document original',
            value: AppSettings.importColorModeDocument,
          ),
        ],
        onChanged: ref.read(settingsProvider.notifier).setImportColorMode,
      ),
      const SizedBox(height: 22),
      ..._mediaDefaultsSection(settings),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'STORAGE'),
      const SizedBox(height: 8),
      _SettingsActionsTile(
        icon: Icons.folder_outlined,
        title: 'Recording folder',
        subtitle: _recordingFolderLabel(settings),
        actions: [
          _SettingsAction(
            icon: Icons.folder_open_outlined,
            label: 'Choose folder',
            onPressed: _chooseRecordingFolder,
          ),
          _SettingsAction(
            icon: Icons.open_in_new_rounded,
            label: 'Open folder',
            onPressed: () => _openRecordingFolder(settings),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _SettingsActionsTile(
        icon: Icons.storage_outlined,
        title: 'App data folder',
        subtitle: 'Open local diagnostics, settings, and app support data',
        actions: [
          _SettingsAction(
            icon: Icons.open_in_new_rounded,
            label: 'Open app data',
            onPressed: _openAppDataFolder,
          ),
        ],
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'PERFORMANCE'),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.speed_outlined,
        title: 'Reduce motion',
        subtitle: settings.reduceMotion
            ? 'Nonessential animations are reduced for a steadier live reading experience'
            : 'Uses full UI animations; turn on to reduce transitions during live work',
        value: settings.reduceMotion,
        onChanged: ref.read(settingsProvider.notifier).setReduceMotion,
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'ACCESSIBILITY'),
      const SizedBox(height: 8),
      _SettingsSliderTile(
        icon: Icons.format_size_outlined,
        title: 'Interface text scale',
        subtitle: 'Affects this Settings screen, not script metadata',
        value: settings.uiScale,
        min: 0.90,
        max: 1.25,
        divisions: 7,
        valueLabel: '${(settings.uiScale * 100).round()}%',
        onChanged: ref.read(settingsProvider.notifier).setUiScale,
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'UPDATES / CHANNEL'),
      const SizedBox(height: 8),
      ..._updatesSection(settings),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'LANGUAGE'),
      const SizedBox(height: 8),
      _SettingsChoiceTile<String>(
        icon: Icons.translate_outlined,
        title: 'Speech recognition language',
        subtitle: _languageModeDescription(settings.languageMode),
        value: settings.languageMode,
        choices: const [
          _SettingsChoice(
            label: 'Auto',
            value: AppSettings.languageModeAuto,
          ),
          _SettingsChoice(
            label: 'Hebrew',
            value: AppSettings.languageModeHebrew,
          ),
          _SettingsChoice(
            label: 'English',
            value: AppSettings.languageModeEnglish,
          ),
        ],
        onChanged: ref.read(settingsProvider.notifier).setLanguageMode,
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'FEEDBACK'),
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
      const SizedBox(height: 22),
      const _SectionHeader(title: 'ADVANCED DIAGNOSTICS'),
      const SizedBox(height: 8),
      if (Platform.isWindows) ...[
        _SettingsTile(
          icon: Icons.cleaning_services_outlined,
          title: 'Repair old microphone permission setting',
          subtitle: 'Removes an older Windows speech permission workaround if '
              'this app saved it before the local-process fix.',
          onTap: _clearLegacyWebView2EnvVar,
        ),
        const SizedBox(height: 8),
      ],
      _SettingsSwitchTile(
        icon: Icons.bug_report_outlined,
        title: 'Debug Mode',
        subtitle: settings.debugMode
            ? 'Detailed logs and trace tools are visible'
            : 'Normal mode: heavy debug traces stay off',
        value: settings.debugMode,
        onChanged: (_) => ref.read(settingsProvider.notifier).toggleDebugMode(),
      ),
    ];
  }

  String _recordingFolderLabel(AppSettings settings) {
    return settings.contentCreatorRecordingFolder.isEmpty
        ? r'Videos\AutoTeleprompter'
        : settings.contentCreatorRecordingFolder;
  }

  String _languageModeDescription(String mode) {
    switch (mode) {
      case AppSettings.languageModeHebrew:
        return 'Prefer Hebrew speech recognition when starting sessions';
      case AppSettings.languageModeEnglish:
        return 'Prefer English speech recognition when starting sessions';
      default:
        return 'Detect script language automatically when possible';
    }
  }

  Future<String> _defaultRecordingFolderPath() async {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        return '$home/Movies/AutoTeleprompter';
      }
      final documents = await getApplicationDocumentsDirectory();
      return '${documents.path}/AutoTeleprompter';
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return '$userProfile\\Videos\\AutoTeleprompter';
    }
    final documents = await getApplicationDocumentsDirectory();
    return '${documents.path}\\AutoTeleprompter';
  }

  Future<void> _chooseRecordingFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose AutoTeleprompter recording folder',
    );
    if (path == null || path.trim().isEmpty) return;
    await ref.read(settingsProvider.notifier).setContentCreatorRecordingFolder(
          path,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recording folder set to $path')),
    );
  }

  Future<void> _openRecordingFolder(AppSettings settings) async {
    final path = settings.contentCreatorRecordingFolder.isEmpty
        ? await _defaultRecordingFolderPath()
        : settings.contentCreatorRecordingFolder;
    await Directory(path).create(recursive: true);
    await _openFolder(path, source: 'settings.openRecordingFolder');
  }

  Future<void> _openAppDataFolder() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    await _openFolder(directory.path, source: 'settings.openAppDataFolder');
  }

  Future<void> _openFolder(String path, {required String source}) async {
    try {
      final opened = await ExternalUrlLauncher.openPath(path);
      if (opened) return;
      throw StateError('External launcher reported failure for $path');
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: source,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder could not be opened.')),
      );
    }
  }

  List<Widget> _remoteTab(RemoteControlService? remote) {
    if ((!Platform.isWindows && !Platform.isMacOS) || remote == null) {
      return const [
        _SectionHeader(title: 'REMOTE CONTROL'),
        SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.settings_remote_outlined,
          title: 'Local Remote Control',
          subtitle: 'Available on Windows desktop',
        ),
      ];
    }
    final profiles = remote.controllerProfiles;
    final selectedProfile = _selectedRemoteProfile(remote, profiles);
    final selectedUrl = _remoteUrlProfileId == selectedProfile.id
        ? _remoteUrl ?? remote.remoteUrlForProfile(selectedProfile.id)
        : remote.remoteUrlForProfile(selectedProfile.id);

    return [
      const _SectionHeader(title: 'REMOTE CONTROL'),
      const SizedBox(height: 8),
      _RemoteControlTile(
        title: selectedProfile.name,
        isRunning: selectedProfile.isRunning,
        isBusy: _remoteBusy,
        url: selectedUrl,
        pairingPin: selectedProfile.pairingPin,
        connectedClientCount: selectedProfile.connectedClientCount,
        sessionExpiresAt: selectedProfile.sessionTokenExpiresAt,
        error: _remoteError,
        onStart: () => _startRemote(selectedProfile.id),
        onStop: () => _stopRemote(selectedProfile.id),
        onRename: () => _renameRemoteProfile(selectedProfile),
        onRevoke: () => _revokeRemoteProfile(selectedProfile),
        onCopy: () => _copyRemoteProfileUrl(selectedProfile),
        onOpen: () => _openRemoteProfileUrl(selectedProfile),
      ),
      const SizedBox(height: 8),
      _RemoteProfilesTile(
        profiles: profiles,
        selectedProfileId: selectedProfile.id,
        onSelect: _selectRemoteProfile,
        onAdd: _addRemoteProfile,
        onRename: _renameRemoteProfile,
        onStart: _startRemoteProfile,
        onStop: _stopRemoteProfile,
        onRemove: _removeRemoteProfile,
        onRevoke: _revokeRemoteProfile,
        onCopy: _copyRemoteProfileUrl,
        onOpen: _openRemoteProfileUrl,
      ),
    ];
  }

  RemoteControllerProfile _selectedRemoteProfile(
    RemoteControlService remote,
    List<RemoteControllerProfile> profiles,
  ) {
    if (profiles.isEmpty) {
      remote.createControllerProfile();
      return remote.controllerProfiles.first;
    }
    final selectedId = _selectedRemoteProfileId;
    if (selectedId != null) {
      for (final profile in profiles) {
        if (profile.id == selectedId) return profile;
      }
    }
    final fallbackId = remote.hasControllerProfile(remote.defaultProfileId)
        ? remote.defaultProfileId
        : profiles.first.id;
    _selectedRemoteProfileId = fallbackId;
    return profiles.firstWhere(
      (profile) => profile.id == fallbackId,
      orElse: () => profiles.first,
    );
  }

  void _selectRemoteProfile(RemoteControllerProfile profile) {
    _setSelectedRemoteProfile(profile.id, clearError: true);
    unawaited(_refreshRemoteUrl(profile.id));
  }

  void _setSelectedRemoteProfile(String? profileId, {bool clearError = false}) {
    setState(() {
      _selectedRemoteProfileId = profileId;
      _remoteUrl = null;
      _remoteUrlProfileId = null;
      if (clearError) _remoteError = null;
    });
  }

  Future<void> _refreshRemoteUrl([String? profileId]) async {
    if (!mounted || (!Platform.isWindows && !Platform.isMacOS)) return;
    final remote = ref.read(remoteControlProvider);
    final selectedId = profileId ??
        _selectedRemoteProfileId ??
        (remote.controllerProfiles.isEmpty
            ? remote.defaultProfileId
            : remote.controllerProfiles.first.id);
    final selectedProfile = remote.controllerProfiles.firstWhere(
      (profile) => profile.id == selectedId,
      orElse: () => remote.controllerProfiles.first,
    );
    final url = selectedProfile.isRunning
        ? await remote.preferredUrlForProfile(selectedId)
        : remote.remoteUrlForProfile(selectedId);
    if (!mounted) return;
    setState(() {
      _remoteUrl = url;
      _remoteUrlProfileId = selectedId;
      _remoteError = null;
    });
  }

  Future<void> _startRemote([String? profileId]) async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    final remote = ref.read(remoteControlProvider);
    final selectedId =
        profileId ?? _selectedRemoteProfileId ?? remote.defaultProfileId;
    try {
      await remote.startControllerProfile(selectedId);
      final url = await remote.preferredUrlForProfile(selectedId);
      if (!mounted) return;
      setState(() {
        _remoteUrl = url;
        _remoteUrlProfileId = selectedId;
      });
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.remoteStart',
      );
      if (!mounted) return;
      setState(() {
        _remoteError = 'Remote control could not start. Ports 8080-8090 may '
            'already be in use.';
      });
    } finally {
      if (mounted) setState(() => _remoteBusy = false);
    }
  }

  Future<void> _stopRemote([String? profileId]) async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    final remote = ref.read(remoteControlProvider);
    final selectedId =
        profileId ?? _selectedRemoteProfileId ?? remote.defaultProfileId;
    await remote.stopControllerProfile(selectedId);
    if (!mounted) return;
    setState(() {
      _remoteBusy = false;
      _remoteUrl = remote.remoteUrlForProfile(selectedId);
      _remoteUrlProfileId = selectedId;
    });
  }

  Future<void> _clearLegacyWebView2EnvVar() async {
    ProcessResult result;
    try {
      result = await Process.run('reg', [
        'delete',
        r'HKCU\Environment',
        '/v',
        'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
        '/f',
      ]);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.webview2EnvCleanup',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Old microphone permission setting could not be checked.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final deleted = result.exitCode == 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Old microphone permission setting cleared.'
              : 'No old microphone permission setting was found.',
        ),
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
          'privacy notice and speech-to-text disclosure. You can accept again '
          'from the consent screen.',
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
