import 'dart:convert';
import 'dart:io';

import 'cloud_connection_store.dart';
import 'cloud_oauth_service.dart';

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
    final fileName = '$safeTitle-$timestamp.atp.txt';
    return switch (providerId) {
      CloudConnectionStore.googleDrive => _uploadGoogleScript(
          session: session,
          fileName: fileName,
          text: text,
        ),
      CloudConnectionStore.dropbox => _uploadDropboxScript(
          session: session,
          fileName: fileName,
          text: text,
        ),
      _ => const CloudSyncResult(
          ok: false,
          message: 'This provider does not support account sync yet.',
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
    required String text,
  }) async {
    final folderId = await _googleFolderId(session);
    final boundary = 'atp-${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': fileName,
      'parents': [folderId],
      'mimeType': 'text/plain',
    });
    final body = [
      '--$boundary',
      'Content-Type: application/json; charset=UTF-8',
      '',
      metadata,
      '--$boundary',
      'Content-Type: text/plain; charset=UTF-8',
      '',
      text,
      '--$boundary--',
      '',
    ].join('\r\n');
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
    request.write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return CloudSyncResult(
        ok: false,
        message: 'Google Drive upload failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(responseBody);
    final name = decoded is Map<String, dynamic> ? decoded['name'] : fileName;
    return CloudSyncResult(
        ok: true, message: 'Uploaded $name to Google Drive.');
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

  Future<String> _googleFolderId(CloudAuthorizedSession session) async {
    const query =
        "mimeType='application/vnd.google-apps.folder' and name='AutoTeleprompter' and trashed=false";
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
      'name': _folderName,
      'mimeType': 'application/vnd.google-apps.folder',
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google folder create failed (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    return (decoded as Map<String, dynamic>)['id'].toString();
  }

  Future<List<CloudSyncedFile>> _listDropboxScripts(
    CloudAuthorizedSession session,
  ) async {
    await _ensureDropboxFolder(session);
    final decoded = await _jsonPost(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      token: session.accessToken,
      body: {'path': '/$_folderName', 'recursive': false},
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
    required String text,
  }) async {
    await _ensureDropboxFolder(session);
    final request = await _httpClient.postUrl(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
    );
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
    request.headers.set(
        'Dropbox-API-Arg',
        jsonEncode({
          'path': '/$_folderName/$fileName',
          'mode': 'add',
          'autorename': true,
          'mute': false,
        }));
    request.headers.contentType = ContentType.binary;
    request.add(utf8.encode(text));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return CloudSyncResult(
        ok: false,
        message: 'Dropbox upload failed (${response.statusCode}).',
      );
    }
    return CloudSyncResult(ok: true, message: 'Uploaded $fileName to Dropbox.');
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

  Future<void> _ensureDropboxFolder(CloudAuthorizedSession session) async {
    try {
      await _jsonPost(
        Uri.parse('https://api.dropboxapi.com/2/files/create_folder_v2'),
        token: session.accessToken,
        body: {'path': '/$_folderName', 'autorename': false},
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

  String _safeFileName(String title) {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.isEmpty ? 'Untitled script' : clean;
  }
}
