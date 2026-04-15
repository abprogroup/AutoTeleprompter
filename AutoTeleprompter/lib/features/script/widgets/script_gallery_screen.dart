import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'script_editor_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/widgets/app_settings_screen.dart';
import '../providers/script_provider.dart';
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
          child: Text('AutoTeleprompter',
            style: GoogleFonts.bebasNeue(letterSpacing: 1.5, fontSize: 28, color: const Color(0xFFFFBF00))),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
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
            Text('Welcome Back, ${settings.displayName}.',
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
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

}

// v4.0: _ProDashboard, _RemoteDashboard, _RemoteActionBtn removed (premium features)

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
