import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

const autoTeleprompterAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '5.0.7+31',
);

const autoTeleprompterUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
);

const autoTeleprompterUpdatePlatform = String.fromEnvironment(
  'UPDATE_PLATFORM',
  defaultValue: 'macos',
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

    final candidates = _allowedChannels(channel)
        .map((candidateChannel) {
          final entry = _channelEntry(decoded, candidateChannel);
          if (entry == null) return null;
          return _manifestCandidate(
            channelEntry: entry,
            channel: candidateChannel,
          );
        })
        .whereType<_UpdateManifestCandidate>()
        .toList(growable: false);
    if (candidates.isEmpty) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.notConfigured,
        channel: channel,
        currentVersion: autoTeleprompterAppVersion,
        message: _missingChannelMessage(channel),
      );
    }

    final newest = candidates.reduce((best, candidate) {
      final comparison =
          _compareVersions(candidate.latestVersion, best.latestVersion);
      return comparison > 0 ? candidate : best;
    });
    final comparison = _compareVersions(
      newest.latestVersion,
      autoTeleprompterAppVersion,
    );
    if (comparison <= 0) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        channel: newest.channel,
        currentVersion: autoTeleprompterAppVersion,
        latestVersion: newest.latestVersion,
        downloadUrl: newest.downloadUrl,
        notes: newest.notes,
        publishedAt: newest.publishedAt,
        message: _upToDateMessage(channel, newest.channel),
      );
    }
    return UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      channel: newest.channel,
      currentVersion: autoTeleprompterAppVersion,
      latestVersion: newest.latestVersion,
      downloadUrl: newest.downloadUrl,
      notes: newest.notes,
      publishedAt: newest.publishedAt,
      message: _updateAvailableMessage(channel, newest.channel),
    );
  }

  _UpdateManifestCandidate? _manifestCandidate({
    required Map<String, dynamic> channelEntry,
    required String channel,
  }) {
    final platformEntry = _platformEntry(channelEntry);
    if (platformEntry == null) return null;
    final latestVersion = _stringValue(platformEntry, 'version');
    final downloadUrl = _stringValue(platformEntry, 'url') ??
        _stringValue(platformEntry, 'downloadUrl') ??
        _stringValue(platformEntry, 'packageUrl');
    if (latestVersion == null || latestVersion.trim().isEmpty) {
      throw FormatException('Manifest is missing $channel.version.');
    }
    final notes = _stringValue(platformEntry, 'notes') ??
        _stringValue(platformEntry, 'releaseNotes');
    final publishedAtText = _stringValue(platformEntry, 'publishedAt');
    final publishedAt = publishedAtText == null
        ? null
        : DateTime.tryParse(publishedAtText)?.toLocal();
    return _UpdateManifestCandidate(
      channel: channel,
      latestVersion: latestVersion.trim(),
      downloadUrl: downloadUrl,
      notes: notes,
      publishedAt: publishedAt,
    );
  }

  static List<String> _allowedChannels(String selectedChannel) {
    switch (selectedChannel) {
      case AppSettings.updateChannelInternal:
        return const [
          AppSettings.updateChannelInternal,
          AppSettings.updateChannelBeta,
          AppSettings.updateChannelStable,
        ];
      case AppSettings.updateChannelBeta:
        return const [
          AppSettings.updateChannelBeta,
          AppSettings.updateChannelStable,
        ];
      default:
        return const [AppSettings.updateChannelStable];
    }
  }

  static String _missingChannelMessage(String selectedChannel) {
    final platform = _displayPlatform();
    switch (selectedChannel) {
      case AppSettings.updateChannelInternal:
        return 'No internal, beta, or stable $platform update channel is '
            'published in this manifest yet.';
      case AppSettings.updateChannelBeta:
        return 'No beta or stable $platform update channel is published in '
            'this manifest yet.';
      default:
        return 'No stable $platform update channel is published in this '
            'manifest yet.';
    }
  }

  static String _upToDateMessage(String selectedChannel, String newestChannel) {
    if (selectedChannel == newestChannel) {
      return 'You are already on the latest $newestChannel build.';
    }
    return 'You are already on the latest build allowed by the '
        '$selectedChannel channel. Latest available source: $newestChannel.';
  }

  static String _updateAvailableMessage(
    String selectedChannel,
    String newestChannel,
  ) {
    if (selectedChannel == newestChannel) {
      return 'A newer $newestChannel build is available.';
    }
    return 'A newer $newestChannel build is available through the '
        '$selectedChannel update channel.';
  }

  Map<String, dynamic>? _channelEntry(
    Map<String, dynamic> root,
    String channel,
  ) {
    final channels = root['channels'];
    final raw =
        channels is Map<String, dynamic> ? channels[channel] : root[channel];
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  Map<String, dynamic>? _platformEntry(Map<String, dynamic> channelEntry) {
    final nested = _nestedPlatformEntry(channelEntry);
    if (nested != null) {
      return <String, dynamic>{
        ...channelEntry,
        ...nested,
      };
    }
    return _entryTargetsCurrentPlatform(channelEntry) ? channelEntry : null;
  }

  Map<String, dynamic>? _nestedPlatformEntry(
    Map<String, dynamic> channelEntry,
  ) {
    final platforms = channelEntry['platforms'];
    if (platforms is Map<String, dynamic>) {
      final match = _mapValueForCurrentPlatform(platforms);
      if (match != null) return match;
    }
    final assets = channelEntry['assets'];
    if (assets is Map<String, dynamic>) {
      final match = _mapValueForCurrentPlatform(assets);
      if (match != null) return match;
    }
    if (assets is List) {
      for (final asset in assets.whereType<Map<String, dynamic>>()) {
        if (_entryTargetsCurrentPlatform(asset)) return asset;
      }
    }
    for (final alias in _currentPlatformAliases()) {
      final value = channelEntry[alias];
      if (value is Map<String, dynamic>) return value;
    }
    return null;
  }

  static Map<String, dynamic>? _mapValueForCurrentPlatform(
    Map<String, dynamic> values,
  ) {
    for (final entry in values.entries) {
      if (!_isCurrentPlatformAlias(entry.key)) continue;
      final value = entry.value;
      if (value is Map<String, dynamic>) return value;
    }
    return null;
  }

  static bool _entryTargetsCurrentPlatform(Map<String, dynamic> entry) {
    final declared = _declaredPlatforms(entry).toList(growable: false);
    if (declared.isNotEmpty) {
      return declared.any(_isCurrentPlatformAlias);
    }
    return _containsCurrentPlatformMarker(_platformMarkerText(entry));
  }

  static Iterable<String> _declaredPlatforms(Map<String, dynamic> entry) sync* {
    for (final key in const [
      'platform',
      'os',
      'targetPlatform',
      'platformName',
    ]) {
      final value = entry[key];
      if (value is String && value.trim().isNotEmpty) {
        yield* value
            .split(RegExp(r'[^A-Za-z0-9_-]+'))
            .where((part) => part.trim().isNotEmpty);
      }
    }
    final platforms = entry['platforms'];
    if (platforms is List) {
      for (final value in platforms.whereType<String>()) {
        yield* value
            .split(RegExp(r'[^A-Za-z0-9_-]+'))
            .where((part) => part.trim().isNotEmpty);
      }
    }
  }

  static String _platformMarkerText(Map<String, dynamic> entry) {
    return [
      _stringValue(entry, 'asset'),
      _stringValue(entry, 'tag'),
      _stringValue(entry, 'url'),
      _stringValue(entry, 'downloadUrl'),
      _stringValue(entry, 'packageUrl'),
    ].whereType<String>().join(' ').toLowerCase();
  }

  static bool _containsCurrentPlatformMarker(String text) {
    for (final alias in _currentPlatformAliases()) {
      final pattern = RegExp('(^|[^a-z0-9])$alias([^a-z0-9]|\$)');
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  static bool _isCurrentPlatformAlias(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _currentPlatformAliases().contains(normalized);
  }

  static List<String> _currentPlatformAliases() {
    final normalized = autoTeleprompterUpdatePlatform
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    switch (normalized) {
      case 'macos':
      case 'darwin':
      case 'osx':
        return const ['macos', 'darwin', 'osx', 'mac'];
      default:
        return [normalized];
    }
  }

  static String _displayPlatform() {
    final normalized = autoTeleprompterUpdatePlatform
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'macos' ? 'macOS' : autoTeleprompterUpdatePlatform;
  }

  static String _normalizeChannel(String channel) {
    switch (channel) {
      case AppSettings.updateChannelBeta:
      case AppSettings.updateChannelInternal:
        return channel;
      default:
        return AppSettings.updateChannelStable;
    }
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

class _UpdateManifestCandidate {
  final String channel;
  final String latestVersion;
  final String? downloadUrl;
  final String? notes;
  final DateTime? publishedAt;

  const _UpdateManifestCandidate({
    required this.channel,
    required this.latestVersion,
    this.downloadUrl,
    this.notes,
    this.publishedAt,
  });
}
