import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../feedback/providers/beta_consent_provider.dart';
import '../../feedback/widgets/beta_consent_gate.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../remote/services/remote_control_service.dart';
import '../../teleprompter/widgets/teleprompter_screen.dart';
import '../providers/settings_provider.dart';
import 'cloud_sync_screen.dart';

part 'app_settings_screen.tiles.dart';
part 'app_settings_screen.content_creator.dart';

enum AppSettingsTab {
  general,
  account,
  remote,
  editor,
  present,
  contentCreator
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
              Tab(
                  icon: Icon(Icons.video_camera_front_outlined),
                  text: 'Creator'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _settingsList(_generalTab(settings)),
            _settingsList(_accountTab(settings)),
            _settingsList(_remoteTab(remote)),
            _settingsList(_editorTab(settings)),
            _settingsList(_presentTab(settings)),
            _settingsList(_contentCreatorTab(settings)),
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
      const SizedBox(height: 22),
      const _SectionHeader(title: 'ADVANCED DIAGNOSTICS'),
      const SizedBox(height: 8),
      if (Platform.isWindows) ...[
        _SettingsTile(
          icon: Icons.cleaning_services_outlined,
          title: 'Repair old microphone permission setting',
          subtitle: 'Removes an older Windows speech permission workaround if '
              'this beta saved it before the local-process fix.',
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
        pairingPin: remote.pairingPin,
        error: _remoteError,
        onStart: _startRemote,
        onStop: _stopRemote,
        onCopy: _copyRemoteUrl,
        onOpen: _openRemoteUrl,
      ),
    ];
  }

  List<Widget> _editorTab(AppSettings settings) {
    return [
      const _SectionHeader(title: 'EDITOR DEFAULTS'),
      const SizedBox(height: 8),
      _SettingsControlTile(
        icon: Icons.format_align_center_rounded,
        title: 'Default editor alignment',
        subtitle: 'Used when new or imported text has no explicit alignment',
        children: [
          _SettingsChipGroup<String>(
            selected: settings.textAlign,
            values: const ['left', 'center', 'right'],
            labelFor: (value) => switch (value) {
              'left' => 'Left',
              'right' => 'Right',
              _ => 'Center',
            },
            onSelected: ref.read(settingsProvider.notifier).setTextAlign,
          ),
        ],
      ),
      const SizedBox(height: 8),
      _SettingsSliderTile(
        icon: Icons.format_size_rounded,
        title: 'Editor font size',
        subtitle: 'Shared with Present mode and saved with script metadata',
        value: settings.fontSize,
        displayValue: settings.fontSize.round().toString(),
        min: 14,
        max: 120,
        divisions: 53,
        onChanged: ref.read(settingsProvider.notifier).setFontSize,
      ),
      const SizedBox(height: 8),
      _SettingsSliderTile(
        icon: Icons.format_line_spacing_rounded,
        title: 'Line spacing',
        subtitle: 'Controls spacing while editing and presenting',
        value: settings.lineSpacing,
        displayValue: settings.lineSpacing.toStringAsFixed(2),
        min: 1.0,
        max: 2.5,
        divisions: 30,
        onChanged: ref.read(settingsProvider.notifier).setLineSpacing,
      ),
      const SizedBox(height: 8),
      const _SettingsTile(
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
      _LanguageModeTile(
        value: settings.languageMode,
        onChanged: (mode) =>
            ref.read(settingsProvider.notifier).setLanguageMode(mode),
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
      const SizedBox(height: 18),
      const _SectionHeader(title: 'SESSION CONTROL'),
      const SizedBox(height: 8),
      _SettingsControlTile(
        icon: Icons.swap_vert_rounded,
        title: 'Scroll Mode',
        subtitle: 'Choose speech recognition or fixed manual speed',
        children: [
          _SettingsChipGroup<String>(
            selected: settings.scrollMode,
            values: const ['auto', 'manual'],
            labelFor: (value) =>
                value == 'manual' ? 'Manual Speed' : 'Speech Auto',
            onSelected: ref.read(settingsProvider.notifier).setScrollMode,
          ),
        ],
      ),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.pan_tool_alt_outlined,
        title: 'Allow manual scrolling while listening',
        subtitle: settings.scrollMode == 'manual'
            ? 'Manual Speed mode is not listening, so this is not used'
            : 'A technician can wheel or drag during active speech recognition',
        value: settings.allowScrollDuringActiveSession,
        enabled: settings.scrollMode != 'manual',
        onChanged: ref
            .read(settingsProvider.notifier)
            .setAllowScrollDuringActiveSession,
      ),
      const SizedBox(height: 8),
      _SettingsControlTile(
        icon: Icons.speed_rounded,
        title: 'Manual speed bar position',
        subtitle: 'Where the speed control appears in Manual Speed mode',
        children: [
          _SettingsChipGroup<String>(
            selected: settings.manualScrollBarPlacement,
            values: const [
              AppSettings.manualScrollBarBottom,
              AppSettings.manualScrollBarTop,
              AppSettings.manualScrollBarLeft,
              AppSettings.manualScrollBarRight,
            ],
            labelFor: (value) => switch (value) {
              AppSettings.manualScrollBarTop => 'Top',
              AppSettings.manualScrollBarLeft => 'Left',
              AppSettings.manualScrollBarRight => 'Right',
              _ => 'Bottom',
            },
            onSelected:
                ref.read(settingsProvider.notifier).setManualScrollBarPlacement,
          ),
        ],
      ),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.visibility_outlined,
        title: 'Visible skip assist',
        subtitle: 'Speech recognition may relock only to visible words',
        value: settings.sttVisibleSkipEnabled,
        onChanged: ref.read(settingsProvider.notifier).setSttVisibleSkipEnabled,
      ),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.rule_folder_outlined,
        title: 'Strict bullet/header mode',
        subtitle: 'Use stricter recognition around bullet-like script starts',
        value: settings.sttStrictBulletMode,
        onChanged: ref.read(settingsProvider.notifier).setSttStrictBulletMode,
      ),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.tune_outlined,
        title: 'Manual speech-to-text profile',
        subtitle: 'Use your tuned recognition thresholds',
        value: settings.sttManualProfileEnabled,
        onChanged:
            ref.read(settingsProvider.notifier).setSttManualProfileEnabled,
      ),
      const SizedBox(height: 18),
      const _SectionHeader(title: 'PROMPTER DISPLAY'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.display_settings_outlined,
        title: 'Typography, colors, fade, mirror, and rotation',
        subtitle: _presentDisplaySummary(settings),
        onTap: _showPresenterSettingsPanel,
      ),
    ];
  }

  String _presentDisplaySummary(AppSettings settings) {
    final pieces = <String>[
      'Font ${settings.fontSize.round()}',
      '${settings.flipRotation} deg',
      'Fade ${(settings.readFadeIntensity * 100).round()}%',
    ];
    final mirror = <String>[];
    if (settings.mirrorHorizontal) mirror.add('H');
    if (settings.mirrorVertical) mirror.add('V');
    if (mirror.isNotEmpty) pieces.add('Mirror ${mirror.join('+')}');
    return pieces.join(' | ');
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
    try {
      await Process.run('cmd', ['/c', 'start', url]);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.remoteOpenUrl',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remote URL could not be opened.')),
      );
    }
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
              Text('Legacy WebView2 permission flag could not be checked.'),
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
              ? 'Legacy WebView2 permission flag cleared.'
              : 'No legacy WebView2 permission flag was found.',
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
