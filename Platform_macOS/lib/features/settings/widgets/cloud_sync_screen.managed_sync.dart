part of 'cloud_sync_screen.dart';

class _ManagedSyncSelection {
  final List<_CloudScriptPayload> savedScripts;
  final List<DeletedScriptEntry> deletedScripts;
  final List<_CloudOnlyScriptPayload> cloudOnlyScripts;
  final List<_CloudDeletedScriptPayload> cloudDeletedScripts;

  const _ManagedSyncSelection({
    required this.savedScripts,
    required this.deletedScripts,
    required this.cloudOnlyScripts,
    required this.cloudDeletedScripts,
  });

  bool get isEmpty =>
      savedScripts.isEmpty &&
      deletedScripts.isEmpty &&
      cloudOnlyScripts.isEmpty &&
      cloudDeletedScripts.isEmpty;
}

class _CloudOnlyScriptPayload {
  final String providerId;
  final String providerLabel;
  final String fileName;
  final String? modifiedAtIso;
  final String identity;

  const _CloudOnlyScriptPayload({
    required this.providerId,
    required this.providerLabel,
    required this.fileName,
    required this.modifiedAtIso,
    required this.identity,
  });
}

class _CloudDeletedScriptPayload {
  final String providerId;
  final String providerLabel;
  final String fileName;
  final String activeFileName;
  final String? modifiedAtIso;
  final String identity;

  const _CloudDeletedScriptPayload({
    required this.providerId,
    required this.providerLabel,
    required this.fileName,
    required this.activeFileName,
    required this.modifiedAtIso,
    required this.identity,
  });
}

extension _CloudSyncManagedActions on _CloudSyncScreenState {
  Future<List<_CloudOnlyScriptPayload>> _cloudOnlyScriptsForManagedSync({
    required List<String> providerIds,
    required List<_CloudScriptPayload> localScripts,
  }) async {
    final localNames = <String>{};
    for (final script in localScripts) {
      try {
        final export = await _readableExportFor(script);
        localNames.add(export.fileName.toLowerCase());
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.managedSync.localName',
          data: {'title': script.title},
        );
      }
    }

    final candidates = <_CloudOnlyScriptPayload>[];
    for (final providerId in providerIds) {
      try {
        final files = await _sync.listScripts(providerId);
        for (final file in files) {
          final key = file.name.toLowerCase();
          if (localNames.contains(key)) continue;
          candidates.add(_CloudOnlyScriptPayload(
            providerId: providerId,
            providerLabel: _providerLabel(providerId),
            fileName: file.name,
            modifiedAtIso: file.modifiedAtIso,
            identity: '$providerId::$key',
          ));
        }
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.managedSync.listCloudOnly',
          data: {'providerId': providerId},
        );
        if (mounted) {
          _showSnack(
            '${_providerLabel(providerId)} list failed: ${_shortError(error)}',
          );
        }
      }
    }
    candidates.sort((a, b) {
      final byProvider = a.providerLabel.compareTo(b.providerLabel);
      if (byProvider != 0) return byProvider;
      return a.fileName.compareTo(b.fileName);
    });
    return candidates;
  }

  Future<List<_CloudDeletedScriptPayload>> _cloudDeletedScriptsForManagedSync({
    required List<String> providerIds,
  }) async {
    final candidates = <_CloudDeletedScriptPayload>[];
    for (final providerId in providerIds) {
      try {
        final files = await _sync.listDeletedScripts(providerId);
        for (final file in files) {
          final key = file.name.toLowerCase();
          candidates.add(_CloudDeletedScriptPayload(
            providerId: providerId,
            providerLabel: _providerLabel(providerId),
            fileName: file.name,
            activeFileName: _activeNameFromCloudDeleted(file.name),
            modifiedAtIso: file.modifiedAtIso,
            identity: '$providerId::deleted::$key',
          ));
        }
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.managedSync.listCloudDeleted',
          data: {'providerId': providerId},
        );
        if (mounted) {
          _showSnack(
            '${_providerLabel(providerId)} deleted list failed: '
            '${_shortError(error)}',
          );
        }
      }
    }
    candidates.sort((a, b) {
      final byProvider = a.providerLabel.compareTo(b.providerLabel);
      if (byProvider != 0) return byProvider;
      return a.fileName.compareTo(b.fileName);
    });
    return candidates;
  }

  String _activeNameFromCloudDeleted(String fileName) {
    return fileName.replaceFirst(RegExp(r'^\d{8}_\d{6}_'), '');
  }

  Future<_ManagedSyncSelection?> _chooseManagedSyncAction({
    required List<_CloudScriptPayload> savedScripts,
    required List<DeletedScriptEntry> deletedScripts,
    required List<_CloudOnlyScriptPayload> cloudOnlyScripts,
    required List<_CloudDeletedScriptPayload> cloudDeletedScripts,
  }) async {
    final savedSelected = {
      for (final script in savedScripts) script.identity,
    };
    final deletedSelected = {
      for (final script in deletedScripts) script.path,
    };
    final cloudOnlySelected = <String>{};
    final cloudDeletedSelected = <String>{};

    return showDialog<_ManagedSyncSelection>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final totalSelected = savedSelected.length +
              deletedSelected.length +
              cloudOnlySelected.length +
              cloudDeletedSelected.length;

          void selectSavedAndDeleted() => setDialogState(() {
                savedSelected
                  ..clear()
                  ..addAll(savedScripts.map((script) => script.identity));
                deletedSelected
                  ..clear()
                  ..addAll(deletedScripts.map((script) => script.path));
                cloudDeletedSelected.clear();
              });

          void clearAll() => setDialogState(() {
                savedSelected.clear();
                deletedSelected.clear();
                cloudOnlySelected.clear();
                cloudDeletedSelected.clear();
              });

          return AlertDialog(
            backgroundColor: const Color(0xFF151515),
            title: const Text(
              'Sync scripts',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 720,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: selectSavedAndDeleted,
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('Select saved/deleted'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: clearAll,
                        icon: const Icon(Icons.clear_all_rounded),
                        label: const Text('Clear all'),
                      ),
                      const Spacer(),
                      Text(
                        '$totalSelected selected',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        const _ManagedSyncHeader(
                          title: 'Saved scripts',
                          subtitle:
                              'Selected files update Local Backup and connected cloud folders.',
                        ),
                        if (savedScripts.isEmpty)
                          const _ManagedSyncEmpty('No saved scripts found.')
                        else
                          for (final script in savedScripts)
                            CheckboxListTile(
                              value: savedSelected.contains(script.identity),
                              onChanged: (value) => setDialogState(() {
                                if (value ?? false) {
                                  savedSelected.add(script.identity);
                                } else {
                                  savedSelected.remove(script.identity);
                                }
                              }),
                              activeColor: const Color(0xFFFFBF00),
                              checkColor: Colors.black,
                              title: Text(
                                script.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                _scriptPayloadSubtitle(script),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        const SizedBox(height: 12),
                        const _ManagedSyncHeader(
                          title: 'Deleted scripts',
                          subtitle:
                              'Selected backups are copied to each provider Deleted Scripts folder.',
                        ),
                        if (deletedScripts.isEmpty)
                          const _ManagedSyncEmpty('No deleted backups found.')
                        else
                          for (final script in deletedScripts)
                            CheckboxListTile(
                              value: deletedSelected.contains(script.path),
                              onChanged: (value) => setDialogState(() {
                                if (value ?? false) {
                                  deletedSelected.add(script.path);
                                } else {
                                  deletedSelected.remove(script.path);
                                }
                              }),
                              activeColor: const Color(0xFFFFBF00),
                              checkColor: Colors.black,
                              title: Text(
                                script.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${script.daysRemaining} days left before permanent delete',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        const SizedBox(height: 12),
                        const _ManagedSyncHeader(
                          title: 'Cloud-only / missing locally',
                          subtitle:
                              'Leave unchecked to keep untouched. Select only files you want moved to cloud Deleted Scripts.',
                        ),
                        if (cloudOnlyScripts.isEmpty)
                          const _ManagedSyncEmpty(
                            'No cloud-only scripts found.',
                          )
                        else
                          for (final script in cloudOnlyScripts)
                            CheckboxListTile(
                              value:
                                  cloudOnlySelected.contains(script.identity),
                              onChanged: (value) => setDialogState(() {
                                if (value ?? false) {
                                  cloudOnlySelected.add(script.identity);
                                } else {
                                  cloudOnlySelected.remove(script.identity);
                                }
                              }),
                              activeColor: const Color(0xFFFFBF00),
                              checkColor: Colors.black,
                              title: Text(
                                script.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${script.providerLabel}'
                                '${script.modifiedAtIso == null ? '' : ' - ${script.modifiedAtIso}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        const SizedBox(height: 12),
                        const _ManagedSyncHeader(
                          title: 'Cloud deleted scripts',
                          subtitle:
                              'Leave unchecked to keep deleted. Select files you want restored to active cloud sync.',
                        ),
                        if (cloudDeletedScripts.isEmpty)
                          const _ManagedSyncEmpty(
                            'No cloud deleted scripts found.',
                          )
                        else
                          for (final script in cloudDeletedScripts)
                            CheckboxListTile(
                              value: cloudDeletedSelected.contains(
                                script.identity,
                              ),
                              onChanged: (value) => setDialogState(() {
                                if (value ?? false) {
                                  cloudDeletedSelected.add(script.identity);
                                } else {
                                  cloudDeletedSelected.remove(script.identity);
                                }
                              }),
                              activeColor: const Color(0xFFFFBF00),
                              checkColor: Colors.black,
                              title: Text(
                                script.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${script.providerLabel} restore as '
                                '${script.activeFileName}'
                                '${script.modifiedAtIso == null ? '' : ' - ${script.modifiedAtIso}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: totalSelected == 0
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          _ManagedSyncSelection(
                            savedScripts: [
                              for (final script in savedScripts)
                                if (savedSelected.contains(script.identity))
                                  script,
                            ],
                            deletedScripts: [
                              for (final script in deletedScripts)
                                if (deletedSelected.contains(script.path))
                                  script,
                            ],
                            cloudOnlyScripts: [
                              for (final script in cloudOnlyScripts)
                                if (cloudOnlySelected.contains(script.identity))
                                  script,
                            ],
                            cloudDeletedScripts: [
                              for (final script in cloudDeletedScripts)
                                if (cloudDeletedSelected
                                    .contains(script.identity))
                                  script,
                            ],
                          ),
                        ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Sync selected'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ManagedSyncHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ManagedSyncHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFBF00),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagedSyncEmpty extends StatelessWidget {
  final String text;

  const _ManagedSyncEmpty(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white30, fontSize: 12),
      ),
    );
  }
}
