import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'script_editor_screen.dart';
import '../../../core/security/secure_script_store.dart';
import '../../../core/widgets/stable_walkthrough_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_screen.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/services/deleted_scripts_service.dart';
import '../../settings/services/settings_error_sanitizer.dart';
import '../../settings/services/update_check_service.dart';
import '../../settings/services/update_download_service.dart';
import '../../settings/services/update_install_service.dart';
import '../../settings/widgets/app_settings_screen.dart';
import '../../settings/widgets/cloud_sync_screen.dart';
import '../providers/script_provider.dart';
import '../services/styling_service.dart';
import 'script_delete_dialog.dart';
import '../../../platform/system/external_url_launcher.dart';
import '../../../platform/file_import/platform_file_import.dart';

part 'script_gallery_screen.account_menu.dart';
part 'script_gallery_screen.deleted_scripts.dart';
part 'script_gallery_screen.history_sheet.dart';
part 'script_gallery_screen.premium_hub.dart';
part 'script_gallery_screen.recent_item.dart';
part 'script_gallery_screen.widgets.dart';
part 'script_gallery_screen.onboarding.dart';
part 'script_gallery_screen.onboarding_setup.dart';

class ScriptGalleryScreen extends ConsumerStatefulWidget {
  final Duration initialInputShieldDuration;

  const ScriptGalleryScreen({
    super.key,
    this.initialInputShieldDuration = Duration.zero,
  });

  @override
  ConsumerState<ScriptGalleryScreen> createState() =>
      _ScriptGalleryScreenState();
}

class _ScriptGalleryScreenState extends ConsumerState<ScriptGalleryScreen> {
  static bool _startupUpdateCheckRan = false;
  int _logoTaps = 0;
  Timer? _inputShieldTimer;
  bool _inputShielded = false;
  bool _recentSelectionMode = false;
  bool _macOnboardingVisible = false;
  bool _macOnboardingScheduled = false;
  int _macOnboardingStep = 0;
  final GlobalKey _walkthroughScriptActionsKey = GlobalKey();
  final GlobalKey _walkthroughRecentsKey = GlobalKey();
  final Set<String> _selectedRecentKeys = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialInputShieldDuration > Duration.zero) {
      _inputShielded = true;
      _inputShieldTimer = Timer(widget.initialInputShieldDuration, () {
        if (mounted) setState(() => _inputShielded = false);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeCheckForUpdatesOnStartup());
    });
  }

  @override
  void dispose() {
    _inputShieldTimer?.cancel();
    super.dispose();
  }

  void _setGalleryState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final hasProAccess = auth.hasPremiumAccess;

    void openPremiumHub() => _showPremiumHub(context, auth);

    void openRemoteSettings() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AppSettingsScreen(
              initialTab: AppSettingsTab.remote,
            ),
          ),
        );

    void openCloudSettings() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
        );
    final remoteSettingsAction =
        (Platform.isWindows || Platform.isMacOS) ? openRemoteSettings : null;
    final visibleRecents = _dedupedRecentMetadata(settings.recentScripts);
    _scheduleMacOnboardingIfNeeded(settings);

    return AbsorbPointer(
      absorbing: _inputShielded,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          toolbarHeight: 64,
          title: GestureDetector(
            onTap: () async {
              setState(() => _logoTaps++);
              if (_logoTaps >= 5) {
                setState(() => _logoTaps = 0);
                final settingsNotifier = ref.read(settingsProvider.notifier);
                await settingsNotifier.toggleDebugMode();
                if (!context.mounted) {
                  return;
                }
                final isNowDebug = ref.read(settingsProvider).debugMode;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('DEBUG MODE: ${isNowDebug ? 'ON' : 'OFF'}'),
                    backgroundColor:
                        isNowDebug ? Colors.green : Colors.grey[800],
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Text('AutoTeleprompter',
                style: GoogleFonts.bebasNeue(
                    letterSpacing: 1.5,
                    fontSize: 28,
                    color: const Color(0xFFFFBF00))),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (Platform.isWindows || Platform.isMacOS)
              _PremiumShortcutIcon(
                enabled: hasProAccess,
                tooltip: 'Local Remote Control',
                lockedTooltip: 'Connect a Pro account to use Remote Control',
                icon: Icons.wifi_tethering_rounded,
                onPressed: remoteSettingsAction ?? openPremiumHub,
                onLockedPressed: openPremiumHub,
              ),
            _PremiumShortcutIcon(
              enabled: hasProAccess,
              tooltip: 'Cloud Storage',
              lockedTooltip: 'Connect a Pro account to use online Cloud',
              icon: Icons.cloud_outlined,
              onPressed: openCloudSettings,
              onLockedPressed: openPremiumHub,
            ),
            IconButton(
              tooltip: 'Send Feedback',
              icon:
                  const Icon(Icons.bug_report_outlined, color: Colors.white54),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedbackReportScreen()),
              ),
            ),
            _AccountMenuButton(auth: auth),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white54),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppSettingsScreen(
                    initialTab: AppSettingsTab.general,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final displayName =
                          auth.isSignedIn ? settings.displayName : 'Guest';
                      final welcomeTitle = 'Welcome Back, $displayName.';
                      final welcome = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            welcomeTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ready for your next broadcast?',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 15),
                          ),
                        ],
                      );
                      final pro = _ProDashboard(
                        auth: auth,
                        compact: true,
                        onTap: openPremiumHub,
                        onOpenRemote: remoteSettingsAction,
                        onOpenCloud: openCloudSettings,
                        onLockedFeature: openPremiumHub,
                      );
                      final titlePainter = TextPainter(
                        text: TextSpan(
                          text: welcomeTitle,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();
                      final shouldStack =
                          constraints.maxWidth < titlePainter.width + 18 + 465;
                      if (shouldStack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            welcome,
                            const SizedBox(height: 12),
                            pro,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 6, child: welcome),
                          const SizedBox(width: 18),
                          Expanded(flex: 7, child: pro),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  KeyedSubtree(
                    key: _walkthroughScriptActionsKey,
                    child: Column(
                      children: [
                        _GalleryActionCard(
                          title: 'New Script',
                          subtitle: 'Start with a blank canvas',
                          icon: Icons.add_rounded,
                          color: const Color(0xFFFFBF00),
                          onTap: () {
                            LightweightDiagnostics.instance.record(
                              'gallery',
                              'new script action opened',
                            );
                            _showNewScriptDialog(context);
                          },
                        ),
                        const SizedBox(height: 12),
                        _GalleryActionCard(
                          title: 'Load Script',
                          subtitle:
                              'Import from ${PlatformFileImport.formatsLabel}',
                          icon: Icons.file_open_outlined,
                          color: Colors.white,
                          onTap: () {
                            LightweightDiagnostics.instance.record(
                              'gallery',
                              'load script action opened',
                            );
                            // v3.9.5.59: Sovereign Fluid Transition
                            // Immediately navigate to the editor shell; the editor will handle
                            // triggering the file picker over its amber loading screen,
                            // eliminating home-to-home flicker.
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ScriptEditorScreen(
                                  shouldAutoLoad: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 38),
                  KeyedSubtree(
                    key: _walkthroughRecentsKey,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Recent Activity',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (visibleRecents.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _recentSelectionMode =
                                            !_recentSelectionMode;
                                        _selectedRecentKeys.clear();
                                      });
                                    },
                                    child: Text(
                                      _recentSelectionMode
                                          ? 'cancel'
                                          : 'select',
                                      style: const TextStyle(
                                        color: Color(0xFFFFBF00),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (_recentSelectionMode &&
                                    visibleRecents.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedRecentKeys
                                          ..clear()
                                          ..addAll(
                                            visibleRecents.take(3).map((item) {
                                              final meta =
                                                  Map<String, dynamic>.from(
                                                jsonDecode(item),
                                              );
                                              return _recentGallerySelectionKey(
                                                meta,
                                              );
                                            }),
                                          );
                                      });
                                    },
                                    child: const Text(
                                      'select all',
                                      style: TextStyle(
                                        color: Color(0xFFFFBF00),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (_recentSelectionMode &&
                                    _selectedRecentKeys.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(
                                        () => _selectedRecentKeys.clear(),
                                      );
                                    },
                                    child: const Text(
                                      'clear all',
                                      style: TextStyle(
                                        color: Color(0xFFFFBF00),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (_recentSelectionMode &&
                                    _selectedRecentKeys.isNotEmpty)
                                  TextButton(
                                    onPressed: () =>
                                        _deleteSelectedRecentScripts(
                                      visibleRecents,
                                    ),
                                    child: Text(
                                      'delete ${_selectedRecentKeys.length}',
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (visibleRecents.length > 3)
                                  TextButton(
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        backgroundColor:
                                            const Color(0xFF0A0A0A),
                                        isScrollControlled: true,
                                        builder: (_) =>
                                            const _FullHistorySheet(),
                                      );
                                    },
                                    child: const Text('show more',
                                        style: TextStyle(
                                            color: Color(0xFFFFBF00),
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: visibleRecents.isEmpty
                              ? [const _EmptyStatePlaceholder()]
                              : visibleRecents.take(3).map((metaJson) {
                                  final meta = Map<String, dynamic>.from(
                                    jsonDecode(metaJson),
                                  );
                                  final selectionKey =
                                      _recentGallerySelectionKey(meta);
                                  return _ScriptListItem(
                                    title: meta['title'] ?? 'Untitled Script',
                                    date: meta['date'] ?? 'Imported',
                                    type: meta['type'] ?? 'FILE',
                                    fullText: meta['fullText'] ?? '',
                                    snippet: meta['snippet'],
                                    sessionId: meta['sessionId'],
                                    secureRecordId:
                                        meta[SecureScriptStore.recordIdKey],
                                    sourcePath: meta['sourcePath'],
                                    selectionMode: _recentSelectionMode,
                                    selected: _selectedRecentKeys
                                        .contains(selectionKey),
                                    onSelectionChanged: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedRecentKeys.add(selectionKey);
                                        } else {
                                          _selectedRecentKeys
                                              .remove(selectionKey);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                        ),
                      ],
                    ),
                  ),
                  _DeletedScriptsSection(enabled: hasProAccess),
                ],
              ),
            ),
            if (_macOnboardingVisible)
              _buildMacOnboardingOverlay(settings, hasProAccess),
          ],
        ),
      ),
    );
  }

  void _showNewScriptDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Production Title',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Broadcast V1',
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
              Navigator.pop(ctx);
              LightweightDiagnostics.instance.record(
                'gallery',
                'new script created',
                data: {'title': name.isEmpty ? 'New Script' : name},
              );
              ref.read(scriptProvider.notifier).clear();
              ref.read(settingsProvider.notifier).resetToDefaultAppearance();
              ref
                  .read(scriptProvider.notifier)
                  .loadText('', title: name.isEmpty ? 'New Script' : name);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ScriptEditorScreen()));
            },
            child: const Text('Start Producing',
                style: TextStyle(
                    color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedRecentScripts(List<String> visibleRecents) async {
    final selected = <Map<String, dynamic>>[];
    for (final item in visibleRecents) {
      try {
        final meta = Map<String, dynamic>.from(jsonDecode(item));
        if (_selectedRecentKeys.contains(_recentGallerySelectionKey(meta))) {
          selected.add(meta);
        }
      } catch (_) {
        // Ignore malformed history entries. They are already hidden elsewhere.
      }
    }
    if (selected.isEmpty) return;
    final choice = await showScriptDeleteDialog(
      context,
      title: '${selected.length} selected scripts',
      sourcePaths: _recentGallerySourcePaths(selected),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _selectedRecentKeys.clear();
      _recentSelectionMode = false;
    });
    try {
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.deleteRecentScripts(selected);
      var deletedSourceCount = 0;
      if (choice.deleteSourceFile) {
        deletedSourceCount = await _deleteRecentGallerySourceFiles(selected);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedSourceCount > 0
                ? 'Deleted ${selected.length} scripts and $deletedSourceCount source files.'
                : 'Deleted ${selected.length} scripts.',
          ),
        ),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'gallery.deleteSelectedRecentScripts',
        data: {'count': selected.length},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete selected scripts.')),
      );
    }
  }

  void _showPremiumHub(BuildContext context, AuthState auth) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumHubSheet(
        auth: auth,
        onOpenRemote: (Platform.isWindows || Platform.isMacOS)
            ? () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AppSettingsScreen(
                      initialTab: AppSettingsTab.remote,
                    ),
                  ),
                );
              }
            : null,
        onOpenCloud: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
          );
        },
        onSignIn: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        },
        onOpenAccount: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AppSettingsScreen(
                initialTab: AppSettingsTab.account,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _maybeCheckForUpdatesOnStartup() async {
    if (_startupUpdateCheckRan) return;
    _startupUpdateCheckRan = true;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final startupUpdates = await _readStartupUpdatePreferences();
    if (!mounted || !startupUpdates.checkUpdatesOnStartup) return;
    final auth = ref.read(authProvider);
    final adminUpdateConfigured =
        autoTeleprompterAdminEmail.trim().isNotEmpty &&
            autoTeleprompterAdminCodeHash.trim().isNotEmpty;
    final canUseInternalUpdates =
        auth.isAdmin && (auth.accountBackendEnabled || adminUpdateConfigured);
    final channel =
        startupUpdates.updateChannel == AppSettings.updateChannelInternal &&
                !canUseInternalUpdates
            ? AppSettings.updateChannelStable
            : startupUpdates.updateChannel;
    final result = await UpdateCheckService().check(
      channel: channel,
    );
    if (!mounted || result.status != UpdateCheckStatus.updateAvailable) {
      return;
    }
    final installUnavailableMessage = result.installUnavailableMessage;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Update available',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${result.message}\n\n'
          'Current: ${result.currentVersion}\n'
          'Latest: ${result.latestVersion ?? 'Unknown'}'
          '${installUnavailableMessage == null ? '' : '\n\n$installUnavailableMessage'}',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          if (result.canInstallOnCurrentPlatform)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(_downloadStartupUpdate(result));
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Install update'),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadStartupUpdate(UpdateCheckResult result) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading update package...')),
    );
    try {
      final file = await UpdateDownloadService().download(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Installing update. AutoTeleprompter will restart.'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await UpdateInstallService().installDownloadedUpdate(file, result);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'gallery.downloadStartupUpdate',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Update install failed: ${sanitizeSettingsErrorForUser(error)}',
          ),
        ),
      );
    }
  }

  Future<_StartupUpdatePreferences> _readStartupUpdatePreferences() async {
    final providerSettings = ref.read(settingsProvider);
    final prefs = await SharedPreferences.getInstance();
    final savedChannel = prefs.getString('updateChannel');
    final channel = switch (savedChannel) {
      AppSettings.updateChannelStable => AppSettings.updateChannelStable,
      AppSettings.updateChannelBeta => AppSettings.updateChannelBeta,
      AppSettings.updateChannelInternal => AppSettings.updateChannelInternal,
      _ => providerSettings.updateChannel,
    };
    return _StartupUpdatePreferences(
      updateChannel: channel,
      checkUpdatesOnStartup: prefs.getBool('checkUpdatesOnStartup') ??
          providerSettings.checkUpdatesOnStartup,
    );
  }
}

class _StartupUpdatePreferences {
  final String updateChannel;
  final bool checkUpdatesOnStartup;

  const _StartupUpdatePreferences({
    required this.updateChannel,
    required this.checkUpdatesOnStartup,
  });
}

// Gallery remote entry routes through the Pro hub and Settings Remote tab.
