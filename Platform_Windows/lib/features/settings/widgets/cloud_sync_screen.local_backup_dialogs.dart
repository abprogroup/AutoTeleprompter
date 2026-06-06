part of 'cloud_sync_screen.dart';

extension _CloudSyncScreenLocalBackupDialogs on _CloudSyncScreenState {
  Future<void> _showLocalBackupScripts() async {
    final folder = _localBackup?.folderPath.trim() ?? '';
    if (folder.isEmpty) return;
    final files = <File>[];
    try {
      await LocalBackupService().migrateHistorySidecarsFromBackupFolder();
      final directory = Directory(folder);
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is! File) continue;
          if (_isBackupScriptFile(entity.path)) files.add(entity);
        }
      }
      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.localBackupList',
      );
      _showSnack('Could not list Local Backup scripts.');
      return;
    }

    if (!mounted) return;
    final selected = <String>{};
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> deleteSelected() async {
              final targets = [
                for (final file in files)
                  if (selected.contains(file.path)) file,
              ];
              if (targets.isEmpty) return;
              final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (confirmContext) => AlertDialog(
                      backgroundColor: const Color(0xFF151515),
                      title: const Text(
                        'Delete local backup files?',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: Text(
                        'This removes ${targets.length} selected Local Backup '
                        'script files and their restore metadata. It does not '
                        'delete the original source files.',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(confirmContext, true),
                          child: const Text('Delete selected'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!confirmed) return;
              final service = LocalBackupService();
              for (final file in targets) {
                await service.deleteBackupFileAndHistory(file.path);
              }
              files.removeWhere((file) => selected.contains(file.path));
              selected.clear();
              if (context.mounted) {
                setDialogState(() {});
                _showSnack('Deleted ${targets.length} Local Backup scripts.');
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF151515),
              title: const Text(
                'Local Backup scripts',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 640,
                child: files.isEmpty
                    ? const Text(
                        'No backed-up scripts are in this folder yet.',
                        style: TextStyle(color: Colors.white70),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () => setDialogState(() {
                                  selected
                                    ..clear()
                                    ..addAll(files.map((file) => file.path));
                                }),
                                icon: const Icon(Icons.done_all),
                                label: const Text('Select all'),
                              ),
                              TextButton.icon(
                                onPressed: selected.isEmpty
                                    ? null
                                    : () => setDialogState(selected.clear),
                                icon: const Icon(Icons.clear_all),
                                label: const Text('Clear all'),
                              ),
                              TextButton.icon(
                                onPressed:
                                    selected.isEmpty ? null : deleteSelected,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete selected'),
                              ),
                              Text(
                                '${selected.length}/${files.length} selected',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: files.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: Colors.white12),
                              itemBuilder: (context, index) {
                                final file = files[index];
                                final stat = file.statSync();
                                final isSelected = selected.contains(file.path);
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (value) => setDialogState(() {
                                      if (value == true) {
                                        selected.add(file.path);
                                      } else {
                                        selected.remove(file.path);
                                      }
                                    }),
                                    activeColor: const Color(0xFFFFBF00),
                                  ),
                                  title: Text(
                                    file.uri.pathSegments.last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    '${stat.modified}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Delete backup',
                                    onPressed: () {
                                      selected
                                        ..clear()
                                        ..add(file.path);
                                      deleteSelected();
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  onTap: () => setDialogState(() {
                                    if (isSelected) {
                                      selected.remove(file.path);
                                    } else {
                                      selected.add(file.path);
                                    }
                                  }),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openFolder(folder);
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open folder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isBackupScriptFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.rtf') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.text') ||
        lower.endsWith('.log') ||
        lower.endsWith('.md') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.odt') ||
        lower.endsWith('.pages');
  }
}
