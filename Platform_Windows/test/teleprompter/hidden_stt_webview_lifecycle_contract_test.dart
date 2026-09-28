import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String presenterScreen;
  late String presenterLifecycle;
  late String presenterBuild;
  late String contentCreatorScreen;
  late String contentCreatorLifecycle;

  setUpAll(() {
    presenterScreen = _readSource(
      'lib/features/teleprompter/widgets/teleprompter_screen.dart',
    );
    presenterLifecycle = _readSource(
      'lib/features/teleprompter/widgets/teleprompter_screen.session_stt.dart',
    );
    presenterBuild = _readSource(
      'lib/features/teleprompter/widgets/teleprompter_screen.build.dart',
    );
    contentCreatorScreen = _readSource(
      'lib/features/teleprompter/widgets/content_creator_screen.dart',
    );
    contentCreatorLifecycle = _readSource(
      'lib/features/teleprompter/widgets/content_creator_screen.camera_webview.dart',
    );
  });

  test('presenter prewarms and reuses one controller initialization', () {
    expect(
      presenterScreen,
      contains('unawaited(_ensureSttWebViewController());'),
    );
    expect(
      presenterScreen.indexOf('unawaited(_ensureSttWebViewController());'),
      lessThan(
        presenterScreen.indexOf(
          'teleprompterProvider.select((s) => s.sttWebViewUrl)',
        ),
      ),
    );
    expect(
      presenterScreen,
      contains('Future<WebviewController?>? _webViewControllerInitFuture;'),
    );
    expect(
      presenterLifecycle,
      contains('if (existing != null) return existing;'),
    );
    expect(
      presenterLifecycle,
      contains('if (inFlight != null) return inFlight;'),
    );
    expect(
      presenterLifecycle,
      contains('_webViewControllerInitFuture = initialization;'),
    );
    expect(
      presenterLifecycle,
      contains('identical(_webViewControllerInitFuture, initialization)'),
    );
    expect(
      presenterLifecycle,
      contains('final controller = await _ensureSttWebViewController();'),
    );
    expect(_occurrences(presenterLifecycle, 'WebviewController()'), 1);
  });

  test('content creator prewarms and reuses one controller initialization', () {
    expect(
      contentCreatorScreen,
      contains('unawaited(_ensureContentSttWebViewController());'),
    );
    expect(
      contentCreatorScreen.indexOf(
        'unawaited(_ensureContentSttWebViewController());',
      ),
      lessThan(
        contentCreatorScreen.indexOf(
          'teleprompterProvider.select((s) => s.sttWebViewUrl)',
        ),
      ),
    );
    expect(
      contentCreatorScreen,
      contains(
        'Future<WebviewController?>? _contentWebViewControllerInitFuture;',
      ),
    );
    expect(
      contentCreatorLifecycle,
      contains('if (existing != null) return existing;'),
    );
    expect(
      contentCreatorLifecycle,
      contains('if (inFlight != null) return inFlight;'),
    );
    expect(
      contentCreatorLifecycle,
      contains('_contentWebViewControllerInitFuture = initialization;'),
    );
    expect(
      contentCreatorLifecycle,
      contains(
        'identical(_contentWebViewControllerInitFuture, initialization)',
      ),
    );
    expect(
      contentCreatorLifecycle,
      contains(
        'final controller = await _ensureContentSttWebViewController();',
      ),
    );
    expect(_occurrences(contentCreatorLifecycle, 'WebviewController()'), 1);
  });

  test('hidden WebViews remain mounted at one physical pixel', () {
    expect(
      presenterBuild,
      matches(
        RegExp(
          r'width:\s*1,[\s\S]*?height:\s*1,[\s\S]*?'
          r'IgnorePointer\([\s\S]*?ignoring:\s*true,[\s\S]*?'
          r'Opacity\([\s\S]*?opacity:\s*0\.01,[\s\S]*?'
          r'Webview\(_webviewController!\)',
        ),
      ),
    );
    expect(
      contentCreatorScreen,
      matches(
        RegExp(
          r'width:\s*1,[\s\S]*?height:\s*1,[\s\S]*?'
          r'IgnorePointer\([\s\S]*?ignoring:\s*true,[\s\S]*?'
          r'Opacity\([\s\S]*?opacity:\s*0\.01,[\s\S]*?'
          r'Webview\(_contentWebviewController!\)',
        ),
      ),
    );
  });

  test('clearing a session URL preserves each warmed controller', () {
    final presenterClear = _methodBody(presenterLifecycle, '_clearSttWebView');
    expect(presenterClear, contains('_webViewLoadGeneration++'));
    expect(presenterClear, contains('_pendingWebViewUrl = null'));
    expect(presenterClear, contains('_loadedWebViewUrl = null'));
    expect(presenterClear, isNot(contains('dispose')));
    expect(presenterClear, isNot(contains('_webviewController = null')));

    final contentCreatorClear = _methodBody(
      contentCreatorLifecycle,
      '_clearContentSttWebView',
    );
    expect(contentCreatorClear, contains('_contentWebViewLoadGeneration++'));
    expect(contentCreatorClear, contains('_pendingContentWebViewUrl = null'));
    expect(contentCreatorClear, contains('_loadedContentWebViewUrl = null'));
    expect(contentCreatorClear, isNot(contains('dispose')));
    expect(
      contentCreatorClear,
      isNot(contains('_contentWebviewController = null')),
    );
  });

  test('host telemetry reports the process-selected WebView2 runtime', () {
    for (final lifecycle in <String>[
      presenterLifecycle,
      contentCreatorLifecycle,
    ]) {
      expect(
        lifecycle,
        contains(
          'final runtimeVersion = runtimeBootstrap?.effectiveRuntimeVersion;',
        ),
      );
      expect(
        lifecycle,
        contains(
          '.reportEmbeddedSttHostLoaded(runtimeVersion: runtimeVersion);',
        ),
      );
      expect(lifecycle, contains('runtimeVersion: runtimeVersion'));
      expect(
        lifecycle,
        isNot(contains('WebviewController.getWebViewVersion()')),
      );
    }
  });
}

String _readSource(String relativePath) {
  final direct = File(relativePath);
  if (direct.existsSync()) return direct.readAsStringSync();

  final fromRepositoryRoot = File('Platform_Windows/$relativePath');
  expect(
    fromRepositoryRoot.existsSync(),
    isTrue,
    reason: 'Missing source contract input: $relativePath',
  );
  return fromRepositoryRoot.readAsStringSync();
}

String _methodBody(String source, String methodName) {
  final match = RegExp(
    'void ${RegExp.escape(methodName)}\\(\\) \\{([\\s\\S]*?)\\n  \\}',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'Missing method: $methodName');
  return match!.group(1)!;
}

int _occurrences(String source, String pattern) =>
    RegExp(RegExp.escape(pattern)).allMatches(source).length;
