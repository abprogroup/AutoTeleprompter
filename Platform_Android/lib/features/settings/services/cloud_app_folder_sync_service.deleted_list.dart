part of 'cloud_app_folder_sync_service.dart';

extension CloudAppFolderDeletedScriptList on CloudAppFolderSyncService {
  static const _deletedListFolderName = 'Deleted Scripts';

  Future<List<CloudSyncedFile>> listDeletedScripts(String providerId) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) return const [];
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _listGoogleDeletedScripts(session),
      CloudConnectionStore.dropbox => _listDropboxDeletedScripts(session),
      _ => const <CloudSyncedFile>[],
    };
  }

  Future<List<CloudSyncedFile>> _listGoogleDeletedScripts(
    CloudAuthorizedSession session,
  ) async {
    final rootId = await _googleFolderId(session);
    final deletedId = await _googleFolderId(
      session,
      folderName: _deletedListFolderName,
      parentId: rootId,
    );
    final decoded = await _jsonRequest(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'$deletedId' in parents and trashed=false",
        'spaces': 'drive',
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id,name,mimeType,modifiedTime,size)',
      }),
      token: session.accessToken,
    );
    final files = decoded['files'];
    if (files is! List) return const [];
    return [
      for (final file in files)
        if (file is Map<String, dynamic>)
          if (file['mimeType'] != 'application/vnd.google-apps.folder')
            CloudSyncedFile(
              id: file['id']?.toString() ?? '',
              name: file['name']?.toString() ?? 'Untitled',
              providerId: CloudConnectionStore.googleDrive,
              modifiedAtIso: file['modifiedTime']?.toString(),
              sizeBytes: int.tryParse(file['size']?.toString() ?? ''),
            ),
    ]
        .where((file) =>
            file.id.isNotEmpty && !_isInternalScriptArtifact(file.name))
        .toList(growable: false);
  }

  Future<List<CloudSyncedFile>> _listDropboxDeletedScripts(
    CloudAuthorizedSession session,
  ) async {
    try {
      final deleted = _dropboxChildPath(
        _dropboxRootPath(),
        _deletedListFolderName,
      );
      await _ensureDropboxFolder(session, path: deleted);
      final decoded = await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
        token: session.accessToken,
        body: {'path': deleted, 'recursive': false},
      );
      final entries = decoded['entries'];
      if (entries is! List) return const [];
      return [
        for (final entry in entries)
          if (entry is Map<String, dynamic> && entry['.tag'] == 'file')
            CloudSyncedFile(
              id: entry['path_lower']?.toString() ?? '',
              name: entry['name']?.toString() ?? 'Untitled',
              providerId: CloudConnectionStore.dropbox,
              modifiedAtIso: entry['server_modified']?.toString(),
              sizeBytes: entry['size'] is int ? entry['size'] as int : null,
            ),
      ]
          .where((file) =>
              file.id.isNotEmpty && !_isInternalScriptArtifact(file.name))
          .toList(growable: false);
    } catch (error) {
      throw StateError(_dropboxListFailure(error));
    }
  }
}
