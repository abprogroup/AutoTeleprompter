part of 'settings_provider.dart';

mixin SettingsNotifierRecentDelete on Notifier<AppSettings> {
  Future<void> deleteRecentScript({
    String? sessionId,
    String? title,
  }) async {
    final list = List<String>.from(state.recentScripts);
    final removedRecordIds = <String>{};
    final removedItems = <Map<String, dynamic>>[];
    var removedActiveScript = false;
    list.removeWhere((item) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        final itemSessionId = decoded['sessionId'] as String?;
        final itemRecordId = SecureScriptStore.recordIdFromMetadata(decoded);
        final itemTitle = decoded['title'] as String?;
        final matches = (sessionId != null && itemSessionId == sessionId) ||
            (sessionId != null && itemRecordId == sessionId) ||
            (sessionId == null && title != null && itemTitle == title);
        if (!matches) return false;
        final recordId = itemRecordId;
        if (recordId != null) removedRecordIds.add(recordId);
        removedItems.add(decoded);
        removedActiveScript = removedActiveScript ||
            recordId == state.lastScriptSessionId ||
            itemSessionId == state.lastScriptSessionId;
        return true;
      } catch (e) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent metadata while removing script',
          data: {
            'source': 'removeFromRecent',
            'sessionId': sessionId ?? '',
            'title': title ?? '',
            'error': e.toString(),
          },
        );
        return false;
      }
    });

    final secureStore = SecureScriptStore();
    for (final item in removedItems) {
      try {
        final data = await secureStore.readFromMetadata(item);
        await LocalBackupService().backupDeletedScript(
          title: item['title']?.toString() ?? title ?? 'Untitled script',
          text: data?.text ?? '',
          sourceType: item['type']?.toString(),
          sourcePath: item['sourcePath']?.toString(),
        );
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.backupDeletedScript',
          data: {
            'sessionId': item['sessionId']?.toString() ?? '',
            'title': item['title']?.toString() ?? '',
          },
        );
      }
    }

    for (final recordId in removedRecordIds) {
      try {
        await secureStore.delete(recordId);
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.deleteSecureRecentScript',
          data: {'recordId': recordId},
        );
      }
    }

    state = state.copyWith(
      recentScripts: list,
      lastScript: removedActiveScript ? '' : state.lastScript,
      lastScriptSessionId: removedActiveScript ? '' : state.lastScriptSessionId,
      lastScriptTitle: removedActiveScript ? '' : state.lastScriptTitle,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
    if (removedActiveScript) {
      await Future.wait([
        prefs.remove(_lastScriptKey),
        prefs.remove(_lastScriptSessionIdKey),
        prefs.remove('last_script_title'),
      ]);
    }
  }

  Future<void> removeFromRecent(String sessionId) async {
    await deleteRecentScript(sessionId: sessionId);
  }
}

String _recentIdentityKey({
  String? title,
  String? type,
  String? sourcePath,
}) {
  final path = _normalizeRecentPath(sourcePath);
  if (path.isNotEmpty) return 'path:$path';
  final cleanTitle = _normalizeRecentTitle(title);
  if (cleanTitle.isEmpty) return '';
  final cleanType = (type ?? '').trim().toUpperCase();
  return 'title:$cleanType:$cleanTitle';
}

String _normalizeRecentPath(String? value) {
  final path = value?.trim();
  if (path == null || path.isEmpty) return '';
  return path.replaceAll('/', r'\').toLowerCase();
}

String _normalizeRecentTitle(String? value) {
  var title = value?.trim().toLowerCase() ?? '';
  var changed = true;
  while (changed) {
    changed = false;
    final next = title.replaceFirst(
      RegExp(r'\.(?:atp|atp\.txt)$', caseSensitive: false),
      '',
    );
    if (next != title) {
      title = next;
      changed = true;
    }
  }
  return title.replaceAll(RegExp(r'\s+'), ' ');
}

void _dedupeRecentMetadataList(List<String> recentList) {
  final seen = <String>{};
  for (var i = 0; i < recentList.length; i++) {
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(recentList[i]));
      final key = _recentIdentityKey(
        title: decoded['title']?.toString(),
        type: decoded['type']?.toString(),
        sourcePath: decoded['sourcePath']?.toString(),
      );
      if (key.isEmpty || seen.add(key)) continue;
      recentList.removeAt(i);
      i--;
    } catch (_) {
      continue;
    }
  }
}
