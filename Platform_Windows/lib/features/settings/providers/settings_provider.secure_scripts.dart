part of 'settings_provider.dart';

class _SecureSettingsMigration {
  final List<String> recentScripts;
  final String lastScriptSessionId;
  final bool needsResave;

  const _SecureSettingsMigration({
    required this.recentScripts,
    required this.lastScriptSessionId,
    required this.needsResave,
  });
}

class _SavedSecureScript {
  final String sessionId;
  final String recordId;

  const _SavedSecureScript({
    required this.sessionId,
    required this.recordId,
  });
}

class _RecentActivation {
  final AppSettings settings;
  final List<String> recentScripts;
  final String recordId;
  final String title;
  final int? historyIndex;
  final bool recentsChanged;

  const _RecentActivation({
    required this.settings,
    required this.recentScripts,
    required this.recordId,
    required this.title,
    required this.historyIndex,
    required this.recentsChanged,
  });
}

extension _SettingsSecureScriptParts on SettingsNotifier {
  Future<_SecureSettingsMigration> _migrateSecureScriptPreferences(
    SharedPreferences prefs,
    List<String> sanitizedRecents,
  ) async {
    final secureStore = SecureScriptStore();
    final migratedRecents = await secureStore.migrateRecentMetadata(
      sanitizedRecents,
      onIssue: (issue, error, stackTrace, index) {
        LightweightDiagnostics.instance.recordError(
          error,
          stackTrace,
          source: 'settings.$issue',
          data: {'index': index},
        );
      },
    );
    var needsResave =
        jsonEncode(migratedRecents) != jsonEncode(sanitizedRecents);
    var lastScriptSessionId = prefs.getString(_lastScriptSessionIdKey) ?? '';

    final legacyLastScript = prefs.getString(_lastScriptKey) ?? '';
    if (legacyLastScript.trim().isNotEmpty) {
      try {
        final migratedLastId = await secureStore.migrateLastScript(
          lastScript: legacyLastScript,
          lastTitle: prefs.getString('last_script_title') ?? '',
          fallbackSessionId: _matchingRecentSessionId(
            migratedRecents,
            prefs.getString('last_script_title') ?? '',
          ),
        );
        if (migratedLastId != null) {
          lastScriptSessionId = migratedLastId;
          await prefs.setString(_lastScriptSessionIdKey, migratedLastId);
        }
      } catch (error, stackTrace) {
        LightweightDiagnostics.instance.recordError(
          error,
          stackTrace,
          source: 'settings.secureLastScriptMigration',
        );
      }
      await prefs.remove(_lastScriptKey);
    }

    final legacyAutosave = prefs.getString('autosave_script') ?? '';
    if (legacyAutosave.trim().isNotEmpty) {
      try {
        final autosaveId = await secureStore.save(
          recordId: 'autosave_${DateTime.now().microsecondsSinceEpoch}',
          text: legacyAutosave,
        );
        await prefs.setString('autosave_secure_record_id', autosaveId);
      } catch (error, stackTrace) {
        LightweightDiagnostics.instance.recordError(
          error,
          stackTrace,
          source: 'settings.secureAutosaveMigration',
        );
      }
      await prefs.remove('autosave_script');
    }

    return _SecureSettingsMigration(
      recentScripts: migratedRecents,
      lastScriptSessionId: lastScriptSessionId,
      needsResave: needsResave,
    );
  }

  Future<_SavedSecureScript> _saveEncryptedScriptRecord({
    required String text,
    required String? sessionId,
    required String? historyJson,
  }) async {
    final effectiveSessionId =
        sessionId ?? 'script_${DateTime.now().microsecondsSinceEpoch}';
    if (text.trim().isEmpty) {
      return _SavedSecureScript(sessionId: effectiveSessionId, recordId: '');
    }
    final secureRecordId = await SecureScriptStore().save(
      recordId: effectiveSessionId,
      text: text,
      historyJson: historyJson,
    );
    return _SavedSecureScript(
      sessionId: effectiveSessionId,
      recordId: secureRecordId,
    );
  }

  Future<Map<String, dynamic>> _secureIncomingRecentMetadata(
    String metadataJson,
  ) async {
    var newData = Map<String, dynamic>.from(jsonDecode(metadataJson));
    final legacyText = newData['fullText'];
    if (legacyText is String && legacyText.isNotEmpty) {
      return SecureScriptStore().secureMetadata(
        newData,
        text: legacyText,
        historyJson: newData['historyJson'] as String?,
      );
    }
    return newData
      ..remove('fullText')
      ..remove('historyJson')
      ..remove('snippet');
  }

  _RecentActivation _prepareRecentActivation(
    Map<String, dynamic> metadata,
    AppSettings current,
  ) {
    final sessionId = metadata['sessionId'] as String?;
    final title = metadata['title'] as String? ?? current.lastScriptTitle;
    final recordId =
        SecureScriptStore.recordIdFromMetadata(metadata) ?? sessionId ?? '';
    final historyIndex = metadata['historyIndex'] as int?;
    final list = List<String>.from(current.recentScripts);

    var updatedList = list;
    final matchIndex = list.indexWhere((item) {
      try {
        final decoded = jsonDecode(item);
        return (sessionId != null && decoded['sessionId'] == sessionId) ||
            (recordId.isNotEmpty &&
                decoded[SecureScriptStore.recordIdKey] == recordId);
      } catch (error) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent activation metadata',
          data: {'error': error.toString()},
        );
        return false;
      }
    });
    if (matchIndex > 0) {
      updatedList = List<String>.from(list);
      final item = updatedList.removeAt(matchIndex);
      updatedList.insert(0, item);
    }

    return _RecentActivation(
      settings: current.copyWith(
        lastScript: '',
        lastScriptTitle: title,
        lastScriptSessionId: recordId,
        lastHistoryIndex: historyIndex ?? current.lastHistoryIndex,
        recentScripts: updatedList,
      ),
      recentScripts: updatedList,
      recordId: recordId,
      title: title,
      historyIndex: historyIndex,
      recentsChanged: !identical(updatedList, list),
    );
  }

  String? _matchingRecentSessionId(List<String> recents, String title) {
    for (final item in recents) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        if (decoded['title'] == title) return decoded['sessionId'] as String?;
      } catch (error) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent title metadata',
          data: {
            'title': title,
            'error': error.toString(),
          },
        );
      }
    }
    return null;
  }
}
