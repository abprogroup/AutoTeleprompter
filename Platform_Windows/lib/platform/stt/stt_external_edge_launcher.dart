import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

typedef ExternalEdgeProcessStarter =
    Future<ExternalEdgeProcess> Function(
      String executable,
      List<String> arguments,
    );

typedef ExternalEdgeFileExists = bool Function(String filePath);
typedef ExternalEdgeEnsureDirectory =
    Future<void> Function(String directoryPath);
typedef ExternalEdgeUnexpectedExit = void Function(int exitCode);

abstract interface class ExternalEdgeProcess {
  int get pid;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

class ExternalEdgeLaunchResult {
  const ExternalEdgeLaunchResult({required this.success, this.message});

  final bool success;
  final String? message;
}

enum WindowsSttExternalBrowser { edge, chrome }

/// Launches the existing localhost STT page in a dedicated Chromium app.
///
/// This service is intentionally additive. It does not select the fallback or
/// alter the embedded WebView2 path. The caller owns that policy decision.
class WindowsSttExternalBrowserLauncher {
  WindowsSttExternalBrowserLauncher({
    required this.browser,
    Map<String, String>? environment,
    ExternalEdgeProcessStarter? processStarter,
    ExternalEdgeFileExists? fileExists,
    ExternalEdgeEnsureDirectory? ensureDirectory,
    this.onUnexpectedExit,
    bool? isWindows,
    Duration stopTimeout = const Duration(seconds: 2),
    Duration forceStopTimeout = const Duration(seconds: 1),
  }) : _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ),
       _processStarter = processStarter ?? _startProcess,
       _fileExists = fileExists ?? _defaultFileExists,
       _ensureDirectory = ensureDirectory ?? _defaultEnsureDirectory,
       _isWindows = isWindows ?? Platform.isWindows,
       _stopTimeout = stopTimeout,
       _forceStopTimeout = forceStopTimeout;

  static const int _minimumPort = 8082;
  static const int _maximumPort = 8092;

  final WindowsSttExternalBrowser browser;
  final Map<String, String> _environment;
  final ExternalEdgeProcessStarter _processStarter;
  final ExternalEdgeFileExists _fileExists;
  final ExternalEdgeEnsureDirectory _ensureDirectory;
  final bool _isWindows;
  final Duration _stopTimeout;
  final Duration _forceStopTimeout;

  /// Retained for source compatibility with the original Edge launcher API.
  ///
  /// Chromium may return a short-lived bootstrap process and hand the app to
  /// another process. Its exit is therefore not authoritative host failure and
  /// is deliberately not reported here. Authenticated socket readiness and
  /// disconnect events own host health.
  ExternalEdgeUnexpectedExit? onUnexpectedExit;

  ExternalEdgeProcess? _process;
  bool _launching = false;
  bool _stopRequested = false;

  /// Whether this launcher owns an active launch lease.
  ///
  /// The lease remains active when Chromium's direct bootstrap PID exits. It
  /// is cleared only by [stop], preventing duplicate browser trees while the
  /// authenticated readiness layer determines whether the host is healthy.
  bool get isRunning => _launching || _process != null;

  Future<ExternalEdgeLaunchResult> launch(String url) async {
    if (!_isWindows) {
      return const ExternalEdgeLaunchResult(
        success: false,
        message:
            'The external browser speech fallback is available on Windows.',
      );
    }

    final validated = _validateUrl(url);
    if (validated == null) {
      return const ExternalEdgeLaunchResult(
        success: false,
        message: 'The speech fallback received an invalid local address.',
      );
    }

    if (isRunning) {
      return ExternalEdgeLaunchResult(
        success: true,
        message: 'The $_browserName speech fallback is already running.',
      );
    }

    _launching = true;
    _stopRequested = false;
    try {
      final profilePath = _resolveProfilePath();
      if (profilePath == null) {
        return const ExternalEdgeLaunchResult(
          success: false,
          message: 'The Windows app data folder is unavailable.',
        );
      }

      final executable = _resolveExecutable();
      if (executable == null) {
        return ExternalEdgeLaunchResult(
          success: false,
          message: '$_browserName is not installed or could not be found.',
        );
      }

      try {
        await _ensureDirectory(profilePath);
      } catch (_) {
        return const ExternalEdgeLaunchResult(
          success: false,
          message: 'The speech fallback profile could not be prepared.',
        );
      }

      if (_stopRequested) {
        return ExternalEdgeLaunchResult(
          success: false,
          message: 'The $_browserName speech fallback was stopped.',
        );
      }

      final arguments = <String>[
        '--app=${validated.uri}',
        '--user-data-dir=$profilePath',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-sync',
        '--disable-extensions',
        '--disable-background-mode',
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows',
        '--disable-renderer-backgrounding',
        '--start-minimized',
        '--window-position=-32000,-32000',
        '--window-size=320,240',
        '--use-fake-ui-for-media-stream',
        '--autoplay-policy=no-user-gesture-required',
        '--unsafely-treat-insecure-origin-as-secure=${validated.origin}',
      ];

      try {
        final process = await _processStarter(executable, arguments);
        _track(process);
        if (_stopRequested) {
          await stop();
          return ExternalEdgeLaunchResult(
            success: false,
            message: 'The $_browserName speech fallback was stopped.',
          );
        }
      } catch (_) {
        return ExternalEdgeLaunchResult(
          success: false,
          message: '$_browserName could not be started for speech recognition.',
        );
      }

      return const ExternalEdgeLaunchResult(success: true);
    } finally {
      _launching = false;
    }
  }

  /// Stops only the process returned by this launcher's direct browser start.
  ///
  /// It deliberately never searches for or terminates unrelated browser
  /// processes.
  Future<void> stop() async {
    _stopRequested = true;
    final process = _process;
    if (process == null) return;

    var exited = await _killAndWait(
      process,
      ProcessSignal.sigterm,
      _stopTimeout,
    );
    if (!exited) {
      exited = await _killAndWait(
        process,
        ProcessSignal.sigkill,
        _forceStopTimeout,
      );
    }

    if (exited && identical(_process, process)) {
      _process = null;
    }
  }

  Future<bool> _killAndWait(
    ExternalEdgeProcess process,
    ProcessSignal signal,
    Duration timeout,
  ) async {
    try {
      process.kill(signal);
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void _track(ExternalEdgeProcess process) {
    _process = process;
    unawaited(
      process.exitCode.then<void>(
        (_) {
          // Do not clear the launch lease or report failure here. Chromium can
          // use the returned process only as a bootstrap and keep the app alive
          // in another process. Socket readiness/disconnect is authoritative.
        },
        onError: (_) {
          // Keep the process tracked when its exit cannot be confirmed. This
          // prevents a second Edge tree from being launched accidentally.
        },
      ),
    );
  }

  _ValidatedBrowserUrl? _validateUrl(String value) {
    if (value.isEmpty || value.trim() != value) return null;
    if (value.contains(RegExp(r'[\u0000-\u001F\u007F]'))) return null;

    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'http' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'localhost' ||
        !uri.hasPort ||
        uri.port < _minimumPort ||
        uri.port > _maximumPort ||
        uri.path != '/' ||
        uri.fragment.isNotEmpty) {
      return null;
    }

    return _ValidatedBrowserUrl(
      uri: uri,
      origin: 'http://localhost:${uri.port}',
    );
  }

  String? _resolveProfilePath() {
    final localAppData = _environmentValue('LOCALAPPDATA')?.trim();
    if (localAppData == null ||
        localAppData.isEmpty ||
        !path.windows.isAbsolute(localAppData)) {
      return null;
    }

    final canonicalRoot = path.windows.normalize(localAppData);
    final profile = path.windows.normalize(
      path.windows.join(
        canonicalRoot,
        'AutoTeleprompter',
        'BrowserSTT',
        _profileDirectoryName,
      ),
    );
    if (!path.windows.isWithin(canonicalRoot, profile)) return null;
    return profile;
  }

  String? _resolveExecutable() {
    final roots =
        browser == WindowsSttExternalBrowser.edge
            ? <String?>[
              _environmentValue('ProgramFiles(x86)'),
              _environmentValue('ProgramFiles'),
              _environmentValue('LOCALAPPDATA'),
            ]
            : <String?>[
              _environmentValue('ProgramFiles'),
              _environmentValue('ProgramFiles(x86)'),
              _environmentValue('LOCALAPPDATA'),
            ];
    final checked = <String>{};

    for (final rawRoot in roots) {
      final root = rawRoot?.trim();
      if (root == null || root.isEmpty || !path.windows.isAbsolute(root)) {
        continue;
      }
      final candidate = path.windows.normalize(
        path.windows.joinAll(<String>[root, ..._executableSegments]),
      );
      if (checked.add(candidate.toLowerCase()) && _fileExists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  String get _browserName => switch (browser) {
    WindowsSttExternalBrowser.edge => 'Microsoft Edge',
    WindowsSttExternalBrowser.chrome => 'Google Chrome',
  };

  String get _profileDirectoryName => switch (browser) {
    WindowsSttExternalBrowser.edge => 'EdgeProfile',
    WindowsSttExternalBrowser.chrome => 'ChromeProfile',
  };

  List<String> get _executableSegments => switch (browser) {
    WindowsSttExternalBrowser.edge => const <String>[
      'Microsoft',
      'Edge',
      'Application',
      'msedge.exe',
    ],
    WindowsSttExternalBrowser.chrome => const <String>[
      'Google',
      'Chrome',
      'Application',
      'chrome.exe',
    ],
  };

  String? _environmentValue(String key) {
    final normalizedKey = key.toLowerCase();
    for (final entry in _environment.entries) {
      if (entry.key.toLowerCase() == normalizedKey) return entry.value;
    }
    return null;
  }

  static Future<ExternalEdgeProcess> _startProcess(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    unawaited(process.stdout.drain<void>().catchError((_) {}));
    unawaited(process.stderr.drain<void>().catchError((_) {}));
    return _IoExternalEdgeProcess(process);
  }

  static bool _defaultFileExists(String filePath) =>
      File(filePath).existsSync();

  static Future<void> _defaultEnsureDirectory(String directoryPath) async {
    await Directory(directoryPath).create(recursive: true);
  }
}

/// Source-compatible Edge facade used by the existing provider.
class WindowsSttExternalEdgeLauncher extends WindowsSttExternalBrowserLauncher {
  WindowsSttExternalEdgeLauncher({
    super.environment,
    super.processStarter,
    super.fileExists,
    super.ensureDirectory,
    super.onUnexpectedExit,
    super.isWindows,
    super.stopTimeout,
    super.forceStopTimeout,
  }) : super(browser: WindowsSttExternalBrowser.edge);
}

class WindowsSttExternalChromeLauncher
    extends WindowsSttExternalBrowserLauncher {
  WindowsSttExternalChromeLauncher({
    super.environment,
    super.processStarter,
    super.fileExists,
    super.ensureDirectory,
    super.onUnexpectedExit,
    super.isWindows,
    super.stopTimeout,
    super.forceStopTimeout,
  }) : super(browser: WindowsSttExternalBrowser.chrome);
}

class _ValidatedBrowserUrl {
  const _ValidatedBrowserUrl({required this.uri, required this.origin});

  final Uri uri;
  final String origin;
}

class _IoExternalEdgeProcess implements ExternalEdgeProcess {
  const _IoExternalEdgeProcess(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}
