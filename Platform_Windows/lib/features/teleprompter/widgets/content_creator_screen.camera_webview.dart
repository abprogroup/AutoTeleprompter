part of 'content_creator_screen.dart';

extension _ContentCreatorCameraWebView on _ContentCreatorScreenState {
  Future<WebviewController?> _ensureContentSttWebViewController() async {
    if (!Platform.isWindows ||
        !mounted ||
        _contentWebViewControllerOwnerDisposed) {
      return null;
    }
    final existing = _contentWebviewController;
    if (existing != null) return existing;
    final inFlight = _contentWebViewControllerInitFuture;
    if (inFlight != null) return inFlight;

    final runtimeBootstrap = WebView2RuntimeBootstrap.current;
    if (runtimeBootstrap?.mode == WebView2RuntimeMode.unavailable) {
      LightweightDiagnostics.instance.record(
        'error',
        'Embedded WebView2 runtime unavailable',
        data: {
          'source': 'contentCreator.webviewRuntime',
          'reason': runtimeBootstrap?.reason.name,
        },
      );
      return null;
    }

    WebView2RuntimeConfig.configureForLocalSttDefaults();
    final initialization = _initializeContentSttWebViewController();
    _contentWebViewControllerInitFuture = initialization;
    try {
      return await initialization;
    } finally {
      if (identical(_contentWebViewControllerInitFuture, initialization)) {
        _contentWebViewControllerInitFuture = null;
      }
    }
  }

  Future<WebviewController?> _initializeContentSttWebViewController() async {
    WebviewController? controller;
    try {
      controller = WebviewController();
      await controller.initialize();
      if (!mounted || _contentWebViewControllerOwnerDisposed) {
        await _disposeContentSttWebViewController(controller);
        return null;
      }
      _updateContentCreatorState(() {
        _contentWebviewController = controller;
      });
      return controller;
    } catch (_) {
      if (controller != null) {
        await _disposeContentSttWebViewController(controller);
      }
      _logContentDebug('content webview init failed');
      LightweightDiagnostics.instance.record(
        'error',
        'Embedded WebView2 initialization failed',
        data: const {'source': 'contentCreator.webviewInit'},
      );
      return null;
    }
  }

  Future<void> _loadContentSttWebView(String url) {
    if (!Platform.isWindows ||
        !mounted ||
        _contentWebViewControllerOwnerDisposed) {
      return Future<void>.value();
    }
    final generation = ++_contentWebViewLoadGeneration;
    _pendingContentWebViewUrl = url;
    WebView2RuntimeConfig.configureForLocalSttUrl(url);
    final previousNavigation = _contentWebViewNavigationTail;
    final operation = () async {
      try {
        await previousNavigation;
        if (!_isCurrentContentSttWebViewLoad(generation, url)) return;
        await _performContentSttWebViewLoad(generation, url);
      } catch (_) {
        LightweightDiagnostics.instance.record(
          'error',
          'Unexpected embedded WebView2 navigation failure',
          data: const {'source': 'contentCreator.webviewLoadUnexpected'},
        );
      }
    }();
    _contentWebViewNavigationTail = operation;
    return operation;
  }

  Future<void> _performContentSttWebViewLoad(int generation, String url) async {
    final runtimeBootstrap = WebView2RuntimeBootstrap.current;
    final runtimeVersion = runtimeBootstrap?.effectiveRuntimeVersion;
    if (runtimeBootstrap?.mode == WebView2RuntimeMode.unavailable) {
      _pendingContentWebViewUrl = null;
      ref
          .read(teleprompterProvider.notifier)
          .reportEmbeddedSttHostFailure(
            reasonCode: 'webview-runtime-unavailable',
            runtimeVersion: runtimeVersion,
          );
      return;
    }
    final controller = await _ensureContentSttWebViewController();
    if (!_isCurrentContentSttWebViewLoad(generation, url)) return;
    if (controller == null) {
      _pendingContentWebViewUrl = null;
      ref
          .read(teleprompterProvider.notifier)
          .reportEmbeddedSttHostFailure(
            reasonCode: 'webview-init-failed',
            runtimeVersion: runtimeVersion,
          );
      return;
    }

    try {
      await controller.loadUrl(url).timeout(const Duration(seconds: 12));
      if (!_isCurrentContentSttWebViewLoad(generation, url)) {
        return;
      }
      _pendingContentWebViewUrl = null;
      _loadedContentWebViewUrl = url;
      _logContentDebug('content webview loaded');
      ref
          .read(teleprompterProvider.notifier)
          .reportEmbeddedSttHostLoaded(runtimeVersion: runtimeVersion);
    } catch (_) {
      if (_isCurrentContentSttWebViewLoad(generation, url)) {
        _pendingContentWebViewUrl = null;
        _loadedContentWebViewUrl = null;
        if (_contentWebviewController == controller) {
          _updateContentCreatorState(() {
            _contentWebviewController = null;
          });
        }
        await _disposeContentSttWebViewController(controller);
        if (_isCurrentContentSttWebViewLoad(generation, url)) {
          ref
              .read(teleprompterProvider.notifier)
              .reportEmbeddedSttHostFailure(
                reasonCode: 'webview-load-failed',
                runtimeVersion: runtimeVersion,
              );
        }
      }
      _logContentDebug('content webview load failed');
      LightweightDiagnostics.instance.record(
        'error',
        'Embedded WebView2 navigation failed',
        data: const {'source': 'contentCreator.webviewLoad'},
      );
    }
  }

  bool _isCurrentContentSttWebViewLoad(int generation, String url) {
    return mounted &&
        generation == _contentWebViewLoadGeneration &&
        ref.read(teleprompterProvider).sttWebViewUrl == url;
  }

  Future<void> _disposeContentSttWebViewController(
    WebviewController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (_) {
      // Cleanup failures are intentionally ignored. They must not mask the
      // bounded host lifecycle result or expose platform exception details.
    }
  }

  Future<void> _disposeContentSttWebViewResources(
    WebviewController? controller,
    Future<void> navigationTail,
  ) async {
    try {
      await navigationTail;
    } catch (_) {
      // Navigation failures are already reported by the owning operation.
    }
    if (controller != null) {
      await _disposeContentSttWebViewController(controller);
    }
  }

  void _clearContentSttWebView() {
    _contentWebViewLoadGeneration++;
    _pendingContentWebViewUrl = null;
    _loadedContentWebViewUrl = null;
  }
}
