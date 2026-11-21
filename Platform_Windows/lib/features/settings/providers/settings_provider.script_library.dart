part of 'settings_provider.dart';

/// Separate append-only path: importing a folder must not activate a script,
/// overwrite a matching entry, or invoke cloud/backup mirroring.
final scriptLibraryStoreProvider = Provider<SecureScriptStore>(
  (ref) => SecureScriptStore(),
);

mixin SettingsNotifierScriptLibrary on Notifier<AppSettings> {
  Future<void>? _libraryReady;
  Future<void> _libraryWriteQueue = Future<void>.value();
  bool get _libraryIsDisposed;

  Future<SecureScriptData> readLibraryScript(Map<String, dynamic> metadata) async {
    final store = ref.read(scriptLibraryStoreProvider);
    final recordId = SecureScriptStore.recordIdFromMetadata(metadata);
    final data = recordId == null
        ? await store.readFromMetadata(metadata) : await store.read(recordId);
    if (data == null) throw StateError('Stored script could not be read.');
    return data;
  }

  Future<T> _serializeLibraryWrite<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _libraryWriteQueue = _libraryWriteQueue.then((_) async {
      try {
        await _libraryReady;
        if (_libraryIsDisposed) throw StateError('Script library is closed.');
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  bool libraryContainsScript({
    required String title,
    String? sourcePath,
    String? excludingSessionId,
  }) => _containsLibraryScript(state.recentScripts, title: title,
      sourcePath: sourcePath, excludingSessionId: excludingSessionId);

  bool _containsLibraryScript(List<String> recents, {required String title,
      String? sourcePath, String? excludingSessionId}) {
    final normalizedTitle = title.trim().toLowerCase();
    String pathKey(String? value) =>
        (value ?? '').trim().replaceAll('\\', '/').toLowerCase();
    final path = pathKey(sourcePath);
    for (final raw in recents) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        if (excludingSessionId != null &&
            item['sessionId'] == excludingSessionId) {
          continue;
        }
        if ((item['title'] as String? ?? '').trim().toLowerCase() ==
                normalizedTitle ||
            (path.isNotEmpty &&
                pathKey(item['sourcePath'] as String?) == path)) {
          return true;
        }
      } catch (_) {
        /* Existing malformed entries are not modified here. */
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> addScriptToLibrary({
    required String title,
    required String text,
    String type = 'TEMP',
    String? sourcePath,
    Map<String, dynamic> style = const {},
  }) =>
      _serializeLibraryWrite(() async {
        final name = title.trim();
        if (name.isEmpty) throw ArgumentError('Script name cannot be empty.');
        final prefs = await SharedPreferences.getInstance();
        var current = prefs.getStringList(_recentScriptsKey) ?? state.recentScripts;
        if (_containsLibraryScript(current, title: name, sourcePath: sourcePath)) {
          return null;
        }
        final id = 'library_${DateTime.now().microsecondsSinceEpoch}';
        final recordId = await ref
            .read(scriptLibraryStoreProvider)
            .save(recordId: id, text: text);
        if (_libraryIsDisposed) throw StateError('Script library is closed.');
        // Recheck after asynchronous storage; another editor may have saved meanwhile.
        current = prefs.getStringList(_recentScriptsKey) ?? state.recentScripts;
        if (_containsLibraryScript(current, title: name, sourcePath: sourcePath)) {
          return null;
        }
        final metadata = <String, dynamic>{
          'title': name,
          'type': type,
          'sessionId': id,
          SecureScriptStore.recordIdKey: recordId,
          SecureScriptStore.storageVersionKey: SecureScriptStore.storageVersion,
          if (sourcePath != null) 'sourcePath': sourcePath,
          'historyIndex': 0,
          'lastModified': DateTime.now().toIso8601String(),
          'style': Map<String, dynamic>.from(style),
        };
        final recents = [jsonEncode(metadata), ...current];
        if (!await prefs.setStringList(_recentScriptsKey, recents)) {
          throw StateError('Could not save the script library.');
        }
        if (!_libraryIsDisposed) state = state.copyWith(recentScripts: recents);
        return metadata;
      });

  Future<bool> renameLibraryScript(String sessionId, String title) =>
      _serializeLibraryWrite(() async {
        final name = title.trim();
        final prefs = await SharedPreferences.getInstance();
        final recents = List<String>.from(
            prefs.getStringList(_recentScriptsKey) ?? state.recentScripts);
        if (name.isEmpty ||
            _containsLibraryScript(recents, title: name, excludingSessionId: sessionId)) {
          return false;
        }
        for (var i = 0; i < recents.length; i++) {
          final Map<String, dynamic> item;
          try {
            item = Map<String, dynamic>.from(jsonDecode(recents[i]));
          } catch (_) {
            continue;
          }
          if (item['sessionId'] != sessionId) continue;
          item['title'] = name;
          recents[i] = jsonEncode(item);
          if (!await prefs.setStringList(_recentScriptsKey, recents)) {
            throw StateError('Could not rename the script.');
          }
          if (!_libraryIsDisposed) state = state.copyWith(recentScripts: recents);
          return true;
        }
        return false;
      });
}
