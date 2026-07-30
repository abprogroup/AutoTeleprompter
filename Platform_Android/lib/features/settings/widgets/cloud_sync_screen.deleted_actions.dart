part of 'cloud_sync_screen.dart';

extension _CloudSyncDeletedActions on _CloudSyncScreenState {
  Future<int> _syncDeletedScriptsForProvider({
    required String providerId,
    required List<DeletedScriptEntry> deletedScripts,
    required List<String> failures,
  }) async {
    var ok = 0;
    for (final entry in deletedScripts) {
      try {
        final result = await _sync.uploadDeletedScriptFile(
          providerId: providerId,
          filePath: entry.path,
          originalName: entry.originalName,
          deletedAt: entry.deletedAt,
        );
        if (result.ok) {
          ok++;
        } else {
          failures.add('${_providerLabel(providerId)} deleted: '
              '${result.message}');
        }
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.syncDeletedScripts',
          data: {
            'providerId': providerId,
            'name': entry.displayName,
          },
        );
        failures.add(
          '${_providerLabel(providerId)} deleted: ${_shortError(error)}',
        );
      }
    }
    return ok;
  }
}
