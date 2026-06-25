import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'script_editor_screen.dart';
import 'script_gallery_premium_panel.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_screen.dart';
import '../../feedback/widgets/feedback_report_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/widgets/app_settings_screen.dart';
import '../../settings/widgets/cloud_sync_screen.dart';
import '../providers/script_provider.dart';
import '../../../core/security/secure_script_store.dart';
import '../../../core/services/styling_service.dart';
import '../../../core/widgets/stable_walkthrough_overlay.dart';
import '../../../platform/file_import/platform_file_import.dart';

part 'script_gallery_screen.onboarding.dart';
part 'script_gallery_screen.recent_item.dart';

class ScriptGalleryScreen extends ConsumerStatefulWidget {
  const ScriptGalleryScreen({super.key});

  @override
  ConsumerState<ScriptGalleryScreen> createState() =>
      _ScriptGalleryScreenState();
}

class _ScriptGalleryScreenState extends ConsumerState<ScriptGalleryScreen> {
  int _logoTaps = 0;
  final GlobalKey _walkthroughNewScriptKey = GlobalKey();
  final GlobalKey _walkthroughLoadScriptKey = GlobalKey();
  final GlobalKey _walkthroughRecentsKey = GlobalKey();
  bool _iosOnboardingVisible = false;
  bool _iosOnboardingScheduled = false;
  int _iosOnboardingStep = 0;

  void _setGalleryState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final compactPhone = MediaQuery.sizeOf(context).width < 430;
    _scheduleIosOnboardingIfNeeded();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        toolbarHeight: compactPhone ? 72 : 80,
        titleSpacing: compactPhone ? 12 : null,
        title: GestureDetector(
          onTap: () async {
            setState(() => _logoTaps++);
            if (_logoTaps >= 5) {
              setState(() => _logoTaps = 0);
              final settingsNotifier = ref.read(settingsProvider.notifier);
              await settingsNotifier.toggleDebugMode();
              if (context.mounted) {
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
            }
          },
          child: Text(
            'AutoTeleprompter',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.bebasNeue(
              letterSpacing: 1.5,
              fontSize: compactPhone ? 25 : 28,
              color: const Color(0xFFFFBF00),
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _GalleryShortcutButton(
            tooltip: 'Feedback',
            icon: Icons.bug_report_outlined,
            compact: compactPhone,
            onPressed: () => _openFeedback(context),
          ),
          _GalleryShortcutButton(
            tooltip: 'Remote',
            icon: Icons.settings_remote_outlined,
            compact: compactPhone,
            onPressed: () => _openRemote(context, auth),
          ),
          _GalleryShortcutButton(
            tooltip: 'Cloud',
            icon: Icons.cloud_outlined,
            compact: compactPhone,
            onPressed: () => _openCloud(context),
          ),
          _GalleryShortcutButton(
            tooltip: auth.isSignedIn ? 'Account' : 'Sign in',
            icon: auth.isSignedIn
                ? Icons.account_circle_outlined
                : Icons.login_rounded,
            compact: compactPhone,
            onPressed: () => _openAccount(context),
          ),
          _GalleryShortcutButton(
            tooltip: 'Settings',
            icon: Icons.settings_outlined,
            compact: compactPhone,
            onPressed: () => _openSettings(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.all(compactPhone ? 18 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome Back, ${settings.displayName}.',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Ready for your next broadcast?',
                    style: TextStyle(color: Colors.white54, fontSize: 15)),
                const SizedBox(height: 24),
                ScriptGalleryPremiumPanel(
                  auth: auth,
                  onSignIn: () => _openAccount(context),
                  onOpenCloud: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
                  ),
                  onLogout: () async {
                    await ref.read(authProvider.notifier).logout();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signed out.')),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    KeyedSubtree(
                      key: _walkthroughNewScriptKey,
                      child: _GalleryActionCard(
                        title: 'New Script',
                        subtitle: 'Start with a blank canvas',
                        icon: Icons.add_rounded,
                        color: const Color(0xFFFFBF00),
                        onTap: () => _showNewScriptDialog(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: _walkthroughLoadScriptKey,
                      child: _GalleryActionCard(
                        title: 'Load Script',
                        subtitle: 'Import ${PlatformFileImport.formatsLabel}',
                        icon: Icons.file_open_outlined,
                        color: Colors.white,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ScriptEditorScreen(
                                    shouldAutoLoad: true)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
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
                KeyedSubtree(
                  key: _walkthroughRecentsKey,
                  child: Column(
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
                              secureRecordId:
                                  meta[SecureScriptStore.recordIdKey],
                            );
                          }).toList(),
                  ),
                ),
              ],
            ),
          ),
          if (_iosOnboardingVisible)
            _buildIosOnboardingOverlay(auth.hasPremiumAccess),
        ],
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

  void _openFeedback(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FeedbackReportScreen()),
    );
  }

  void _openCloud(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
    );
  }

  void _openRemote(BuildContext context, AuthState auth) {
    if (!auth.hasPremiumAccess) {
      _openAccount(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const AppSettingsScreen(initialTab: AppSettingsTab.remote),
      ),
    );
  }

  void _openAccount(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(initialPasswordMode: true),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
      ).then((_) {
        // The walkthrough "seen" flag may have been reset in Settings. The
        // lobby stays mounted while Settings is on top, so re-check on return
        // to replay the guide without needing an app restart.
        if (mounted) _scheduleIosOnboardingIfNeeded();
      }),
    );
  }
}

// Premium account state is owned by ScriptGalleryPremiumPanel.

class _GalleryShortcutButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool compact;
  final VoidCallback onPressed;

  const _GalleryShortcutButton({
    required this.tooltip,
    required this.icon,
    this.compact = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 40.0;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.all(compact ? 6 : 8),
      icon: Icon(icon, color: Colors.white60, size: compact ? 22 : 24),
      onPressed: onPressed,
    );
  }
}

class _FullHistorySheet extends ConsumerWidget {
  const _FullHistorySheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
          color: Color(0xFF0A0A0A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Complete History',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: Consumer(builder: (context, ref, _) {
              final scripts = ref.watch(settingsProvider).recentScripts;
              return ListView.builder(
                cacheExtent: 1000,
                itemCount: scripts.length,
                itemBuilder: (ctx, idx) {
                  final meta = jsonDecode(scripts[idx]);
                  return _ScriptListItem(
                    key: ValueKey(meta['sessionId'] ?? idx.toString()),
                    title: meta['title'] ?? 'Untitled Document',
                    date: meta['date'] ?? 'Imported',
                    type: meta['type'] ?? 'FILE',
                    fullText: meta['fullText'] ?? '',
                    snippet: meta['snippet'],
                    sessionId: meta['sessionId'],
                    secureRecordId: meta[SecureScriptStore.recordIdKey],
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _GalleryActionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GalleryActionCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.black, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _AutoSaveCard extends StatefulWidget {
  const _AutoSaveCard();
  @override
  State<_AutoSaveCard> createState() => _AutoSaveCardState();
}

class _AutoSaveCardState extends State<_AutoSaveCard> {
  String? _lastContent;

  @override
  void initState() {
    super.initState();
    _checkAutoSave();
  }

  Future<void> _checkAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    final content = prefs.getString('autosave_script');
    final title = prefs.getString('autosave_title') ?? 'Untitled';
    if (mounted && content != null && content.trim().isNotEmpty) {
      setState(() => _lastContent = '$title: $content');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastContent == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: Colors.blue, size: 18),
              const SizedBox(width: 10),
              const Text('RECOVERY AVAILABLE',
                  style: TextStyle(
                      color: Colors.blue,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ScriptEditorScreen()));
                },
                child: const Text('RESTORE SESSION',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Last Session',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text(
            _lastContent!.length > 100
                ? '${_lastContent!.substring(0, 100)}...'
                : _lastContent!,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyStatePlaceholder extends StatelessWidget {
  const _EmptyStatePlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        children: [
          SizedBox(height: 48),
          Icon(Icons.description_outlined, color: Colors.white10, size: 64),
          SizedBox(height: 16),
          Text(
            'Work on you first script now and Choose "New Script"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
