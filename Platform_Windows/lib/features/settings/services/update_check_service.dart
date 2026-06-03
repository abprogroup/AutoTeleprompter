import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

const autoTeleprompterAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '5.0.5+20',
);

const autoTeleprompterUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
);

enum UpdateCheckStatus {
  notConfigured,
  upToDate,
  updateAvailable,
  failed,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String channel;
  final String currentVersion;
  final String? latestVersion;
  final String? downloadUrl;
  final String message;
  final String? notes;
  final DateTime? publishedAt;

  const UpdateCheckResult({
    required this.status,
    required this.channel,
    required this.currentVersion,
    required this.message,
    this.latestVersion,
    this.downloadUrl,
    this.notes,
    this.publishedAt,
  });

  bool get hasDownload => downloadUrl != null && downloadUrl!.trim().isNotEmpty;
}

class UpdateCheckService {
  UpdateCheckService({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<UpdateCheckResult> check({
    required String channel,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final normalizedChannel = _normalizeChannel(channel);
    final manifestUrl = autoTeleprompterUpdateManifestUrl.trim();
    if (manifestUrl.isEmpty) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.notConfigured,
        channel: normalizedChannel,
        currentVersion: autoTeleprompterAppVersion,
        message: 'Update checking is not connected in this build yet.',
      );
    }

    final uri = Uri.tryParse(manifestUrl);
    if (uri == null || !_isAllowedManifestUri(uri)) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        channel: normalizedChannel,
        currentVersion: autoTeleprompterAppVersion,
        message: 'Update manifest URL is invalid or not HTTPS.',
      );
    }

    try {
      final request = await _httpClient.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.failed,
          channel: normalizedChannel,
          currentVersion: autoTeleprompterAppVersion,
          message: 'Update server returned HTTP ${response.statusCode}.',
        );
      }
      return _parseManifest(body, normalizedChannel);
    } catch (error) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.failed,
        channel: normalizedChannel,
        currentVersion: autoTeleprompterAppVersion,
        message: 'Update check failed: $error',
      );
    }
  }

  UpdateCheckResult _parseManifest(String body, String channel) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manifest root must be a JSON object.');
    }

    final channelEntry = _channelEntry(decoded, channel);
    final latestVersion = _stringValue(channelEntry, 'version');
    final downloadUrl = _stringValue(channelEntry, 'url') ??
        _stringValue(channelEntry, 'downloadUrl');
    if (latestVersion == null || latestVersion.trim().isEmpty) {
      throw FormatException('Manifest is missing $channel.version.');
    }

    final notes = _stringValue(channelEntry, 'notes') ??
        _stringValue(channelEntry, 'releaseNotes');
    final publishedAtText = _stringValue(channelEntry, 'publishedAt');
    final publishedAt = publishedAtText == null
        ? null
        : DateTime.tryParse(publishedAtText)?.toLocal();
    final comparison = _compareVersions(
      latestVersion.trim(),
      autoTeleprompterAppVersion,
    );
    if (comparison <= 0) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        channel: channel,
        currentVersion: autoTeleprompterAppVersion,
        latestVersion: latestVersion.trim(),
        downloadUrl: downloadUrl,
        notes: notes,
        publishedAt: publishedAt,
        message: 'You are already on the latest $channel build.',
      );
    }
    return UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      channel: channel,
      currentVersion: autoTeleprompterAppVersion,
      latestVersion: latestVersion.trim(),
      downloadUrl: downloadUrl,
      notes: notes,
      publishedAt: publishedAt,
      message: 'A newer $channel build is available.',
    );
  }

  Map<String, dynamic> _channelEntry(
    Map<String, dynamic> root,
    String channel,
  ) {
    final channels = root['channels'];
    final raw =
        channels is Map<String, dynamic> ? channels[channel] : root[channel];
    if (raw is Map<String, dynamic>) return raw;
    throw FormatException('Manifest is missing a $channel channel object.');
  }

  static String _normalizeChannel(String channel) {
    return channel == AppSettings.updateChannelBeta
        ? AppSettings.updateChannelBeta
        : AppSettings.updateChannelStable;
  }

  static bool _isAllowedManifestUri(Uri uri) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    return uri.host == 'localhost' || uri.host == '127.0.0.1';
  }

  static String? _stringValue(Map<String, dynamic> source, String key) {
    final value = source[key];
    return value is String ? value.trim() : null;
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
    final normalized = version.replaceAll('+', '.').replaceAll('-', '.');
    return normalized
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList(growable: false);
  }
}
