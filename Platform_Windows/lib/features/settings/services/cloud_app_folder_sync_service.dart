import 'dart:convert';
import 'dart:io';

import 'cloud_connection_store.dart';
import 'cloud_oauth_service.dart';

const dropboxSyncRootPath = String.fromEnvironment('DROPBOX_SYNC_ROOT_PATH',
    defaultValue: '/AutoTeleprompter');

class CloudSyncedFile {
  final String id;
  final String name;
  final String providerId;
  final String? modifiedAtIso;
  final int? sizeBytes;

  const CloudSyncedFile({
    required this.id,
    required this.name,
    required this.providerId,
    this.modifiedAtIso,
    this.sizeBytes,
  });
}

class CloudSyncResult {
  final bool ok;
  final String message;

  const CloudSyncResult({
    required this.ok,
    required this.message,
  });
}

class CloudAppFolderSyncService {
  static const _folderName = 'AutoTeleprompter';
  static const _recordingsFolderName = 'Recordings';

  CloudAppFolderSyncService({
    CloudOAuthService? oauth,
    HttpClient? httpClient,
  })  : _oauth = oauth ?? CloudOAuthService(),
        _httpClient = httpClient ?? HttpClient();

  final CloudOAuthService _oauth;
  final HttpClient _httpClient;

  Future<List<CloudSyncedFile>> listScripts(String providerId) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) return const [];
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _listGoogleScripts(session),
      CloudConnectionStore.dropbox => _listDropboxScripts(session),
      _ => const <CloudSyncedFile>[],
    };
  }

  Future<CloudSyncResult> uploadScript({
    required String providerId,
    required String title,
    required String text,
    String? fileName,
    List<int>? bytes,
    String mimeType = 'text/plain; charset=utf-8',
    bool replaceExisting = false,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before uploading.',
      );
    }
    final safeTitle = _safeFileName(title.isEmpty ? 'Untitled script' : title);
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final resolvedFileName = fileName ?? '$safeTitle-$timestamp.atp.txt';
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _uploadGoogleScript(
          session: session,
          fileName: resolvedFileName,
          bytes: bytes ?? utf8.encode(text),
          mimeType: mimeType,
          replaceExisting: replaceExisting,
        ),
      CloudConnectionStore.dropbox => _uploadDropboxScript(
          session: session,
          fileName: resolvedFileName,
          bytes: bytes ?? utf8.encode(text),
          replaceExisting: replaceExisting,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support account sync yet.',
        ),
    };
  }

  Future<CloudSyncResult> uploadRecording({
    required String providerId,
    required String sourcePath,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) {
      return const CloudSyncResult(
        ok: false,
        message: 'Connect this cloud account before uploading recordings.',
      );
    }
    final file = File(sourcePath);
    if (!await file.exists()) {
      return const CloudSyncResult(
        ok: false,
        message: 'Recording file no longer exists.',
      );
    }
    final fileName = _safeFileName(_basename(sourcePath));
    final bytes = await file.readAsBytes();
    final mimeType = _recordingMimeType(fileName);
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _uploadGoogleRecording(
          session: session,
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
        ),
      CloudConnectionStore.dropbox => _uploadDropboxRecording(
          session: session,
          fileName: fileName,
          bytes: bytes,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support recording upload yet.',
        ),
    };
  }

  Future<String?> downloadScript({
    required String providerId,
    required String fileId,
  }) async {
    final session = await _oauth.authorizeAccount(providerId);
    if (session == null) return null;
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _downloadGoogleScript(
          session: session,
          fileId: fileId,
        ),
      CloudConnectionStore.dropbox => _downloadDropboxScript(
          session: session,
          path: fileId,
        ),
      _ => null,
    };
  }

  Future<List<CloudSyncedFile>> _listGoogleScripts(
    CloudAuthorizedSession session,
  ) async {
    final folderId = await _googleFolderId(session);
    final query = "'$folderId' in parents and trashed=false";
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': query,
      'spaces': 'drive',
      'orderBy': 'modifiedTime desc',
      'fields': 'files(id,name,modifiedTime,size)',
    });
    final decoded = await _jsonRequest(uri, token: session.accessToken);
    final files = decoded['files'];
    if (files is! List) return const [];
    return [
      for (final file in files)
        if (file is Map<String, dynamic>)
          CloudSyncedFile(
            id: file['id']?.toString() ?? '',
            name: file['name']?.toString() ?? 'Untitled',
            providerId: CloudConnectionStore.googleDrive,
            modifiedAtIso: file['modifiedTime']?.toString(),
            sizeBytes: int.tryParse(file['size']?.toString() ?? ''),
          ),
    ].where((file) => file.id.isNotEmpty).toList(growable: false);
  }

  Future<CloudSyncResult> _uploadGoogleScript({
    required CloudAuthorizedSession session,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
    required bool replaceExisting,
    String? folderId,
  }) async {
    final targetFolderId = folderId ?? await _googleFolderId(session);
    if (replaceExisting) {
      final existingId = await _googleFileIdByName(
        session: session,
        folderId: targetFolderId,
        fileName: fileName,
      );
      if (existingId != null) {
        return _updateGoogleScriptContent(
          session: session,
          fileId: existingId,
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
        );
      }
    }
    final boundary = 'atp-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': fileName,
      'parents': [targetFolderId],
      'mimeType': mimeType.split(';').first.trim(),
    });
    final header = [
      '--$boundary',
      'Content-Type: application/json; charset=UTF-8',
      '',
      metadata,
      '--$boundary',
      'Content-Type: $mimeType',
      '',
      '',
    ].join('\r\n');
    final footer = [
      '',
      '--$boundary--',
      '',
    ].join('\r\n');
    final bodyBytes = [
      ...utf8.encode(header),
      ...bytes,
      ...utf8.encode(footer),
    ];
    final request = await _httpClient.postUrl(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id,name',
      }),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    request.headers
        .set('Content-Type', 'multipart/related; boundary=$boundary');
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return CloudSyncResult(
        ok: false,
        message: _providerFailure(
          'Google Drive upload failed',
          response.statusCode,
          responseBody,
        ),
      );
    }
    final decoded = jsonDecode(responseBody);
    final name = decoded is Map<String, dynamic> ? decoded['name'] : fileName;
    return CloudSyncResult(
        ok: true, message: 'Uploaded $name to Google Drive.');
  }

  Future<CloudSyncResult> _uploadGoogleRecording({
    required CloudAuthorizedSession session,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final rootId = await _googleFolderId(session);
    final recordingsId = await _googleFolderId(
      session,
      folderName: _recordingsFolderName,
      parentId: rootId,
    );
    return _uploadGoogleScript(
      session: session,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      replaceExisting: true,
      folderId: recordingsId,
    );
  }

  Future<CloudSyncResult> _updateGoogleScriptContent({
    required CloudAuthorizedSession session,
    required String fileId,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final request = await _httpClient.patchUrl(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files/$fileId', {
        'uploadType': 'media',
        'fields': 'id,name',
      }),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    request.headers.set(HttpHeaders.contentTypeHeader, mimeType);
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return CloudSyncResult(
        ok: false,
        message: _providerFailure(
          'Google Drive sync failed',
          response.statusCode,
          responseBody,
        ),
      );
    }
    return CloudSyncResult(
      ok: true,
      message: 'Synced $fileName to Google Drive.',
    );
  }

  Future<String?> _downloadGoogleScript({
    required CloudAuthorizedSession session,
    required String fileId,
  }) async {
    final request = await _httpClient.getUrl(
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'alt': 'media',
      }),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return response.statusCode >= 200 && response.statusCode < 300
        ? body
        : null;
  }

  Future<String> _googleFolderId(
    CloudAuthorizedSession session, {
    String folderName = _folderName,
    String? parentId,
  }) async {
    final parentClause = parentId == null ? '' : " and '$parentId' in parents";
    final query = "mimeType='application/vnd.google-apps.folder' and "
        "name=${_driveQueryLiteral(folderName)} and trashed=false$parentClause";
    final list = await _jsonRequest(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id,name)',
      }),
      token: session.accessToken,
    );
    final files = list['files'];
    if (files is List && files.isNotEmpty && files.first is Map) {
      final id = (files.first as Map)['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    final request = await _httpClient.postUrl(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'fields': 'id',
      }),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'name': folderName,
      'mimeType': 'application/vnd.google-apps.folder',
      if (parentId != null) 'parents': [parentId],
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google folder create failed (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    return (decoded as Map<String, dynamic>)['id'].toString();
  }

  Future<String?> _googleFileIdByName({
    required CloudAuthorizedSession session,
    required String folderId,
    required String fileName,
  }) async {
    final query =
        "'$folderId' in parents and name=${_driveQueryLiteral(fileName)} and trashed=false";
    final decoded = await _jsonRequest(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id,name)',
      }),
      token: session.accessToken,
    );
    final files = decoded['files'];
    if (files is List && files.isNotEmpty && files.first is Map) {
      return (files.first as Map)['id']?.toString();
    }
    return null;
  }

  Future<List<CloudSyncedFile>> _listDropboxScripts(
    CloudAuthorizedSession session,
  ) async {
    final folderPath = _dropboxRootPath();
    await _ensureDropboxFolder(session, path: folderPath);
    final decoded = await _jsonPost(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      token: session.accessToken,
      body: {'path': folderPath, 'recursive': false},
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
    ].where((file) => file.id.isNotEmpty).toList(growable: false);
  }

  Future<CloudSyncResult> _uploadDropboxScript({
    required CloudAuthorizedSession session,
    required String fileName,
    required List<int> bytes,
    required bool replaceExisting,
    String? folderPath,
  }) async {
    final targetFolderPath = folderPath ?? _dropboxRootPath();
    await _ensureDropboxFolder(session, path: targetFolderPath);
    final request = await _httpClient.postUrl(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    request.headers.set(
        'Dropbox-API-Arg',
        jsonEncode({
          'path': _dropboxFilePath(targetFolderPath, fileName),
          'mode': replaceExisting ? 'overwrite' : 'add',
          'autorename': !replaceExisting,
          'mute': false,
        }));
    request.headers.contentType = ContentType.binary;
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      return CloudSyncResult(
        ok: false,
        message: _providerFailure(
          'Dropbox upload failed',
          response.statusCode,
          body,
        ),
      );
    }
    return CloudSyncResult(
      ok: true,
      message: replaceExisting
          ? 'Synced $fileName to Dropbox${_dropboxPathLabel(targetFolderPath)}.'
          : 'Uploaded $fileName to Dropbox${_dropboxPathLabel(targetFolderPath)}.',
    );
  }

  Future<CloudSyncResult> _uploadDropboxRecording({
    required CloudAuthorizedSession session,
    required String fileName,
    required List<int> bytes,
  }) async {
    return _uploadDropboxScript(
      session: session,
      fileName: fileName,
      bytes: bytes,
      replaceExisting: true,
      folderPath: _dropboxChildPath(_dropboxRootPath(), _recordingsFolderName),
    );
  }

  Future<String?> _downloadDropboxScript({
    required CloudAuthorizedSession session,
    required String path,
  }) async {
    final request = await _httpClient.postUrl(
      Uri.parse('https://content.dropboxapi.com/2/files/download'),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    request.headers.set('Dropbox-API-Arg', jsonEncode({'path': path}));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return response.statusCode >= 200 && response.statusCode < 300
        ? body
        : null;
  }

  Future<void> _ensureDropboxFolder(
    CloudAuthorizedSession session, {
    String path = '/$_folderName',
  }) async {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      await _createDropboxFolderIfNeeded(session, current);
    }
  }

  String _dropboxRootPath() {
    final configured = dropboxSyncRootPath
        .replaceAll(RegExp(r'\\+'), '/')
        .replaceAll(RegExp(r'/+'), '/')
        .trim();
    if (configured.isEmpty || configured == '/' || configured == '.') {
      return '';
    }
    final noTrailing = configured.replaceFirst(RegExp(r'/+$'), '');
    return noTrailing.startsWith('/') ? noTrailing : '/$noTrailing';
  }

  String _dropboxChildPath(String parent, String child) {
    final safeChild = child.replaceAll(RegExp(r'^/+|/+$'), '');
    if (parent.isEmpty) return '/$safeChild';
    return '$parent/$safeChild';
  }

  String _dropboxFilePath(String folderPath, String fileName) {
    if (folderPath.isEmpty) return '/$fileName';
    return '$folderPath/$fileName';
  }

  String _dropboxPathLabel(String folderPath) {
    if (folderPath.isEmpty) return ' app folder root';
    return ' $folderPath';
  }

  Future<void> _createDropboxFolderIfNeeded(
    CloudAuthorizedSession session,
    String path,
  ) async {
    try {
      await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/create_folder_v2'),
        token: session.accessToken,
        body: {'path': path, 'autorename': false},
      );
    } catch (_) {
      // Existing folder is acceptable; list/upload will report real failures.
    }
  }

  Future<Map<String, dynamic>> _jsonRequest(
    Uri uri, {
    required String token,
  }) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('cloud request failed (${response.statusCode}): $body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('cloud request returned invalid JSON');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _jsonPost(
    Uri uri, {
    required String token,
    required Map<String, Object?> body,
  }) async {
    final request = await _httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'cloud request failed (${response.statusCode}): $responseBody',
      );
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('cloud request returned invalid JSON');
    }
    return decoded;
  }

  static String _safeFileName(String title) {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.isEmpty ? 'Untitled script' : clean;
  }

  static String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  static String _recordingMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }

  static String stableScriptFileName(String title) {
    final safeTitle = _safeFileName(title.isEmpty ? 'Untitled script' : title);
    if (RegExp(r'\.(?:docx?|rtf|txt)$', caseSensitive: false)
        .hasMatch(safeTitle)) {
      return safeTitle;
    }
    final baseName = safeTitle.replaceFirst(
      RegExp(r'\.(?:docx?|rtf|txt|pdf|atp\.txt)$', caseSensitive: false),
      '',
    );
    return '${baseName.isEmpty ? 'Untitled script' : baseName}.txt';
  }

  String _driveQueryLiteral(String value) {
    return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
  }

  String _providerFailure(String prefix, int statusCode, String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '$prefix ($statusCode).';
    final clipped =
        compact.length > 220 ? '${compact.substring(0, 220)}...' : compact;
    return '$prefix ($statusCode): $clipped';
  }
}
