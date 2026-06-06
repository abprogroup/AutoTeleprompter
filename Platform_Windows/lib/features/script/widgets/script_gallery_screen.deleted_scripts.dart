part of 'script_gallery_screen.dart';

class _DeletedScriptsSection extends ConsumerStatefulWidget {
  final bool enabled;

  const _DeletedScriptsSection({required this.enabled});

  @override
  ConsumerState<_DeletedScriptsSection> createState() =>
      _DeletedScriptsSectionState();
}

class _DeletedScriptsSectionState
    extends ConsumerState<_DeletedScriptsSection> {
  final DeletedScriptsService _service = DeletedScriptsService();
  StreamSubscription<void>? _deletedChanges;
  Timer? _folderRefreshTimer;
  List<DeletedScriptEntry> _entries = const [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _deletedChanges = DeletedScriptsService.changes.listen((_) {
      unawaited(_loadDeletedEntries(showLoading: false));
    });
    _folderRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_loadDeletedEntries(showLoading: false));
    });
    unawaited(_loadDeletedEntries());
  }

  @override
  void didUpdateWidget(covariant _DeletedScriptsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      unawaited(_loadDeletedEntries());
    }
  }

  @override
  void dispose() {
    _deletedChanges?.cancel();
    _folderRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeletedEntries({bool showLoading = true}) async {
    if (!widget.enabled) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _loading = false;
      });
      return;
    }
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }
    final next = await _service.listLocalDeletedScripts();
    if (!mounted) return;
    setState(() {
      _entries = next;
      _selectedPaths.removeWhere(
        (path) => !next.any((entry) => entry.path == path),
      );
      if (_selectedPaths.isEmpty) _selectionMode = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const Padding(
        padding: EdgeInsets.only(top: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deleted Scripts',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            _DeletedScriptsEmptyTile(
              icon: Icons.lock_outline_rounded,
              title: 'Deleted scripts are locked',
              subtitle: 'Connect a Pro account to view 30-day deleted backups.',
            ),
          ],
        ),
      );
    }
    final entries = _entries;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Deleted Scripts',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectionMode = !_selectionMode;
                          _selectedPaths.clear();
                        });
                      },
                      child: Text(
                        _selectionMode ? 'cancel' : 'select',
                        style: const TextStyle(
                          color: Color(0xFFFFBF00),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_selectionMode && entries.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedPaths
                            ..clear()
                            ..addAll(
                                entries.take(3).map((entry) => entry.path));
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
                  if (_selectionMode && _selectedPaths.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selectedPaths.clear()),
                      child: const Text(
                        'clear all',
                        style: TextStyle(
                          color: Color(0xFFFFBF00),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (_selectionMode && _selectedPaths.isNotEmpty) ...[
                    TextButton(
                      onPressed: _confirmRestoreSelected,
                      child: Text(
                        'recover ${_selectedPaths.length}',
                        style: const TextStyle(
                          color: Color(0xFFFFBF00),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _confirmPermanentDeleteSelected,
                      child: Text(
                        'delete ${_selectedPaths.length}',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  if (entries.length > 3)
                    TextButton(
                      onPressed: () => _showAllDeletedScripts(entries),
                      child: const Text(
                        'show more',
                        style: TextStyle(
                          color: Color(0xFFFFBF00),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Kept for 30 days in Local Backup before permanent deletion.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_loading && entries.isEmpty)
            const _DeletedScriptsEmptyTile(
              icon: Icons.hourglass_empty_rounded,
              title: 'Checking deleted backups...',
              subtitle: 'Looking for scripts kept in the 30-day restore list.',
            )
          else if (entries.isEmpty)
            const _DeletedScriptsEmptyTile(
              icon: Icons.restore_from_trash_outlined,
              title: 'No deleted scripts',
              subtitle:
                  'Deleted scripts will appear here for 30 days after removal.',
            )
          else
            Column(
              children: entries
                  .take(3)
                  .map((entry) => _DeletedScriptTile(
                        entry: entry,
                        onRestore: () => _confirmRestore(entry),
                        onDeleteForever: () => _confirmPermanentDelete(entry),
                        selectionMode: _selectionMode,
                        selected: _selectedPaths.contains(entry.path),
                        onSelectionChanged: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedPaths.add(entry.path);
                            } else {
                              _selectedPaths.remove(entry.path);
                            }
                          });
                        },
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  void _showAllDeletedScripts(List<DeletedScriptEntry> entries) {
    final sheetSelected = <String>{};
    var sheetSelectionMode = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0A),
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
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
                      'Deleted Scripts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        sheetSelectionMode = !sheetSelectionMode;
                        sheetSelected.clear();
                      });
                    },
                    child: Text(sheetSelectionMode ? 'Cancel' : 'Select'),
                  ),
                  if (sheetSelectionMode)
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          sheetSelected
                            ..clear()
                            ..addAll(entries.map((entry) => entry.path));
                        });
                      },
                      child: const Text('Select all'),
                    ),
                  if (sheetSelectionMode && sheetSelected.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setSheetState(() => sheetSelected.clear());
                      },
                      child: const Text('Clear all'),
                    ),
                  if (sheetSelectionMode && sheetSelected.isNotEmpty) ...[
                    TextButton(
                      onPressed: () async {
                        await _restoreDeletedBatch(
                          entries
                              .where(
                                  (entry) => sheetSelected.contains(entry.path))
                              .toList(),
                        );
                        final next = await _service.listLocalDeletedScripts();
                        if (!context.mounted) return;
                        setSheetState(() {
                          entries = next;
                          sheetSelected.clear();
                          sheetSelectionMode = false;
                        });
                      },
                      child: Text('Recover ${sheetSelected.length}'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _permanentlyDeleteBatch(
                          entries
                              .where(
                                  (entry) => sheetSelected.contains(entry.path))
                              .toList(),
                        );
                        final next = await _service.listLocalDeletedScripts();
                        if (!context.mounted) return;
                        setSheetState(() {
                          entries = next;
                          sheetSelected.clear();
                          sheetSelectionMode = false;
                        });
                      },
                      child: Text('Delete ${sheetSelected.length}'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Permanent delete removes the backup and its restore metadata.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: entries
                      .map((entry) => _DeletedScriptTile(
                            entry: entry,
                            onRestore: () async {
                              await _confirmRestore(entry);
                              final next =
                                  await _service.listLocalDeletedScripts();
                              if (!context.mounted) return;
                              setSheetState(() => entries = next);
                            },
                            onDeleteForever: () async {
                              await _confirmPermanentDelete(entry);
                              final next =
                                  await _service.listLocalDeletedScripts();
                              if (!context.mounted) return;
                              setSheetState(() => entries = next);
                            },
                            selectionMode: sheetSelectionMode,
                            selected: sheetSelected.contains(entry.path),
                            onSelectionChanged: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  sheetSelected.add(entry.path);
                                } else {
                                  sheetSelected.remove(entry.path);
                                }
                              });
                            },
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestoreSelected() async {
    final entries =
        _entries.where((entry) => _selectedPaths.contains(entry.path)).toList();
    if (entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Recover selected scripts?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Recover ${entries.length} deleted scripts into the backup folder '
          'and restore their metadata when available.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Recover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _restoreDeletedBatch(entries);
    await _loadDeletedEntries(showLoading: false);
  }

  Future<void> _confirmPermanentDeleteSelected() async {
    final entries =
        _entries.where((entry) => _selectedPaths.contains(entry.path)).toList();
    if (entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete selected forever?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This permanently removes ${entries.length} deleted backups and '
          'their restore metadata.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete forever',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _permanentlyDeleteBatch(entries);
    await _loadDeletedEntries(showLoading: false);
  }

  Future<void> _restoreDeletedBatch(List<DeletedScriptEntry> entries) async {
    var restoredCount = 0;
    for (final entry in entries) {
      final restored =
          await ref.read(settingsProvider.notifier).restoreDeletedScript(entry);
      if (restored != null) restoredCount++;
    }
    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recovered $restoredCount scripts.')),
    );
  }

  Future<void> _permanentlyDeleteBatch(
    List<DeletedScriptEntry> entries,
  ) async {
    for (final entry in entries) {
      await _service.permanentlyDeleteLocal(entry);
    }
    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${entries.length} backups forever.')),
    );
  }

  Future<void> _confirmRestore(DeletedScriptEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Recover deleted script?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${entry.displayName}\n\nThis moves the file out of Deleted Scripts '
          'and restores its matching metadata when available.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Recover',
              style: TextStyle(color: Color(0xFFFFBF00)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final restored =
        await ref.read(settingsProvider.notifier).restoreDeletedScript(entry);
    await _loadDeletedEntries(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restored == null
            ? 'Deleted script file was not found.'
            : 'Recovered script to ${restored.file.parent.path}.'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _confirmPermanentDelete(DeletedScriptEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete permanently?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${entry.displayName}\n\nThis removes the deleted backup immediately. '
          'The 30-day restore copy will no longer be available.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete forever',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.permanentlyDeleteLocal(entry);
    await _loadDeletedEntries(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deleted script backup removed permanently.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

class _DeletedScriptsEmptyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DeletedScriptsEmptyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletedScriptTile extends StatelessWidget {
  final DeletedScriptEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  const _DeletedScriptTile({
    required this.entry,
    required this.onRestore,
    required this.onDeleteForever,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFBF00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.restore_from_trash_outlined,
              color: Color(0xFFFFBF00),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          if (selectionMode) ...[
            Checkbox(
              value: selected,
              onChanged: (value) => onSelectionChanged?.call(value ?? false),
              activeColor: const Color(0xFFFFBF00),
              checkColor: Colors.black,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.daysRemaining} days left before permanent delete',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Recover script',
            onPressed: selectionMode
                ? () => onSelectionChanged?.call(!selected)
                : onRestore,
            icon: const Icon(
              Icons.restore_rounded,
              color: Color(0xFFFFBF00),
            ),
          ),
          IconButton(
            tooltip: 'Delete forever',
            onPressed: selectionMode ? null : onDeleteForever,
            icon: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
