import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:webview_windows/webview_windows.dart';

import '../stt/stt_webview2_compatibility.dart';
import 'webview2_runtime_config.dart';

enum WebView2RuntimeMode { evergreen, bundledFixed, unavailable }

enum WebView2FixedRuntimeStatus { notInspected, available, missing, invalid }

enum WebView2RuntimeSelectionReason {
  verifiedEvergreen,
  evergreenMissing,
  evergreenUnverified,
  evergreenQuarantined,
  inheritedOverridesCouldNotBeCleared,
  bootstrapUnexpectedFailure,
  bundledFixedUnavailable,
  bundledFixedInvalid,
  bundledFixedInitializationFailed,
  evergreenInitializationFailed,
}

class WebView2RuntimeDecision {
  const WebView2RuntimeDecision({
    required this.preferredMode,
    required this.reason,
    required this.requiresCompatibilityRuntime,
  });

  final WebView2RuntimeMode preferredMode;
  final WebView2RuntimeSelectionReason reason;
  final bool requiresCompatibilityRuntime;
}

class WebView2RuntimeBootstrapResult {
  const WebView2RuntimeBootstrapResult({
    required this.mode,
    required this.reason,
    required this.installedEvergreenVersion,
    required this.effectiveRuntimeVersion,
    required this.fixedRuntimePath,
    required this.fixedRuntimeStatus,
    required this.compatibilityRuntimeRequired,
    required this.compatibilityRuntimeAvailable,
  });

  final WebView2RuntimeMode mode;
  final WebView2RuntimeSelectionReason reason;
  final String? installedEvergreenVersion;
  final String? effectiveRuntimeVersion;
  final String? fixedRuntimePath;
  final WebView2FixedRuntimeStatus fixedRuntimeStatus;
  final bool compatibilityRuntimeRequired;
  final bool compatibilityRuntimeAvailable;

  bool get usesBundledFixed => mode == WebView2RuntimeMode.bundledFixed;

  bool get compatibilityRuntimeRequiredButMissing =>
      compatibilityRuntimeRequired && !compatibilityRuntimeAvailable;
}

/// Selects the process-global WebView2 environment before any controller is
/// created. V5 remains a hidden embedded-WebView product: this class changes
/// only the embedded runtime binaries, never the speech engine or UI surface.
class WebView2RuntimeBootstrap {
  static const String fixedRuntimeVersion = '152.0.4191.62';
  static const String _fixedExecutableName = 'msedgewebview2.exe';
  static const int _fixedExecutableBytes = 4824392;
  static const Map<String, int> _fixedRequiredFileBytes = <String, int>{
    _fixedExecutableName: _fixedExecutableBytes,
    '152.0.4191.62.manifest': 226,
    'msedge.dll': 343780680,
    'icudtl.dat': 12461408,
    'resources.pak': 40707441,
    r'Locales\en-US.pak': 935463,
    r'Locales\he.pak': 1344308,
  };
  static const String _fixedExecutableSha256 =
      '0f75ba7da899408d4c4474d58358bdbee732705fc090161cbf08e8783520572d';
  static const Duration _probeTimeout = Duration(seconds: 8);

  static WebView2RuntimeBootstrapResult? _current;
  static Future<WebView2RuntimeBootstrapResult>? _initialization;

  static WebView2RuntimeBootstrapResult? get current => _current;

  /// The 152.0.4191 family is the only Evergreen family proven live with this
  /// app's Hebrew Web Speech pipeline. Unknown newer versions use the bundled
  /// compatibility runtime until a later app release explicitly verifies them.
  static bool isVerifiedEvergreenForStt(String? rawVersion) {
    final version = sanitizeWebView2RuntimeVersion(rawVersion);
    return version != null && version.startsWith('152.0.4191.');
  }

  static WebView2RuntimeDecision decide({
    required String? installedEvergreenVersion,
    required WebView2FixedRuntimeStatus fixedRuntimeStatus,
    required bool evergreenQuarantined,
  }) {
    final installed = sanitizeWebView2RuntimeVersion(installedEvergreenVersion);
    final requiresCompatibility =
        installed == null ||
        evergreenQuarantined ||
        !isVerifiedEvergreenForStt(installed);
    if (!requiresCompatibility) {
      return const WebView2RuntimeDecision(
        preferredMode: WebView2RuntimeMode.evergreen,
        reason: WebView2RuntimeSelectionReason.verifiedEvergreen,
        requiresCompatibilityRuntime: false,
      );
    }
    if (fixedRuntimeStatus == WebView2FixedRuntimeStatus.available) {
      return WebView2RuntimeDecision(
        preferredMode: WebView2RuntimeMode.bundledFixed,
        reason:
            installed == null
                ? WebView2RuntimeSelectionReason.evergreenMissing
                : evergreenQuarantined
                ? WebView2RuntimeSelectionReason.evergreenQuarantined
                : WebView2RuntimeSelectionReason.evergreenUnverified,
        requiresCompatibilityRuntime: true,
      );
    }
    return WebView2RuntimeDecision(
      preferredMode: WebView2RuntimeMode.unavailable,
      reason:
          fixedRuntimeStatus == WebView2FixedRuntimeStatus.invalid
              ? WebView2RuntimeSelectionReason.bundledFixedInvalid
              : WebView2RuntimeSelectionReason.bundledFixedUnavailable,
      requiresCompatibilityRuntime: true,
    );
  }

  static Future<WebView2RuntimeBootstrapResult> initialize() {
    final existing = _current;
    if (existing != null) return Future.value(existing);
    final inFlight = _initialization;
    if (inFlight != null) return inFlight;

    return _initialization = _initializeSafely();
  }

  static Future<WebView2RuntimeBootstrapResult> _initializeSafely() async {
    try {
      return await _initializeOnce();
    } catch (_) {
      return _current = const WebView2RuntimeBootstrapResult(
        mode: WebView2RuntimeMode.unavailable,
        reason: WebView2RuntimeSelectionReason.bootstrapUnexpectedFailure,
        installedEvergreenVersion: null,
        effectiveRuntimeVersion: null,
        fixedRuntimePath: null,
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.notInspected,
        compatibilityRuntimeRequired: true,
        compatibilityRuntimeAvailable: false,
      );
    }
  }

  static Future<WebView2RuntimeBootstrapResult> _initializeOnce() async {
    if (!WebView2RuntimeConfig.clearInheritedLoaderOverrides()) {
      return _current = const WebView2RuntimeBootstrapResult(
        mode: WebView2RuntimeMode.unavailable,
        reason:
            WebView2RuntimeSelectionReason.inheritedOverridesCouldNotBeCleared,
        installedEvergreenVersion: null,
        effectiveRuntimeVersion: null,
        fixedRuntimePath: null,
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.notInspected,
        compatibilityRuntimeRequired: true,
        compatibilityRuntimeAvailable: false,
      );
    }
    final installedVersion = await _readEvergreenVersion();
    final fixedPath = _bundledFixedRuntimePath();
    final fixedStatus = await _inspectFixedRuntime(fixedPath);
    final fixedAvailable = fixedStatus == WebView2FixedRuntimeStatus.available;
    final quarantined = await _isQuarantined(installedVersion);
    final decision = decide(
      installedEvergreenVersion: installedVersion,
      fixedRuntimeStatus: fixedStatus,
      evergreenQuarantined: quarantined,
    );

    if (decision.preferredMode == WebView2RuntimeMode.bundledFixed) {
      final aclReady = await _prepareWindows10FixedRuntimeAcl(fixedPath);
      final initialized =
          aclReady &&
          await _initializeEnvironment(
            mode: WebView2RuntimeMode.bundledFixed,
            browserExecutablePath: fixedPath,
          );
      return _current = WebView2RuntimeBootstrapResult(
        mode:
            initialized
                ? WebView2RuntimeMode.bundledFixed
                : WebView2RuntimeMode.unavailable,
        reason:
            initialized
                ? decision.reason
                : WebView2RuntimeSelectionReason
                    .bundledFixedInitializationFailed,
        installedEvergreenVersion: installedVersion,
        effectiveRuntimeVersion: initialized ? fixedRuntimeVersion : null,
        fixedRuntimePath: fixedPath,
        fixedRuntimeStatus: fixedStatus,
        compatibilityRuntimeRequired: true,
        compatibilityRuntimeAvailable: true,
      );
    }

    if (decision.preferredMode == WebView2RuntimeMode.unavailable) {
      return _current = WebView2RuntimeBootstrapResult(
        mode: WebView2RuntimeMode.unavailable,
        reason: decision.reason,
        installedEvergreenVersion: installedVersion,
        effectiveRuntimeVersion: null,
        fixedRuntimePath: null,
        fixedRuntimeStatus: fixedStatus,
        compatibilityRuntimeRequired: true,
        compatibilityRuntimeAvailable: false,
      );
    }

    final evergreenInitialized = await _initializeEnvironment(
      mode: WebView2RuntimeMode.evergreen,
    );
    return _current = WebView2RuntimeBootstrapResult(
      mode:
          evergreenInitialized
              ? WebView2RuntimeMode.evergreen
              : WebView2RuntimeMode.unavailable,
      reason:
          !evergreenInitialized && !decision.requiresCompatibilityRuntime
              ? WebView2RuntimeSelectionReason.evergreenInitializationFailed
              : decision.reason,
      installedEvergreenVersion: installedVersion,
      effectiveRuntimeVersion: evergreenInitialized ? installedVersion : null,
      fixedRuntimePath: fixedAvailable ? fixedPath : null,
      fixedRuntimeStatus: fixedStatus,
      compatibilityRuntimeRequired: decision.requiresCompatibilityRuntime,
      compatibilityRuntimeAvailable: fixedAvailable,
    );
  }

  static Future<String?> _readEvergreenVersion() async {
    try {
      return sanitizeWebView2RuntimeVersion(
        await WebviewController.getWebViewVersion().timeout(_probeTimeout),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isQuarantined(String? version) async {
    if (version == null) return false;
    try {
      final quarantine = await WebView2RuntimeQuarantine.create().timeout(
        const Duration(seconds: 2),
      );
      return await quarantine
          .contains(version)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return false;
    }
  }

  static String _bundledFixedRuntimePath() {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    return path.normalize(
      path.join(
        executableDirectory,
        'runtime',
        'webview2',
        fixedRuntimeVersion,
      ),
    );
  }

  static Future<WebView2FixedRuntimeStatus> _inspectFixedRuntime(
    String runtimePath,
  ) async {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    if (runtimePath.startsWith(r'\\') ||
        !path.isWithin(executableDirectory, runtimePath)) {
      return WebView2FixedRuntimeStatus.invalid;
    }
    try {
      final runtimeDirectory = Directory(runtimePath);
      if (!await runtimeDirectory.exists()) {
        return WebView2FixedRuntimeStatus.missing;
      }

      final resolvedExecutableDirectory =
          await Directory(executableDirectory).resolveSymbolicLinks();
      final resolvedRuntimePath = await runtimeDirectory.resolveSymbolicLinks();
      if (resolvedRuntimePath.startsWith(r'\\') ||
          !path.isWithin(resolvedExecutableDirectory, resolvedRuntimePath)) {
        return WebView2FixedRuntimeStatus.invalid;
      }

      for (final requiredFile in _fixedRequiredFileBytes.entries) {
        final file = File(path.join(resolvedRuntimePath, requiredFile.key));
        if (!await file.exists() || await file.length() != requiredFile.value) {
          return WebView2FixedRuntimeStatus.invalid;
        }
        final resolvedFilePath = await file.resolveSymbolicLinks();
        if (!path.isWithin(resolvedRuntimePath, resolvedFilePath)) {
          return WebView2FixedRuntimeStatus.invalid;
        }
      }

      final executable = File(
        path.join(resolvedRuntimePath, _fixedExecutableName),
      );
      final digest = await sha256.bind(executable.openRead()).first;
      return digest.toString() == _fixedExecutableSha256
          ? WebView2FixedRuntimeStatus.available
          : WebView2FixedRuntimeStatus.invalid;
    } catch (_) {
      return WebView2FixedRuntimeStatus.invalid;
    }
  }

  static Future<bool> _prepareWindows10FixedRuntimeAcl(
    String runtimePath,
  ) async {
    if (!_requiresWindows10FixedRuntimeAcl(Platform.operatingSystemVersion)) {
      return true;
    }
    const identities = <String>['*S-1-15-2-2', '*S-1-15-2-1'];
    try {
      for (final identity in identities) {
        final result = await Process.run('icacls', <String>[
          runtimePath,
          '/grant',
          '$identity:(OI)(CI)(RX)',
        ]).timeout(const Duration(seconds: 15));
        if (result.exitCode != 0) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _requiresWindows10FixedRuntimeAcl(String operatingSystemVersion) {
    final buildMatch = RegExp(
      r'\bBuild\s+(\d{4,6})\b',
      caseSensitive: false,
    ).firstMatch(operatingSystemVersion);
    final build = int.tryParse(buildMatch?.group(1) ?? '');
    if (build != null) return build < 22000;
    if (operatingSystemVersion.contains('Windows 11')) return false;
    return operatingSystemVersion.contains('Windows 10');
  }

  static Future<bool> _initializeEnvironment({
    required WebView2RuntimeMode mode,
    String? browserExecutablePath,
  }) async {
    final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
    final base =
        localAppData == null || localAppData.isEmpty
            ? File(Platform.resolvedExecutable).parent.path
            : localAppData;
    final runtimeLabel =
        mode == WebView2RuntimeMode.bundledFixed
            ? 'fixed-$fixedRuntimeVersion'
            : 'evergreen';
    final userDataPath = path.join(
      base,
      'AutoTeleprompter',
      'WebView2',
      runtimeLabel,
    );
    try {
      await Directory(userDataPath).create(recursive: true);
      await WebviewController.initializeEnvironment(
        userDataPath: userDataPath,
        browserExePath: browserExecutablePath,
        additionalArguments: WebView2RuntimeConfig.localSttArguments,
      );
      WebView2RuntimeConfig.markEnvironmentInitialized();
      return true;
    } catch (_) {
      return false;
    }
  }
}
