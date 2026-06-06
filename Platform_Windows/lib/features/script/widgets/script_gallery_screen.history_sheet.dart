part of 'script_gallery_screen.dart';

class _FullHistorySheet extends ConsumerStatefulWidget {
  const _FullHistorySheet();

  @override
  ConsumerState<_FullHistorySheet> createState() => _FullHistorySheetState();
}

class _FullHistorySheetState extends ConsumerState<_FullHistorySheet> {
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Complete History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectionMode = !_selectionMode;
                    _selected.clear();
                  });
                },
                child: Text(_selectionMode ? 'Cancel' : 'Select'),
              ),
              if (_selectionMode)
                TextButton(
                  onPressed: () {
                    final scripts = _dedupedRecentMetadata(
                      ref.read(settingsProvider).recentScripts,
                    );
                    setState(() {
                      _selected
                        ..clear()
                        ..addAll(scripts.map((item) {
                          final meta = Map<String, dynamic>.from(
                            jsonDecode(item),
                          );
                          return _recentGallerySelectionKey(meta);
                        }));
                    });
                  },
                  child: const Text('Select all'),
                ),
              if (_selectionMode && _selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text('Clear all'),
                ),
              if (_selectionMode && _selected.isNotEmpty)
                TextButton(
                  onPressed: _deleteSelected,
                  child: Text('Delete ${_selected.length}'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Consumer(builder: (context, ref, _) {
              final scripts = _dedupedRecentMetadata(
                ref.watch(settingsProvider).recentScripts,
              );
              return ListView.builder(
                cacheExtent: 1000,
                itemCount: scripts.length,
                itemBuilder: (ctx, idx) {
                  final meta =
                      Map<String, dynamic>.from(jsonDecode(scripts[idx]));
                  final selectionKey = _recentGallerySelectionKey(meta);
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
                    selectionMode: _selectionMode,
                    selected: _selected.contains(selectionKey),
                    onSelectionChanged: (selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(selectionKey);
                        } else {
                          _selected.remove(selectionKey);
                        }
                      });
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final scripts = _dedupedRecentMetadata(
      ref.read(settingsProvider).recentScripts,
    );
    final selectedMeta = <Map<String, dynamic>>[];
    for (final item in scripts) {
      try {
        final meta = Map<String, dynamic>.from(jsonDecode(item));
        if (_selected.contains(_recentGallerySelectionKey(meta))) {
          selectedMeta.add(meta);
        }
      } catch (_) {
        // Ignore malformed history rows.
      }
    }
    if (selectedMeta.isEmpty) return;
    final choice = await showScriptDeleteDialog(
      context,
      title: '${selectedMeta.length} selected scripts',
      sourcePaths: _recentGallerySourcePaths(selectedMeta),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
    try {
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.deleteRecentScripts(selectedMeta);
      var deletedSourceCount = 0;
      if (choice.deleteSourceFile) {
        deletedSourceCount =
            await _deleteRecentGallerySourceFiles(selectedMeta);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedSourceCount > 0
                ? 'Deleted ${selectedMeta.length} scripts and $deletedSourceCount source files.'
                : 'Deleted ${selectedMeta.length} scripts.',
          ),
        ),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'gallery.history.deleteSelected',
        data: {'count': selectedMeta.length},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete selected scripts.')),
      );
    }
  }
}
