import 'dart:async';
import 'dart:io';

import 'package:autoteleprompter/platform/stt/stt_external_edge_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  const localAppData = r'C:\Users\Tester\AppData\Local';
  const programFiles = r'C:\Program Files';
  const programFilesX86 = r'C:\Program Files (x86)';
  final edgePath = path.windows.join(
    programFilesX86,
    'Microsoft',
    'Edge',
    'Application',
    'msedge.exe',
  );
  final profilePath = path.windows.join(
    localAppData,
    'AutoTeleprompter',
    'BrowserSTT',
    'EdgeProfile',
  );
  final chromePath = path.windows.join(
    programFiles,
    'Google',
    'Chrome',
    'Application',
    'chrome.exe',
  );
  final chromeProfilePath = path.windows.join(
    localAppData,
    'AutoTeleprompter',
    'BrowserSTT',
    'ChromeProfile',
  );

  group('WindowsSttExternalEdgeLauncher.launch', () {
    test(
      'starts the exact Edge executable with the contained profile',
      () async {
        final process = _FakeProcess();
        final starts = <_StartCall>[];
        final directories = <String>[];
        final launcher = _launcher(
          edgePath: edgePath,
          process: process,
          starts: starts,
          directories: directories,
        );

        final result = await launcher.launch(
          'http://localhost:8087/?session=42',
        );

        expect(result.success, isTrue);
        expect(result.message, isNull);
        expect(launcher.isRunning, isTrue);
        expect(directories, <String>[profilePath]);
        expect(starts, hasLength(1));
        expect(starts.single.executable, edgePath);
        expect(starts.single.arguments, <String>[
          '--app=http://localhost:8087/?session=42',
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
          '--unsafely-treat-insecure-origin-as-secure=http://localhost:8087',
        ]);
        expect(
          starts.single.arguments,
          isNot(anyElement(contains('fake-device'))),
        );
        expect(
          starts.single.arguments,
          isNot(anyElement(contains('fake-audio'))),
        );
      },
    );

    test('launches only once while its Edge process is active', () async {
      final starts = <_StartCall>[];
      final launcher = _launcher(
        edgePath: edgePath,
        process: _FakeProcess(),
        starts: starts,
      );

      final first = await launcher.launch('http://localhost:8082/');
      final second = await launcher.launch('http://localhost:8092/');

      expect(first.success, isTrue);
      expect(second.success, isTrue);
      expect(second.message, contains('already running'));
      expect(starts, hasLength(1));
    });

    test('rejects every non-canonical STT address before launch', () async {
      final starts = <_StartCall>[];
      final directories = <String>[];
      final launcher = _launcher(
        edgePath: edgePath,
        process: _FakeProcess(),
        starts: starts,
        directories: directories,
      );
      final invalidUrls = <String>[
        'https://localhost:8082/',
        'http://127.0.0.1:8082/',
        'http://localhost/',
        'http://localhost:8081/',
        'http://localhost:8093/',
        'http://localhost.evil:8082/',
        'http://user@localhost:8082/',
        'http://localhost:8082/unexpected',
        'http://localhost:8082/#fragment',
        ' http://localhost:8082/',
      ];

      for (final url in invalidUrls) {
        final result = await launcher.launch(url);
        expect(result.success, isFalse, reason: url);
        expect(result.message, isNotEmpty, reason: url);
      }
      expect(starts, isEmpty);
      expect(directories, isEmpty);
    });

    test('returns a safe error when LOCALAPPDATA is unavailable', () async {
      final launcher = WindowsSttExternalEdgeLauncher(
        environment: <String, String>{'ProgramFiles(x86)': programFilesX86},
        processStarter: (_, __) async => _FakeProcess(),
        fileExists: (_) => true,
        isWindows: true,
      );

      final result = await launcher.launch('http://localhost:8082/');

      expect(result.success, isFalse);
      expect(result.message, contains('app data'));
    });

    test('returns a safe error when Microsoft Edge is unavailable', () async {
      final launcher = WindowsSttExternalEdgeLauncher(
        environment: const <String, String>{
          'LOCALAPPDATA': localAppData,
          'ProgramFiles(x86)': programFilesX86,
        },
        processStarter: (_, __) async => _FakeProcess(),
        fileExists: (_) => false,
        ensureDirectory: (_) async {},
        isWindows: true,
      );

      final result = await launcher.launch('http://localhost:8082/');

      expect(result.success, isFalse);
      expect(result.message, contains('not installed'));
    });

    test('does not expose process-start exception details', () async {
      final launcher = WindowsSttExternalEdgeLauncher(
        environment: const <String, String>{
          'LOCALAPPDATA': localAppData,
          'ProgramFiles(x86)': programFilesX86,
        },
        processStarter:
            (_, __) async => throw StateError('private machine detail'),
        fileExists: (candidate) => candidate == edgePath,
        ensureDirectory: (_) async {},
        isWindows: true,
      );

      final result = await launcher.launch('http://localhost:8082/');

      expect(result.success, isFalse);
      expect(result.message, isNot(contains('private machine detail')));
      expect(launcher.isRunning, isFalse);
    });
  });

  group('WindowsSttExternalBrowserLauncher Chrome', () {
    test(
      'uses only the exact Chrome root and a separate contained profile',
      () async {
        final process = _FakeProcess();
        final starts = <_StartCall>[];
        final directories = <String>[];
        final launcher = WindowsSttExternalBrowserLauncher(
          browser: WindowsSttExternalBrowser.chrome,
          environment: const <String, String>{
            'LOCALAPPDATA': localAppData,
            'ProgramFiles': programFiles,
            'ProgramFiles(x86)': programFilesX86,
            'PATH': r'C:\Untrusted',
          },
          processStarter: (executable, arguments) async {
            starts.add(_StartCall(executable, List<String>.of(arguments)));
            return process;
          },
          fileExists: (candidate) => candidate == chromePath,
          ensureDirectory: (directory) async => directories.add(directory),
          isWindows: true,
        );

        final result = await launcher.launch(
          'http://localhost:8088/?session=chrome',
        );

        expect(result.success, isTrue);
        expect(directories, <String>[chromeProfilePath]);
        expect(starts, hasLength(1));
        expect(starts.single.executable, chromePath);
        expect(
          starts.single.arguments,
          contains('--user-data-dir=$chromeProfilePath'),
        );
        expect(
          starts.single.arguments,
          contains('--disable-background-timer-throttling'),
        );
        expect(
          starts.single.arguments,
          contains('--disable-backgrounding-occluded-windows'),
        );
        expect(
          starts.single.arguments,
          contains('--disable-renderer-backgrounding'),
        );
      },
    );

    test(
      'does not search PATH when Chrome is absent from trusted roots',
      () async {
        final starts = <_StartCall>[];
        final launcher = WindowsSttExternalChromeLauncher(
          environment: const <String, String>{
            'LOCALAPPDATA': localAppData,
            'ProgramFiles': programFiles,
            'PATH': r'C:\Untrusted',
          },
          processStarter: (executable, arguments) async {
            starts.add(_StartCall(executable, arguments));
            return _FakeProcess();
          },
          fileExists: (_) => false,
          ensureDirectory: (_) async {},
          isWindows: true,
        );

        final result = await launcher.launch('http://localhost:8082/');

        expect(result.success, isFalse);
        expect(result.message, contains('Google Chrome'));
        expect(starts, isEmpty);
      },
    );
  });

  group('WindowsSttExternalEdgeLauncher.stop', () {
    test(
      'terminates only its tracked process and clears running state',
      () async {
        final process = _FakeProcess(exitOnKill: true);
        final launcher = _launcher(edgePath: edgePath, process: process);
        await launcher.launch('http://localhost:8082/');

        await launcher.stop();

        expect(process.killSignals, <ProcessSignal>[ProcessSignal.sigterm]);
        expect(launcher.isRunning, isFalse);
      },
    );

    test('is bounded and keeps an unconfirmed process tracked', () async {
      final process = _FakeProcess();
      final launcher = _launcher(
        edgePath: edgePath,
        process: process,
        stopTimeout: const Duration(milliseconds: 2),
        forceStopTimeout: const Duration(milliseconds: 2),
      );
      await launcher.launch('http://localhost:8082/');

      await launcher.stop();

      expect(process.killSignals, <ProcessSignal>[
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
      expect(launcher.isRunning, isTrue);
    });

    test('bootstrap exit is not authoritative host failure', () async {
      final process = _FakeProcess();
      final exits = <int>[];
      final launcher = _launcher(
        edgePath: edgePath,
        process: process,
        onUnexpectedExit: exits.add,
      );
      await launcher.launch('http://localhost:8082/');

      process.complete(23);
      await Future<void>.delayed(Duration.zero);

      expect(launcher.isRunning, isTrue);
      expect(process.killSignals, isEmpty);
      expect(exits, isEmpty);

      await launcher.stop();
      expect(launcher.isRunning, isFalse);
    });

    test('does not report launcher-owned stop as an unexpected exit', () async {
      final process = _FakeProcess(exitOnKill: true);
      final exits = <int>[];
      final launcher = _launcher(
        edgePath: edgePath,
        process: process,
        onUnexpectedExit: exits.add,
      );
      await launcher.launch('http://localhost:8082/');

      await launcher.stop();

      expect(exits, isEmpty);
    });

    test(
      'accepts an immediate bootstrap handoff and awaits readiness',
      () async {
        final process = _FakeProcess()..complete(7);
        final exits = <int>[];
        final launcher = _launcher(
          edgePath: edgePath,
          process: process,
          onUnexpectedExit: exits.add,
        );

        final result = await launcher.launch('http://localhost:8082/');

        expect(result.success, isTrue);
        expect(exits, isEmpty);
        expect(launcher.isRunning, isTrue);

        await launcher.stop();
        expect(launcher.isRunning, isFalse);
      },
    );

    test('honors stop requested while process start is in flight', () async {
      final process = _FakeProcess(exitOnKill: true);
      final startCompleter = Completer<ExternalEdgeProcess>();
      final launcher = WindowsSttExternalEdgeLauncher(
        environment: const <String, String>{
          'LOCALAPPDATA': r'C:\Users\Tester\AppData\Local',
          'ProgramFiles(x86)': r'C:\Program Files (x86)',
        },
        processStarter: (_, __) => startCompleter.future,
        fileExists: (candidate) => candidate == edgePath,
        ensureDirectory: (_) async {},
        isWindows: true,
      );

      final launchFuture = launcher.launch('http://localhost:8082/');
      await Future<void>.delayed(Duration.zero);
      await launcher.stop();
      startCompleter.complete(process);

      final result = await launchFuture;
      expect(result.success, isFalse);
      expect(result.message, contains('stopped'));
      expect(process.killSignals, <ProcessSignal>[ProcessSignal.sigterm]);
      expect(launcher.isRunning, isFalse);
    });
  });
}

WindowsSttExternalEdgeLauncher _launcher({
  required String edgePath,
  required _FakeProcess process,
  List<_StartCall>? starts,
  List<String>? directories,
  Duration stopTimeout = const Duration(seconds: 2),
  Duration forceStopTimeout = const Duration(seconds: 1),
  ExternalEdgeUnexpectedExit? onUnexpectedExit,
}) {
  return WindowsSttExternalEdgeLauncher(
    environment: const <String, String>{
      'LOCALAPPDATA': r'C:\Users\Tester\AppData\Local',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
    },
    processStarter: (executable, arguments) async {
      starts?.add(_StartCall(executable, List<String>.of(arguments)));
      return process;
    },
    fileExists: (candidate) => candidate == edgePath,
    ensureDirectory: (directory) async => directories?.add(directory),
    isWindows: true,
    onUnexpectedExit: onUnexpectedExit,
    stopTimeout: stopTimeout,
    forceStopTimeout: forceStopTimeout,
  );
}

class _StartCall {
  const _StartCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class _FakeProcess implements ExternalEdgeProcess {
  _FakeProcess({this.exitOnKill = false});

  final bool exitOnKill;
  final Completer<int> _exitCode = Completer<int>();
  final List<ProcessSignal> killSignals = <ProcessSignal>[];

  @override
  int get pid => 1234;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (exitOnKill && !_exitCode.isCompleted) _exitCode.complete(0);
    return true;
  }

  void complete(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }
}
