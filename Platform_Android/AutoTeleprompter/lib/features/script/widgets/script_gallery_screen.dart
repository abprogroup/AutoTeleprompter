import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/providers/auth_provider.dart';
import 'script_editor_screen.dart';
import '../../auth/widgets/login_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/script_provider.dart';
import '../../remote/services/remote_control_service.dart';
import '../../settings/widgets/cloud_sync_screen.dart';
import '../../../core/services/styling_service.dart';

class ScriptGalleryScreen extends ConsumerStatefulWidget {
  const ScriptGalleryScreen({super.key});

  @override
  ConsumerState<ScriptGalleryScreen> createState() => _ScriptGalleryScreenState();
}

class _ScriptGalleryScreenState extends ConsumerState<ScriptGalleryScreen> {
  int _logoTaps = 0;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    
    return Scaffold(
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
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('DEBUG MODE: ${isNowDebug ? 'ON' : 'OFF'}'),
                    backgroundColor: isNowDebug ? Colors.green : Colors.grey[800],
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AutoTeleprompter', 
                style: GoogleFonts.bebasNeue(letterSpacing: 1.5, fontSize: 28, color: const Color(0xFFFFBF00))),
              if (auth.isPro) 
                Text('PROFESSIONAL VERSION', 
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Tooltip(
            message: auth.isPro ? 'Remote Hub' : 'Premium Feature',
            child: IconButton(
              icon: Icon(Icons.hub_rounded, 
                color: auth.isPro ? const Color(0xFFFFBF00) : Colors.white.withOpacity(0.12)),
              onPressed: () {
                if (!auth.isPro) {
                  _showProTipDialog(context);
                } else {
                  _showProServiceHub(context);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          auth.email == null 
          ? TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              icon: const Icon(Icons.login_rounded, color: Color(0xFFFFBF00), size: 20),
              label: const Text('Login', style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
            )
          : PopupMenuButton<String>(
              icon: Icon(Icons.account_circle, 
                color: auth.isPro ? const Color(0xFFFFBF00) : Colors.white70, size: 28),
              onSelected: (val) {
                if (val == 'logout') _showLogoutDialog(context, ref);
              },
              offset: const Offset(0, 50),
              color: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(auth.email!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                PopupMenuItem(
                  value: 'profile',
                  child: Row(children: [
                    Icon(Icons.settings, size: 18, color: auth.isPro ? const Color(0xFFFFBF00) : Colors.white70), 
                    const SizedBox(width: 10), 
                    const Text('Production Settings', style: TextStyle(color: Colors.white70))
                  ]),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text('Sign Out', style: TextStyle(color: Colors.redAccent))]),
                ),
              ],
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(builder: (context) {
              final effectiveName = settings.displayName != 'Guest' 
                ? settings.displayName 
                : (auth.email?.split('@').first ?? 'Guest');
              return Text('Welcome Back, $effectiveName.', 
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold));
            }),
            const SizedBox(height: 8),
            const Text('Ready for your next broadcast?', style: TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 40),
            
            _GalleryActionCard(
              title: 'New Script',
              subtitle: 'Start with a blank canvas',
              icon: Icons.add_rounded,
              color: const Color(0xFFFFBF00),
              onTap: () => _showNewScriptDialog(context),
            ),
            const SizedBox(height: 12),
            _GalleryActionCard(
              title: 'Load Script',
              subtitle: 'Import from DOCX, TXT, or PDF',
              icon: Icons.file_open_outlined,
              color: Colors.white,
              onTap: () {
                // v3.9.5.59: Sovereign Fluid Transition
                // Immediately navigate to the editor shell; the editor will handle
                // triggering the file picker over its amber loading screen,
                // eliminating home-to-home flicker.
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScriptEditorScreen(shouldAutoLoad: true)),
                );
              },
            ),
            const SizedBox(height: 24),
            const _ProDashboard(),
            const SizedBox(height: 48),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Activity', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
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
                  child: const Text('show more', style: TextStyle(color: Color(0xFFFFBF00), fontSize: 13, fontWeight: FontWeight.bold)),
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
                    );
                  }).toList(),
            ),
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
        title: const Text('Production Title', style: TextStyle(color: Colors.white)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              ref.read(scriptProvider.notifier).clear();
              ref.read(settingsProvider.notifier).resetToDefaultAppearance();
              ref.read(scriptProvider.notifier).loadText('', title: name.isEmpty ? 'New Script' : name);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ScriptEditorScreen()));
            },
            child: const Text('Start Producing', style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showProTipDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.stars_rounded, color: Color(0xFFFFBF00)),
            SizedBox(width: 10),
            Text('Premium Feature', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Advanced Remote Control from your devices is available for Premium users. Please sign in to experience the full production suite.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('I Understand')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('Sign In', style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showProServiceHub(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 16, left: 24, right: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Row(
              children: [
                Icon(Icons.hub_rounded, color: Color(0xFFFFBF00), size: 24),
                SizedBox(width: 12),
                Text('Remote Hub', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 32),
            const _RemoteDashboard(),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _ProDashboard extends ConsumerWidget {
  const _ProDashboard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFFFBF00).withOpacity(0.15), Colors.transparent]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFBF00).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFFFBF00), size: 32),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CLOUD SYNC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(auth.isPro ? 'Pro Active' : 'Your scripts, anywhere.', 
                  style: TextStyle(color: auth.isPro ? const Color(0xFFFFBF00) : Colors.white54, fontSize: 13, fontWeight: auth.isPro ? FontWeight.bold : null)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (auth.isPro) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudSyncScreen()));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(auth.isPro ? 'SELECT' : 'UPGRADE', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _RemoteDashboard extends ConsumerStatefulWidget {
  const _RemoteDashboard();
  @override
  ConsumerState<_RemoteDashboard> createState() => _RemoteDashboardState();
}

class _RemoteDashboardState extends ConsumerState<_RemoteDashboard> {
  String _ip = 'Discovering...';
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _loadIp();
    _isOnline = false;
  }

  Future<void> _loadIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (addr.address.startsWith('192.168.') || addr.address.startsWith('172.')) {
              if (mounted) setState(() => _ip = addr.address);
              return;
            }
          }
        }
      }
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => _ip = addr.address);
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _ip = 'Connect to Wi-Fi');
  }

  Future<void> _toggleRemote(bool start) async {
     final remote = ref.read(remoteControlProvider);
     if (start) {
        await remote.start();
        if (mounted) setState(() => _isOnline = true);
     } else {
        await remote.stop();
        if (mounted) setState(() => _isOnline = false);
     }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isOnline ? const Color(0xFFFFBF00).withOpacity(0.3) : Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Control this prompter from your browser:', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _isOnline ? Colors.greenAccent : Colors.redAccent),
              ),
              const SizedBox(width: 6),
              Text(_isOnline ? 'LIVE' : 'OFFLINE', style: TextStyle(color: _isOnline ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('http://$_ip:8080', 
                  style: TextStyle(color: _isOnline ? Colors.white : Colors.white24, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all_rounded, color: Colors.white54, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: 'http://$_ip:8080'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link Copied!')));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _RemoteActionBtn(
                icon: _isOnline ? Icons.portable_wifi_off_rounded : Icons.wifi_protected_setup_rounded, 
                label: _isOnline ? 'Go Offline' : 'Go Online', 
                onTap: () => _toggleRemote(!_isOnline),
              ),
              _RemoteActionBtn(icon: Icons.help_outline, label: 'Guide', onTap: () => _showRemoteGuide(context)),
              _RemoteActionBtn(icon: Icons.share_rounded, label: 'Share', onTap: () {
                 Clipboard.setData(ClipboardData(text: 'Check my Teleprompter V3 Pro Remote: http://$_ip:8080'));
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remote Link Shared to Clipboard!')));
              }),
            ],
          ),
        ],
      ),
    );
  }

  void _showRemoteGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Remote Connectivity Guide', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Connect to Same Network', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('Ensure your controlling device (laptop, tablet, or phone) is on the same Wi-Fi network as this prompter.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('2. Enter Address in Browser', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('Open any web browser and type the URL shown on your dashboard. This will launch your V3 Professional Control Suite.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('3. Remote Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('Use the remote to toggle between Manual Scroll and Speech Follow modes, adjust speed, and reset your script position seamlessly.', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
        ],
      ),
    );
  }
}

class _RemoteActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RemoteActionBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFFFBF00), size: 18),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

class _FullHistorySheet extends ConsumerWidget {
  const _FullHistorySheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scripts = ref.watch(settingsProvider).recentScripts;
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Color(0xFF0A0A0A), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Complete History', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
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
                    );
                  },
                );
              }
            ),
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

  const _GalleryActionCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.black, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 4),
                   Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
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

class _ScriptListItem extends ConsumerWidget {
  final String title, date, type, fullText;
  final String? snippet;
  final String? sessionId;

  const _ScriptListItem({
    super.key,
    required this.title,
    required this.date,
    required this.type,
    required this.fullText,
    this.snippet,
    this.sessionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color labelColor;
    Color labelBgColor;
    Color labelBorderColor;

    switch (type.toUpperCase()) {
      case 'PRO':
        labelColor = Colors.black;
        labelBgColor = const Color(0xFFFFBF00);
        labelBorderColor = Colors.transparent;
        break;
      case 'TEMP':
        labelColor = const Color(0xFF64B5F6);
        labelBgColor = labelColor.withOpacity(0.15);
        labelBorderColor = labelColor.withOpacity(0.3);
        break;
      case 'RTF':
      case 'DOCX':
      case 'DOC':
      case 'ODT':
      case 'PAGES':
        labelColor = const Color(0xFF81C784); // Greenish for documents
        labelBgColor = labelColor.withOpacity(0.15);
        labelBorderColor = labelColor.withOpacity(0.3);
        break;
      case 'PDF':
        labelColor = const Color(0xFFE57373); // Reddish for PDF
        labelBgColor = labelColor.withOpacity(0.15);
        labelBorderColor = labelColor.withOpacity(0.3);
        break;
      case 'TXT':
      case 'MD':
      case 'LOG':
        labelColor = Colors.white70;
        labelBgColor = Colors.white10;
        labelBorderColor = Colors.white24;
        break;
      default:
        labelColor = const Color(0xFFCE93D8); // Purple for others
        labelBgColor = labelColor.withOpacity(0.15);
        labelBorderColor = labelColor.withOpacity(0.3);
    }

    final previewText = snippet ?? StylingService.stripTags(fullText.split('\n').first.trim().isNotEmpty ? fullText.split('\n').first : 'No content preview');

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final settingsNotifier = ref.read(settingsProvider.notifier);
                  final scriptNotifier = ref.read(scriptProvider.notifier);
                  
                  try {
                    final List<String> recentScripts = ref.read(settingsProvider).recentScripts;
                    String? targetMeta;
                    for (var s in recentScripts) {
                      final decodedJson = jsonDecode(s);
                      if (sessionId != null && decodedJson['sessionId'] == sessionId) {
                        targetMeta = s;
                        break;
                      }
                      if (sessionId == null && decodedJson['title'] == title && decodedJson['fullText'] == fullText) {
                        targetMeta = s;
                        break;
                      }
                    }
                    
                    Map<String, dynamic>? decodedMeta;
                    if (targetMeta != null) {
                      decodedMeta = jsonDecode(targetMeta);
                      if (decodedMeta!['style'] != null) {
                        await settingsNotifier.applySessionStyles(decodedMeta['style']);
                      }
                    }

                    scriptNotifier.loadText(fullText, 
                      title: title, 
                      sourceType: type, 
                      sessionId: sessionId,
                      historyJson: decodedMeta?['historyJson'],
                      fontSize: (decodedMeta?['style']?['fontSize'] as num?)?.toDouble(),
                      fontFamily: decodedMeta?['style']?['fontFamily'],
                      lineSpacing: (decodedMeta?['style']?['lineSpacing'] as num?)?.toDouble(),
                      letterSpacing: (decodedMeta?['style']?['letterSpacing'] as num?)?.toDouble(),
                      wordSpacing: (decodedMeta?['style']?['wordSpacing'] as num?)?.toDouble(),
                      textAlign: decodedMeta?['style']?['textAlign'],
                      scriptBgColor: decodedMeta?['style']?['scriptBgColor'],
                      currentWordColor: decodedMeta?['style']?['currentWordColor'],
                      futureWordColor: decodedMeta?['style']?['futureWordColor'],
                    );
                  } catch (e) {
                    debugPrint('Session Recovery Error: $e');
                    scriptNotifier.loadText(fullText, title: title, sourceType: type, sessionId: sessionId);
                  }
                  if (context.mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ScriptEditorScreen()));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        decoration: BoxDecoration(
                          color: labelBgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: labelBorderColor),
                        ),
                        child: Text(type.toUpperCase(), style: TextStyle(
                          color: labelColor,
                          fontSize: 9, 
                          fontWeight: FontWeight.bold
                        )),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(previewText, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 13)),
                            Text(date, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 20),
                onPressed: () {
                  if (sessionId != null) {
                    ref.read(settingsProvider.notifier).removeFromRecent(sessionId!);
                  }
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoSaveCard extends StatefulWidget {
  const _AutoSaveCard({super.key});
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
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: Colors.blue, size: 18),
              const SizedBox(width: 10),
              const Text('RECOVERY AVAILABLE', style: TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ScriptEditorScreen()));
                },
                child: const Text('RESTORE SESSION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Last Session', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          Text(
            _lastContent!.length > 100 ? '${_lastContent!.substring(0, 100)}...' : _lastContent!,
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
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          const Icon(Icons.description_outlined, color: Colors.white10, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Work on you first script now and Choose "New Script"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
