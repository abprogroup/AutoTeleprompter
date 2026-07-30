import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_check_service.dart';

class UpdateDownloadService {
  UpdateDownloadService({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<File> download(UpdateCheckResult result) async {
    final url = result.downloadUrl?.trim();
    if (url == null || url.isEmpty) {
      throw const FormatException('Update download URL is missing.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !_isAllowedDownloadUri(uri)) {
      throw const FormatException(
        'Update download URL is invalid or not HTTPS.',
      );
    }

    final directory = await _updatesDirectory();
    await directory.create(recursive: true);
    final file = File(
      _joinPath(directory.path, _downloadFileName(uri, result.latestVersion)),
    );
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();

    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final response = await request.close().timeout(const Duration(minutes: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Update server returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    await response.pipe(partial.openWrite());
    if (await file.exists()) await file.delete();
    await partial.rename(file.path);
    return file;
  }

  static bool _isAllowedDownloadUri(Uri uri) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    return uri.host == 'localhost' || uri.host == '127.0.0.1';
  }

  /// Must match the `<cache-path>` declared in
  /// `android/app/src/main/res/xml/file_paths.xml` (the FileProvider config
  /// that grants the system package installer temporary read access to the
  /// downloaded APK).
  static Future<Directory> _updatesDirectory() async {
    final cacheDir = await getTemporaryDirectory();
    return Directory(_joinPath(cacheDir.path, 'app_updates'));
  }

  static String _downloadFileName(Uri uri, String? latestVersion) {
    final raw = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final decoded = Uri.decodeComponent(raw).trim();
    final fallbackVersion = (latestVersion ?? 'update').replaceAll('+', '-');
    final name = decoded.isEmpty || !decoded.contains('.')
        ? 'AutoTeleprompter-Android-$fallbackVersion.apk'
        : decoded;
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  static String _joinPath(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) return '$left$right';
    return '$left${Platform.pathSeparator}$right';
  }
}
