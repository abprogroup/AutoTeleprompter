import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'settings_error_sanitizer.dart';

/// Optional App Store region (two-letter country code) for the lookup, in case
/// the app is published in a specific storefront. Empty uses the default.
const autoTeleprompterAppStoreRegion = String.fromEnvironment(
  'APP_STORE_REGION',
);

enum UpdateCheckStatus {
  upToDate,
  updateAvailable,
  notPublished,
  failed,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? appStoreUrl;
  final String message;
  final String? notes;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    required this.message,
    this.latestVersion,
    this.appStoreUrl,
    this.notes,
  });

  bool get hasStorePage =>
      appStoreUrl != null && appStoreUrl!.trim().isNotEmpty;

  bool get isUpdateAvailable => status == UpdateCheckStatus.updateAvailable;
}

/// Standard iOS update check: queries the public iTunes Lookup API for the
/// version Apple has published for this bundle id, compares it to the installed
/// version, and (when newer) points the user at the App Store. iOS apps update
/// through the App Store / TestFlight automatically, so the in-app step is just
/// a courtesy prompt that deep-links to the store page.
class UpdateCheckService {
  UpdateCheckService({
    HttpClient? httpClient,
    Future<PackageInfo> Function()? packageInfoProvider,
  })  : _httpClient = httpClient ?? HttpClient(),
        _packageInfoProvider =
            packageInfoProvider ?? PackageInfo.fromPlatform;

  final HttpClient _httpClient;
  final Future<PackageInfo> Function() _packageInfoProvider;

  Future<UpdateCheckResult> check({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    String currentVersion = '0.0.0';
    try {
      final info = await _packageInfoProvider();
      currentVersion =
          info.version.trim().isEmpty ? '0.0.0' : info.version.trim();
      final bundleId = info.packageName.trim();
      if (bundleId.isEmpty) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          currentVersion: currentVersion,
          message: 'Could not read this app\'s bundle identifier.',
        );
      }

      final params = {
        'bundleId': bundleId,
        if (autoTeleprompterAppStoreRegion.trim().isNotEmpty)
          'country': autoTeleprompterAppStoreRegion.trim(),
        // Cache-bust so we do not read a stale store edge response.
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      final uri = Uri.https('itunes.apple.com', '/lookup', params);

      final request = await _httpClient.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          currentVersion: currentVersion,
          message: 'App Store lookup returned HTTP ${response.statusCode}.',
        );
      }
      return _parseLookup(body, currentVersion);
    } on TimeoutException {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        currentVersion: currentVersion,
        message: 'Update check timed out. Check your connection and retry.',
      );
    } catch (error) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        currentVersion: currentVersion,
        message: 'Update check failed: ${sanitizeSettingsErrorForUser(error)}',
      );
    }
  }

  UpdateCheckResult _parseLookup(String body, String currentVersion) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        currentVersion: currentVersion,
        message: 'App Store returned an unexpected response.',
      );
    }
    final results = decoded['results'];
    if (results is! List || results.isEmpty) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.notPublished,
        currentVersion: currentVersion,
        message: 'This build is not on the App Store yet. Once published, '
            'updates arrive automatically through the App Store / TestFlight.',
      );
    }
    final entry = results.first;
    if (entry is! Map<String, dynamic>) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        currentVersion: currentVersion,
        message: 'App Store entry was malformed.',
      );
    }
    final latest = (entry['version']?.toString() ?? '').trim();
    final storeUrl = (entry['trackViewUrl']?.toString() ?? '').trim();
    final notes = (entry['releaseNotes']?.toString() ?? '').trim();
    if (latest.isEmpty) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        currentVersion: currentVersion,
        message: 'App Store did not report a published version.',
      );
    }

    final newer = _compareVersions(latest, currentVersion) > 0;
    if (!newer) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: latest,
        appStoreUrl: storeUrl.isEmpty ? null : storeUrl,
        message: 'You are on the latest App Store version ($latest).',
      );
    }
    return UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      currentVersion: currentVersion,
      latestVersion: latest,
      appStoreUrl: storeUrl.isEmpty ? null : storeUrl,
      notes: notes.isEmpty ? null : notes,
      message: 'Version $latest is available on the App Store.',
    );
  }

  static int _compareVersions(String left, String right) {
    final a = _versionParts(left);
    final b = _versionParts(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    // App Store versions are CFBundleShortVersionString (e.g. 5.0.8); ignore
    // any build-metadata suffix.
    final normalized = version.split('+').first.replaceAll('-', '.');
    return normalized
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList(growable: false);
  }
}
