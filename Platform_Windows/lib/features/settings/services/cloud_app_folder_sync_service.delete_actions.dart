part of 'cloud_app_folder_sync_service.dart';

extension CloudAppFolderDeleteActions on CloudAppFolderSyncService {
  static const _deletedFolderName = 'Deleted Scripts';

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
    for (final metadataName
        in _metadataNamesForDeleted(deletedFileName, activeFileName)) {
      if (await _deleteDropboxPathIfPresent(
        session: session,
        path: _dropboxFilePath(deletedMetadata, metadataName),
      )) {
        removed++;
      }
    }

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
}
