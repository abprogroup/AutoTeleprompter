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
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_screen.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/widgets/app_settings_screen.dart';
import '../../settings/widgets/cloud_sync_screen.dart';
import '../providers/script_provider.dart';
import '../services/styling_service.dart';
import '../../../platform/file_import/platform_file_import.dart';

part 'script_gallery_screen.account_menu.dart';
part 'script_gallery_screen.history_sheet.dart';
part 'script_gallery_screen.premium_hub.dart';
part 'script_gallery_screen.recent_item.dart';
part 'script_gallery_screen.widgets.dart';

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
  int _logoTaps = 0;
  Timer? _inputShieldTimer;
  bool _inputShielded = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialInputShieldDuration > Duration.zero) {
      _inputShielded = true;
      _inputShieldTimer = Timer(widget.initialInputShieldDuration, () {
        if (mounted) setState(() => _inputShielded = false);
      });
    }
  }

  @override
  void dispose() {
    _inputShieldTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final hasProAccess = auth.isPro || auth.isAdmin;

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
    final remoteSettingsAction = Platform.isWindows ? openRemoteSettings : null;

    return AbsorbPointer(
      absorbing: _inputShielded,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          toolbarHeight: 80,
          title: GestureDetector(
            onTap: () async {
              setState(() => _logoTaps++);
              if (_logoTaps >= 5) {
                setState(() => _logoTaps = 0);
                await ref.read(settingsProvider.notifier).toggleDebugMode();
                final isNowDebug = ref.read(settingsProvider).debugMode;
                if (!context.mounted) {
                  return;
                }
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
            if (Platform.isWindows)
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
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final welcome = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back, ${settings.displayName}.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ready for your next broadcast?',
                        style: TextStyle(color: Colors.white54, fontSize: 15),
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
                  if (constraints.maxWidth < 760) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        welcome,
                        const SizedBox(height: 14),
                        pro,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: welcome),
                      const SizedBox(width: 18),
                      SizedBox(width: 390, child: pro),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
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
                subtitle: 'Import from ${PlatformFileImport.formatsLabel}',
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
                        builder: (_) =>
                            const ScriptEditorScreen(shouldAutoLoad: true)),
                  );
                },
              ),
              const SizedBox(height: 38),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Activity',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  if (settings.recentScripts.length > 3)
                    TextButton(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: const Color(0xFF0A0A0A),
                          isScrollControlled: true,
                          builder: (_) => const _FullHistorySheet(),
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
              const SizedBox(height: 12),
              Column(
                children: settings.recentScripts.isEmpty
                    ? [const _EmptyStatePlaceholder()]
                    : settings.recentScripts.take(3).map((metaJson) {
                        final meta = jsonDecode(metaJson);
                        return _ScriptListItem(
                          title: meta['title'] ?? 'Untitled Script',
                          date: meta['date'] ?? 'Imported',
                          type: meta['type'] ?? 'FILE',
                          fullText: meta['fullText'] ?? '',
                          snippet: meta['snippet'],
                          sessionId: meta['sessionId'],
                          secureRecordId: meta[SecureScriptStore.recordIdKey],
                        );
                      }).toList(),
              ),
            ],
          ),
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

  void _showPremiumHub(BuildContext context, AuthState auth) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PremiumHubSheet(
        auth: auth,
        onOpenRemote: Platform.isWindows
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
}

// Gallery remote status is now restored through RemoteStatusCard.
