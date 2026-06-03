part of 'script_gallery_screen.dart';

class _FullHistorySheet extends ConsumerWidget {
  const _FullHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Complete History',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
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
                    sourcePath: meta['sourcePath'],
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
