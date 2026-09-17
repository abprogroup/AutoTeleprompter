import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

typedef WebView2VersionReader = Future<String?> Function();

enum WebView2RuntimeProbeStatus { available, notInstalled, unreadable }

/// A non-sensitive result from probing the installed Evergreen WebView2 runtime.
class WebView2RuntimeProbeResult {
  const WebView2RuntimeProbeResult._({required this.status, this.exactVersion});

  const WebView2RuntimeProbeResult.available(String version)
    : this._(
        status: WebView2RuntimeProbeStatus.available,
        exactVersion: version,
      );

  const WebView2RuntimeProbeResult.notInstalled()
    : this._(status: WebView2RuntimeProbeStatus.notInstalled);

  const WebView2RuntimeProbeResult.unreadable()
    : this._(status: WebView2RuntimeProbeStatus.unreadable);

  final WebView2RuntimeProbeStatus status;
  final String? exactVersion;
}

/// Reads the installed WebView2 version without allowing plugin failures to
/// escape into the presentation startup path.
class SafeWebView2RuntimeProbe {
  SafeWebView2RuntimeProbe({
    WebView2VersionReader? versionReader,
    this.timeout = const Duration(seconds: 3),
  }) : _versionReader = versionReader ?? WebviewController.getWebViewVersion,
       assert(timeout > Duration.zero);

  final WebView2VersionReader _versionReader;
  final Duration timeout;

  Future<WebView2RuntimeProbeResult> probe() async {
    try {
      final rawVersion = await _versionReader().timeout(timeout);
      if (rawVersion == null || rawVersion.trim().isEmpty) {
        return const WebView2RuntimeProbeResult.notInstalled();
      }
      final version = sanitizeWebView2RuntimeVersion(rawVersion);
      if (version == null) {
        return const WebView2RuntimeProbeResult.unreadable();
      }
      return WebView2RuntimeProbeResult.available(version);
    } catch (_) {
      // The error can contain platform/channel details. Callers need only the
      // bounded status, so the raw exception is intentionally discarded.
      return const WebView2RuntimeProbeResult.unreadable();
    }
  }
}

/// Stores only exact numeric runtime versions and quarantine timestamps.
///
/// Each entry has its own preference key. No failure text, URL, session token,
/// transcript, device identifier, or process command line is persisted.
class WebView2RuntimeQuarantine {
  WebView2RuntimeQuarantine(
    this._preferences, {
    DateTime Function()? now,
    this.ttl = const Duration(days: 90),
    this.maxEntries = 8,
  }) : _now = now ?? DateTime.now,
       assert(ttl > Duration.zero),
       assert(maxEntries > 0);

  static const String preferenceKeyPrefix =
      'autoteleprompter.stt.webview2_quarantine.v1.';

  final SharedPreferences _preferences;
  final DateTime Function() _now;
  final Duration ttl;
  final int maxEntries;

  static Future<WebView2RuntimeQuarantine> create({
    Duration ttl = const Duration(days: 90),
    int maxEntries = 8,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return WebView2RuntimeQuarantine(
      preferences,
      ttl: ttl,
      maxEntries: maxEntries,
    );
  }

  Future<bool> contains(String? rawVersion) async {
    final version = sanitizeWebView2RuntimeVersion(rawVersion);
    await _prune();
    if (version == null) return false;
    return _activeTimestamp(_keyFor(version)) != null;
  }

  Future<void> quarantine(String? rawVersion) async {
    final version = sanitizeWebView2RuntimeVersion(rawVersion);
    if (version == null) return;

    await _prune();
    await _preferences.setInt(
      _keyFor(version),
      _now().toUtc().millisecondsSinceEpoch,
    );
    await _enforceEntryLimit();
  }

  Future<void> clear(String? rawVersion) async {
    final version = sanitizeWebView2RuntimeVersion(rawVersion);
    if (version == null) return;
    await _preferences.remove(_keyFor(version));
  }

  /// Returns a bounded list useful for support diagnostics. Values are exact,
  /// sanitized runtime versions and never contain failure context.
  Future<List<String>> activeVersions() async {
    await _prune();
    final entries = _activeEntries()..sort(_newestFirst);
    return entries.map((entry) => entry.version).toList(growable: false);
  }

  String _keyFor(String version) => '$preferenceKeyPrefix$version';

  int? _activeTimestamp(String key) {
    final timestamp = _preferences.getInt(key);
    if (timestamp == null) return null;
    final nowMilliseconds = _now().toUtc().millisecondsSinceEpoch;
    final age = nowMilliseconds - timestamp;
    if (age < 0 || age >= ttl.inMilliseconds) return null;
    return timestamp;
  }

  List<_QuarantineEntry> _activeEntries() {
    final entries = <_QuarantineEntry>[];
    for (final key in _preferences.getKeys()) {
      if (!key.startsWith(preferenceKeyPrefix)) continue;
      final version = key.substring(preferenceKeyPrefix.length);
      final sanitized = sanitizeWebView2RuntimeVersion(version);
      final timestamp = _activeTimestamp(key);
      if (sanitized == version && timestamp != null) {
        entries.add(_QuarantineEntry(key, version, timestamp));
      }
    }
    return entries;
  }

  Future<void> _prune() async {
    final removals = <Future<bool>>[];
    for (final key in _preferences.getKeys()) {
      if (!key.startsWith(preferenceKeyPrefix)) continue;
      final version = key.substring(preferenceKeyPrefix.length);
      final sanitized = sanitizeWebView2RuntimeVersion(version);
      if (sanitized != version || _activeTimestamp(key) == null) {
        removals.add(_preferences.remove(key));
      }
    }
    await Future.wait(removals);
    await _enforceEntryLimit();
  }

  Future<void> _enforceEntryLimit() async {
    final entries = _activeEntries()..sort(_newestFirst);
    if (entries.length <= maxEntries) return;
    await Future.wait(
      entries.skip(maxEntries).map((entry) => _preferences.remove(entry.key)),
    );
  }

  static int _newestFirst(_QuarantineEntry a, _QuarantineEntry b) =>
      b.timestamp.compareTo(a.timestamp);
}

class _QuarantineEntry {
  const _QuarantineEntry(this.key, this.version, this.timestamp);

  final String key;
  final String version;
  final int timestamp;
}

/// Converts WebView2's version string to an exact four-component numeric
/// version. Known channel suffixes are ignored because the runtime build is
/// the compatibility boundary.
String? sanitizeWebView2RuntimeVersion(String? rawVersion) {
  if (rawVersion == null) return null;
  final match = RegExp(
    r'^\s*(\d{1,4}\.\d{1,4}\.\d{1,6}\.\d{1,6})'
    r'(?:\s+(?:stable|beta|dev|canary))?\s*$',
    caseSensitive: false,
  ).firstMatch(rawVersion);
  return match?.group(1);
}
