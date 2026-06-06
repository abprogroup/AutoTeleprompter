part of 'cloud_app_folder_sync_service.dart';

extension CloudAppFolderDeleteActions on CloudAppFolderSyncService {
  static const _deletedFolderName = 'Deleted Scripts';

  Future<CloudSyncResult> deleteSyncedScriptPermanently({
    required String providerId,
    required String primaryFileName,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before deleting synced scripts.',
      );
    }
    final safeName = _safeFileName(primaryFileName);
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _deleteGoogleSyncedScript(
          session: session,
          primaryFileName: safeName,
        ),
      CloudConnectionStore.dropbox => _deleteDropboxSyncedScript(
          session: session,
          primaryFileName: safeName,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support cloud script deletion.',
        ),
    };
  }

  Future<CloudSyncResult> deleteDeletedScriptPermanently({
    required String providerId,
    required String deletedFileName,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before deleting synced scripts.',
      );
    }
    final deletedName = _safeFileName(deletedFileName);
    final activeName = _activeNameFromDeletedCloudFile(deletedName);
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _deleteGoogleDeletedScript(
          session: session,
          deletedFileName: deletedName,
          activeFileName: activeName,
        ),
      CloudConnectionStore.dropbox => _deleteDropboxDeletedScript(
          session: session,
          deletedFileName: deletedName,
          activeFileName: activeName,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support cloud script deletion.',
        ),
    };
  }

  Future<CloudSyncResult> _deleteGoogleSyncedScript({
    required CloudAuthorizedSession session,
    required String primaryFileName,
  }) async {
    final rootId = await _googleFolderId(session);
    final metadataId = await _googleMetadataFolderId(session);
    var deleted = 0;
    deleted += await _deleteGoogleNames(
      session: session,
      folderId: rootId,
      fileNames: [primaryFileName],
    );
    deleted += await _deleteGoogleMetadataVariants(
      session: session,
      metadataFolderId: metadataId,
      primaryFileName: primaryFileName,
      alternateFileName: primaryFileName,
    );
    return CloudSyncResult(
      ok: deleted > 0,
      message: deleted > 0
          ? 'Deleted $primaryFileName from Google Drive sync.'
          : '$primaryFileName was not found in Google Drive sync.',
    );
  }

  Future<CloudSyncResult> _deleteGoogleDeletedScript({
    required CloudAuthorizedSession session,
    required String deletedFileName,
    required String activeFileName,
  }) async {
    final rootId = await _googleFolderId(session);
    final deletedId = await _googleFolderId(
      session,
      folderName: _deletedFolderName,
      parentId: rootId,
    );
    final deletedMetadataId = await _googleFolderId(
      session,
      folderName: CloudAppFolderSyncService._metadataFolderName,
      parentId: deletedId,
    );
    var deleted = 0;

    deleted += await _deleteGoogleNames(
      session: session,
      folderId: deletedId,
      fileNames: [deletedFileName],
    );
    deleted += await _deleteGoogleNames(
      session: session,
      folderId: deletedMetadataId,
      fileNames: _metadataNamesForDeleted(deletedFileName, activeFileName),
    );
    deleted += await _deleteGoogleMetadataVariants(
      session: session,
      metadataFolderId: deletedMetadataId,
      primaryFileName: deletedFileName,
      alternateFileName: activeFileName,
    );

    return CloudSyncResult(
      ok: deleted > 0,
      message: deleted > 0
          ? 'Deleted $deletedFileName from Google Drive Deleted Scripts.'
          : '$deletedFileName was not found in Google Drive Deleted Scripts.',
    );
  }

  Future<int> _deleteGoogleNames({
    required CloudAuthorizedSession session,
    required String folderId,
    required List<String> fileNames,
  }) async {
    final ids = <String>{};
    for (final fileName in fileNames) {
      ids.addAll(await _googleFileIdsByName(
        session: session,
        folderId: folderId,
        fileName: fileName,
      ));
    }
    for (final fileName in fileNames) {
      await _deleteGoogleFileByName(
        session: session,
        folderId: folderId,
        fileName: fileName,
      );
    }
    return ids.length;
  }

  Future<int> _deleteGoogleMetadataVariants({
    required CloudAuthorizedSession session,
    required String metadataFolderId,
    required String primaryFileName,
    required String alternateFileName,
  }) async {
    final expected = _metadataNamesForDeleted(primaryFileName, alternateFileName);
    final removedIds = <String>{};
    removedIds.addAll(await _googleFileIdsByNames(
      session: session,
      folderId: metadataFolderId,
      fileNames: expected,
    ));
    final decoded = await _jsonRequest(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'$metadataFolderId' in parents and trashed=false",
        'spaces': 'drive',
        'fields': 'files(id,name)',
      }),
      token: session.accessToken,
    );
    final files = decoded['files'];
    if (files is List) {
      for (final file in files) {
        if (file is! Map) continue;
        final id = file['id']?.toString() ?? '';
        final name = file['name']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (_metadataLooksRelated(
          name,
          primaryFileName: primaryFileName,
          alternateFileName: alternateFileName,
        )) {
          removedIds.add(id);
        }
      }
    }
    for (final id in removedIds) {
      await _deleteGoogleFileById(session: session, fileId: id);
    }
    return removedIds.length;
  }

  Future<List<String>> _googleFileIdsByNames({
    required CloudAuthorizedSession session,
    required String folderId,
    required List<String> fileNames,
  }) async {
    final ids = <String>{};
    for (final fileName in fileNames) {
      ids.addAll(await _googleFileIdsByName(
        session: session,
        folderId: folderId,
        fileName: fileName,
      ));
    }
    return ids.toList(growable: false);
  }

  Future<CloudSyncResult> _deleteDropboxSyncedScript({
    required CloudAuthorizedSession session,
    required String primaryFileName,
  }) async {
    final root = _dropboxRootPath();
    final metadata = _dropboxMetadataFolderPath();
    var removed = 0;
    if (await _deleteDropboxPathIfPresent(
      session: session,
      path: _dropboxFilePath(root, primaryFileName),
    )) {
      removed++;
    }
    removed += await _deleteDropboxMetadataVariants(
      session: session,
      metadataFolderPath: metadata,
      primaryFileName: primaryFileName,
      alternateFileName: primaryFileName,
    );
    return CloudSyncResult(
      ok: removed > 0,
      message: removed > 0
          ? 'Deleted $primaryFileName from Dropbox sync.'
          : '$primaryFileName was not found in Dropbox sync.',
    );
  }

  Future<CloudSyncResult> _deleteDropboxDeletedScript({
    required CloudAuthorizedSession session,
    required String deletedFileName,
    required String activeFileName,
  }) async {
    final root = _dropboxRootPath();
    final deleted = _dropboxChildPath(root, _deletedFolderName);
    final deletedMetadata = _dropboxChildPath(
      deleted,
      CloudAppFolderSyncService._metadataFolderName,
    );
    var removed = 0;

    if (await _deleteDropboxPathIfPresent(
      session: session,
      path: _dropboxFilePath(deleted, deletedFileName),
    )) {
      removed++;
    }
    removed += await _deleteDropboxMetadataVariants(
      session: session,
      metadataFolderPath: deletedMetadata,
      primaryFileName: deletedFileName,
      alternateFileName: activeFileName,
    );

    return CloudSyncResult(
      ok: removed > 0,
      message: removed > 0
          ? 'Deleted $deletedFileName from Dropbox Deleted Scripts.'
          : '$deletedFileName was not found in Dropbox Deleted Scripts.',
    );
  }

  Future<bool> _deleteDropboxPathIfPresent({
    required CloudAuthorizedSession session,
    required String path,
  }) async {
    try {
      await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/delete_v2'),
        token: session.accessToken,
        body: {'path': path},
      );
      return true;
    } catch (error) {
      final lower = error.toString().toLowerCase();
      if (lower.contains('not_found') || lower.contains('not-file')) {
        return false;
      }
      rethrow;
    }
  }

  Future<int> _deleteDropboxMetadataVariants({
    required CloudAuthorizedSession session,
    required String metadataFolderPath,
    required String primaryFileName,
    required String alternateFileName,
  }) async {
    var removed = 0;
    final exactNames = _metadataNamesForDeleted(
      primaryFileName,
      alternateFileName,
    );
    for (final metadataName in exactNames) {
      if (await _deleteDropboxPathIfPresent(
        session: session,
        path: _dropboxFilePath(metadataFolderPath, metadataName),
      )) {
        removed++;
      }
    }

    Map<String, dynamic> decoded;
    try {
      decoded = await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
        token: session.accessToken,
        body: {'path': metadataFolderPath, 'recursive': false},
      );
    } catch (error) {
      final lower = error.toString().toLowerCase();
      if (lower.contains('not_found') || lower.contains('not-file')) {
        return removed;
      }
      rethrow;
    }
    final entries = decoded['entries'];
    if (entries is! List) return removed;
    for (final entry in entries) {
      if (entry is! Map<String, dynamic> || entry['.tag'] != 'file') {
        continue;
      }
      final name = entry['name']?.toString() ?? '';
      final path = entry['path_lower']?.toString() ?? '';
      if (path.isEmpty) continue;
      if (!_metadataLooksRelated(
        name,
        primaryFileName: primaryFileName,
        alternateFileName: alternateFileName,
      )) {
        continue;
      }
      if (await _deleteDropboxPathIfPresent(session: session, path: path)) {
        removed++;
      }
    }
    return removed;
  }

  List<String> _metadataNamesForDeleted(
    String deletedFileName,
    String activeFileName,
  ) {
    return {
      ScriptProjectCodec.metadataFileNameFor(deletedFileName),
      ScriptProjectCodec.metadataFileNameFor(activeFileName),
      ..._legacyArtifactNamesFor(deletedFileName),
      ..._legacyArtifactNamesFor(activeFileName),
    }.toList(growable: false);
  }

  String _activeNameFromDeletedCloudFile(String fileName) {
    return fileName.replaceFirst(RegExp(r'^\d{8}_\d{6}_'), '');
  }

  bool _metadataLooksRelated(
    String metadataName, {
    required String primaryFileName,
    required String alternateFileName,
  }) {
    final base = _metadataPrimaryName(metadataName);
    if (base.isEmpty) return false;
    final candidates = {
      _metadataCompareKey(primaryFileName),
      _metadataCompareKey(alternateFileName),
      _metadataCompareKey(_activeNameFromDeletedCloudFile(primaryFileName)),
      _metadataCompareKey(_activeNameFromDeletedCloudFile(alternateFileName)),
    }..remove('');
    return candidates.contains(_metadataCompareKey(base));
  }

  String _metadataPrimaryName(String metadataName) {
    final trimmed = metadataName.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    const suffix = ScriptProjectCodec.companionSuffix;
    if (lower.endsWith(suffix)) {
      return trimmed.substring(0, trimmed.length - suffix.length);
    }
    final match = RegExp(
      r'^(.*)\.autoteleprompter(?: \(\d+\))?\.json$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return match?.group(1)?.trim() ?? '';
  }

  String _metadataCompareKey(String value) {
    return value
        .replaceFirst(RegExp(r'^\d{8}_\d{6}_'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }
}
