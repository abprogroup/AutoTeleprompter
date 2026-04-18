import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/providers/settings_provider.dart';

// v3.9.5.58: Extracted Lobby Settings Panel
class LobbySettingsPanel extends ConsumerWidget {
  const LobbySettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Video Quality', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '480p', label: Text('480p'), icon: Icon(Icons.sd_outlined)),
              ButtonSegment(value: '720p', label: Text('720p'), icon: Icon(Icons.hd_outlined)),
              ButtonSegment(value: '1080p', label: Text('1080p'), icon: Icon(Icons.high_quality_outlined))
            ],
            selected: {settings.videoResolution},
            onSelectionChanged: (vals) => notifier.setVideoResolution(vals.first),
          ),
          const SizedBox(height: 24),
          const Text('User Profile', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter Display Name',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFFFBF00)),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
            ),
            controller: TextEditingController(text: settings.displayName),
            onSubmitted: (val) => notifier.setDisplayName(val),
          ),
          const SizedBox(height: 24),
        ]
      )
    );
  }
}
