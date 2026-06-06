part of 'cloud_app_folder_sync_service.dart';

extension CloudAppFolderDeletedScripts on CloudAppFolderSyncService {
  static const _deletedFolderName = 'Deleted Scripts';
  static final RegExp _deletedStampRe = RegExp(r'^\d{8}_\d{6}_');

  Future<CloudSyncResult> uploadDeletedScriptFile({
    required String providerId,
    required String filePath,
    required String originalName,
    required DateTime deletedAt,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const CloudSyncResult(
        ok: false,
        message: 'Deleted-script backup no longer exists.',
      );
    }
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before syncing deleted scripts.',
      );
    }
    final fileName = _safeFileName(_basename(filePath));
    final sourceName = _safeFileName(
      originalName.trim().isEmpty
          ? _originalNameFromDeletedFileName(fileName)
          : originalName,
    );
    final bytes = await file.readAsBytes();
    final mimeType = _deletedMimeType(fileName);
    final metadataName = ScriptProjectCodec.metadataFileNameFor(fileName);
    final metadataBytes = utf8.encode(jsonEncode({
      'kind': 'autoteleprompter.deleted_script',
      'version': 1,
      'fileName': fileName,
      'originalName': sourceName,
      'deletedAt': deletedAt.toUtc().toIso8601String(),
      'retentionDays': LocalBackupService.deletedRetention.inDays,
    }));

    return switch (providerId) {
      CloudConnectionStore.googleDrive => _uploadGoogleDeletedScript(
          session: session,
          fileName: fileName,
          originalName: sourceName,
          bytes: bytes,
          mimeType: mimeType,
          metadataFileName: metadataName,
          metadataBytes: metadataBytes,
        ),
      CloudConnectionStore.dropbox => _uploadDropboxDeletedScript(
          session: session,
          fileName: fileName,
          originalName: sourceName,
          bytes: bytes,
          metadataFileName: metadataName,
          metadataBytes: metadataBytes,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support deleted script sync.',
        ),
    };
  }

  Future<CloudSyncResult> moveScriptToDeleted({
    required String providerId,
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before deleting synced scripts.',
      );
    }
    final export = await LocalBackupService.buildScriptExportAsync(
      title: title,
      text: text,
      sourceType: sourceType,
      sourcePath: sourcePath,
    );
    final metadataName = ScriptProjectCodec.metadataFileNameFor(
      export.fileName,
    );
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _moveGoogleScriptToDeleted(
          session: session,
          primaryFileName: export.fileName,
          metadataFileName: metadataName,
        ),
      CloudConnectionStore.dropbox => _moveDropboxScriptToDeleted(
          session: session,
          primaryFileName: export.fileName,
          metadataFileName: metadataName,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support deleted script sync.',
        ),
    };
  }

  Future<CloudSyncResult> moveSyncedScriptToDeleted({
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
    final metadataName = ScriptProjectCodec.metadataFileNameFor(safeName);
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _moveGoogleScriptToDeleted(
          session: session,
          primaryFileName: safeName,
          metadataFileName: metadataName,
        ),
      CloudConnectionStore.dropbox => _moveDropboxScriptToDeleted(
          session: session,
          primaryFileName: safeName,
          metadataFileName: metadataName,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support deleted script sync.',
        ),
    };
  }

  Future<CloudSyncResult> restoreDeletedScript({
    required String providerId,
    required String deletedFileName,
    required String activeFileName,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before restoring synced scripts.',
      );
    }
    final deletedName = _safeFileName(deletedFileName);
    final activeName = _safeFileName(activeFileName);
    final deletedMetadataName = ScriptProjectCodec.metadataFileNameFor(
      deletedName,
    );
    final activeMetadataName = ScriptProjectCodec.metadataFileNameFor(
      activeName,
    );
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _restoreGoogleDeletedScript(
          session: session,
          deletedFileName: deletedName,
          activeFileName: activeName,
          deletedMetadataFileName: deletedMetadataName,
          activeMetadataFileName: activeMetadataName,
        ),
      CloudConnectionStore.dropbox => _restoreDropboxDeletedScript(
          session: session,
          deletedFileName: deletedName,
          activeFileName: activeName,
          deletedMetadataFileName: deletedMetadataName,
          activeMetadataFileName: activeMetadataName,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support deleted script restore.',
        ),
    };
  }

  Future<CloudSyncResult> _moveGoogleScriptToDeleted({
    required CloudAuthorizedSession session,
    required String primaryFileName,
    required String metadataFileName,
  }) async {
    final rootId = await _googleFolderId(session);
    final deletedId = await _googleFolderId(
      session,
      folderName: _deletedFolderName,
      parentId: rootId,
    );
    final metadataId = await _googleMetadataFolderId(session);
    final deletedMetadataId = await _googleFolderId(
      session,
      folderName: CloudAppFolderSyncService._metadataFolderName,
      parentId: deletedId,
    );
    var moved = 0;

    final primaryIds = await _googleFileIdsByName(
      session: session,
      folderId: rootId,
      fileName: primaryFileName,
    );
    for (final id in primaryIds) {
      await _moveGoogleFile(
        session: session,
        fileId: id,
        fromParentId: rootId,
        toParentId: deletedId,
      );
      moved++;
    }

    final metadataIds = await _googleFileIdsByName(
      session: session,
      folderId: metadataId,
      fileName: metadataFileName,
    );
    for (final id in metadataIds) {
      await _moveGoogleFile(
        session: session,
        fileId: id,
        fromParentId: metadataId,
        toParentId: deletedMetadataId,
      );
      moved++;
    }
    await _pruneExpiredGoogleDeletedScripts(
      session: session,
      deletedId: deletedId,
      deletedMetadataId: deletedMetadataId,
    );
    return CloudSyncResult(
      ok: moved > 0,
      message: moved > 0
          ? 'Moved $primaryFileName to Google Drive Deleted Scripts.'
          : '$primaryFileName was not found in Google Drive sync.',
    );
  }

  Future<CloudSyncResult> _uploadGoogleDeletedScript({
    required CloudAuthorizedSession session,
    required String fileName,
    required String originalName,
    required List<int> bytes,
    required String mimeType,
    required String metadataFileName,
    required List<int> metadataBytes,
  }) async {
    final rootId = await _googleFolderId(session);
    final deletedId = await _googleFolderId(
      session,
      folderName: _deletedFolderName,
      parentId: rootId,
    );
    final metadataId = await _googleMetadataFolderId(session);
    final deletedMetadataId = await _googleFolderId(
      session,
      folderName: CloudAppFolderSyncService._metadataFolderName,
      parentId: deletedId,
    );

    await _deleteGoogleFileByName(
      session: session,
      folderId: rootId,
      fileName: originalName,
    );
    await _deleteGoogleFileByName(
      session: session,
      folderId: metadataId,
      fileName: ScriptProjectCodec.metadataFileNameFor(originalName),
    );

    final primaryResult = await _uploadGoogleScript(
      session: session,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      replaceExisting: true,
      folderId: deletedId,
    );
    if (!primaryResult.ok) return primaryResult;

    final metadataResult = await _uploadGoogleScript(
      session: session,
      fileName: metadataFileName,
      bytes: metadataBytes,
      mimeType: 'application/json; charset=utf-8',
      replaceExisting: true,
      folderId: deletedMetadataId,
    );
    if (!metadataResult.ok) return metadataResult;

    await _pruneExpiredGoogleDeletedScripts(
      session: session,
      deletedId: deletedId,
      deletedMetadataId: deletedMetadataId,
    );
    return CloudSyncResult(
      ok: true,
      message: 'Synced $fileName to Google Drive Deleted Scripts.',
    );
  }

  Future<void> _moveGoogleFile({
    required CloudAuthorizedSession session,
    required String fileId,
    required String fromParentId,
    required String toParentId,
    String? newName,
  }) async {
    final request = await _httpClient.patchUrl(
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'addParents': toParentId,
        'removeParents': fromParentId,
        'fields': 'id,name,parents',
      }),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    if (newName != null && newName.trim().isNotEmpty) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'name': newName}));
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_providerFailure(
        'Google Drive delete move failed',
        response.statusCode,
        body,
      ));
    }
  }

  Future<CloudSyncResult> _restoreGoogleDeletedScript({
    required CloudAuthorizedSession session,
    required String deletedFileName,
    required String activeFileName,
    required String deletedMetadataFileName,
    required String activeMetadataFileName,
  }) async {
    final rootId = await _googleFolderId(session);
    final deletedId = await _googleFolderId(
      session,
      folderName: _deletedFolderName,
      parentId: rootId,
    );
    final metadataId = await _googleMetadataFolderId(session);
    final deletedMetadataId = await _googleFolderId(
      session,
      folderName: CloudAppFolderSyncService._metadataFolderName,
      parentId: deletedId,
    );
    var moved = 0;

    final primaryIds = [
      ...await _googleFileIdsByName(
        session: session,
        folderId: deletedId,
        fileName: deletedFileName,
      ),
      if (deletedFileName != activeFileName)
        ...await _googleFileIdsByName(
          session: session,
          folderId: deletedId,
          fileName: activeFileName,
        ),
    ];
    if (primaryIds.isNotEmpty) {
      await _deleteGoogleFileByName(
        session: session,
        folderId: rootId,
        fileName: activeFileName,
      );
      for (final id in primaryIds) {
        await _moveGoogleFile(
          session: session,
          fileId: id,
          fromParentId: deletedId,
          toParentId: rootId,
          newName: activeFileName,
        );
        moved++;
      }
    }

    final metadataIds = [
      ...await _googleFileIdsByName(
        session: session,
        folderId: deletedMetadataId,
        fileName: deletedMetadataFileName,
      ),
      if (deletedMetadataFileName != activeMetadataFileName)
        ...await _googleFileIdsByName(
          session: session,
          folderId: deletedMetadataId,
          fileName: activeMetadataFileName,
        ),
    ];
    if (metadataIds.isNotEmpty) {
      await _deleteGoogleFileByName(
        session: session,
        folderId: metadataId,
        fileName: activeMetadataFileName,
      );
      for (final id in metadataIds) {
        await _moveGoogleFile(
          session: session,
          fileId: id,
          fromParentId: deletedMetadataId,
          toParentId: metadataId,
          newName: activeMetadataFileName,
        );
        moved++;
      }
    }

    return CloudSyncResult(
      ok: moved > 0,
      message: moved > 0
          ? 'Restored $activeFileName from Google Drive Deleted Scripts.'
          : '$deletedFileName was not found in Google Drive Deleted Scripts.',
    );
  }

  Future<void> _pruneExpiredGoogleDeletedScripts({
    required CloudAuthorizedSession session,
    required String deletedId,
    required String deletedMetadataId,
  }) async {
    final cutoff = DateTime.now()
        .subtract(LocalBackupService.deletedRetention)
        .toUtc()
        .toIso8601String();
    for (final folderId in [deletedId, deletedMetadataId]) {
      final decoded = await _jsonRequest(
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': "'$folderId' in parents and trashed=false and "
              "modifiedTime < '$cutoff'",
          'spaces': 'drive',
          'fields': 'files(id,name)',
        }),
        token: session.accessToken,
      );
      final files = decoded['files'];
      if (files is! List) continue;
      for (final file in files) {
        if (file is! Map) continue;
        final id = file['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _deleteGoogleFileById(session: session, fileId: id);
      }
    }
  }

  Future<void> _deleteGoogleFileById({
    required CloudAuthorizedSession session,
    required String fileId,
  }) async {
    final request = await _httpClient.deleteUrl(
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId'),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    final response = await request.close();
    await response.drain<void>();
  }

  Future<CloudSyncResult> _moveDropboxScriptToDeleted({
    required CloudAuthorizedSession session,
    required String primaryFileName,
    required String metadataFileName,
  }) async {
    final root = _dropboxRootPath();
    final metadata = _dropboxMetadataFolderPath();
    final deleted = _dropboxChildPath(root, _deletedFolderName);
    final deletedMetadata = _dropboxChildPath(
      deleted,
      CloudAppFolderSyncService._metadataFolderName,
    );
    await _ensureDropboxFolder(session, path: deletedMetadata);
    var moved = 0;

    if (await _moveDropboxPathIfExistsForDelete(
      session: session,
      fromPath: _dropboxFilePath(root, primaryFileName),
      toPath: _dropboxFilePath(deleted, primaryFileName),
    )) {
      moved++;
    }
    if (await _moveDropboxPathIfExistsForDelete(
      session: session,
      fromPath: _dropboxFilePath(metadata, metadataFileName),
      toPath: _dropboxFilePath(deletedMetadata, metadataFileName),
    )) {
      moved++;
    }

    await _pruneExpiredDropboxDeletedScripts(
      session: session,
      folders: [deleted, deletedMetadata],
    );
    return CloudSyncResult(
      ok: moved > 0,
      message: moved > 0
          ? 'Moved $primaryFileName to Dropbox Deleted Scripts.'
          : '$primaryFileName was not found in Dropbox sync.',
    );
  }

  Future<CloudSyncResult> _uploadDropboxDeletedScript({
    required CloudAuthorizedSession session,
    required String fileName,
    required String originalName,
    required List<int> bytes,
    required String metadataFileName,
    required List<int> metadataBytes,
  }) async {
    final root = _dropboxRootPath();
    final metadata = _dropboxMetadataFolderPath();
    final deleted = _dropboxChildPath(root, _deletedFolderName);
    final deletedMetadata = _dropboxChildPath(
      deleted,
      CloudAppFolderSyncService._metadataFolderName,
    );
    await _ensureDropboxFolder(session, path: deletedMetadata);
    await _deleteDropboxPathIfExists(
      session: session,
      path: _dropboxFilePath(root, originalName),
    );
    await _deleteDropboxPathIfExists(
      session: session,
      path: _dropboxFilePath(
        metadata,
        ScriptProjectCodec.metadataFileNameFor(originalName),
      ),
    );

    final primaryResult = await _uploadDropboxScript(
      session: session,
      fileName: fileName,
      bytes: bytes,
      replaceExisting: true,
      folderPath: deleted,
    );
    if (!primaryResult.ok) return primaryResult;

    final metadataResult = await _uploadDropboxScript(
      session: session,
      fileName: metadataFileName,
      bytes: metadataBytes,
      replaceExisting: true,
      folderPath: deletedMetadata,
    );
    if (!metadataResult.ok) return metadataResult;

    await _pruneExpiredDropboxDeletedScripts(
      session: session,
      folders: [deleted, deletedMetadata],
    );
    return CloudSyncResult(
      ok: true,
      message: 'Synced $fileName to Dropbox Deleted Scripts.',
    );
  }

  Future<bool> _moveDropboxPathIfExistsForDelete({
    required CloudAuthorizedSession session,
    required String fromPath,
    required String toPath,
  }) async {
    try {
      await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/move_v2'),
        token: session.accessToken,
        body: {
          'from_path': fromPath,
          'to_path': toPath,
          'allow_shared_folder': false,
          'autorename': true,
          'allow_ownership_transfer': false,
        },
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

  Future<CloudSyncResult> _restoreDropboxDeletedScript({
    required CloudAuthorizedSession session,
    required String deletedFileName,
    required String activeFileName,
    required String deletedMetadataFileName,
    required String activeMetadataFileName,
  }) async {
    final root = _dropboxRootPath();
    final metadata = _dropboxMetadataFolderPath();
    final deleted = _dropboxChildPath(root, _deletedFolderName);
    final deletedMetadata = _dropboxChildPath(
      deleted,
      CloudAppFolderSyncService._metadataFolderName,
    );
    await _ensureDropboxFolder(session, path: metadata);
    var moved = 0;

    if (await _moveDropboxPathIfExistsReplacing(
      session: session,
      fromPath: _dropboxFilePath(deleted, deletedFileName),
      toPath: _dropboxFilePath(root, activeFileName),
    )) {
      moved++;
    } else if (deletedFileName != activeFileName &&
        await _moveDropboxPathIfExistsReplacing(
          session: session,
          fromPath: _dropboxFilePath(deleted, activeFileName),
          toPath: _dropboxFilePath(root, activeFileName),
        )) {
      moved++;
    }

    if (await _moveDropboxPathIfExistsReplacing(
      session: session,
      fromPath: _dropboxFilePath(deletedMetadata, deletedMetadataFileName),
      toPath: _dropboxFilePath(metadata, activeMetadataFileName),
    )) {
      moved++;
    } else if (deletedMetadataFileName != activeMetadataFileName &&
        await _moveDropboxPathIfExistsReplacing(
          session: session,
          fromPath: _dropboxFilePath(deletedMetadata, activeMetadataFileName),
          toPath: _dropboxFilePath(metadata, activeMetadataFileName),
        )) {
      moved++;
    }

    return CloudSyncResult(
      ok: moved > 0,
      message: moved > 0
          ? 'Restored $activeFileName from Dropbox Deleted Scripts.'
          : '$deletedFileName was not found in Dropbox Deleted Scripts.',
    );
  }

  Future<bool> _moveDropboxPathIfExistsReplacing({
    required CloudAuthorizedSession session,
    required String fromPath,
    required String toPath,
  }) async {
    try {
      await _deleteDropboxPathIfExists(session: session, path: toPath);
      await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/move_v2'),
        token: session.accessToken,
        body: {
          'from_path': fromPath,
          'to_path': toPath,
          'allow_shared_folder': false,
          'autorename': false,
          'allow_ownership_transfer': false,
        },
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

  Future<void> _pruneExpiredDropboxDeletedScripts({
    required CloudAuthorizedSession session,
    required List<String> folders,
  }) async {
    final cutoff = DateTime.now().subtract(LocalBackupService.deletedRetention);
    for (final folder in folders) {
      Map<String, dynamic> decoded;
      try {
        decoded = await _jsonPost(
          Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
          token: session.accessToken,
          body: {'path': folder, 'recursive': false},
        );
      } catch (_) {
        continue;
      }
      final entries = decoded['entries'];
      if (entries is! List) continue;
      for (final entry in entries) {
        if (entry is! Map<String, dynamic> || entry['.tag'] != 'file') {
          continue;
        }
        final modified = DateTime.tryParse(
          entry['server_modified']?.toString() ?? '',
        );
        final path = entry['path_lower']?.toString() ?? '';
        if (modified == null || path.isEmpty || !modified.isBefore(cutoff)) {
          continue;
        }
        await _deleteDropboxPathIfExists(session: session, path: path);
      }
    }
  }

  String _originalNameFromDeletedFileName(String fileName) {
    return fileName.replaceFirst(_deletedStampRe, '');
  }

  String _deletedMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.rtf')) return 'application/rtf';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.odt')) {
      return 'application/vnd.oasis.opendocument.text';
    }
    if (lower.endsWith('.md')) return 'text/markdown; charset=utf-8';
    return 'text/plain; charset=utf-8';
  }
}
