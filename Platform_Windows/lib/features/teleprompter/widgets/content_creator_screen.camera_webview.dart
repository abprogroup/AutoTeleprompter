part of 'content_creator_screen.dart';

extension _ContentCreatorCameraWebView on _ContentCreatorScreenState {
  Future<void> _loadContentSttWebView(String url) async {
    if (!Platform.isWindows || !mounted) return;
    final generation = ++_contentWebViewLoadGeneration;
    _pendingContentWebViewUrl = url;
    WebView2RuntimeConfig.configureForLocalSttUrl(url);
    final runtimeVersion = await _readContentWebViewRuntimeVersion();
    if (!_isCurrentContentSttWebViewLoad(generation, url)) return;
    WebviewController? controller = _contentWebviewController;
    var createdController = false;

    if (controller == null) {
      try {
        controller = WebviewController();
        createdController = true;
        await controller.initialize();
      } catch (_) {
        if (controller != null) {
          await _disposeContentSttWebViewController(controller);
        }
        if (_isCurrentContentSttWebViewLoad(generation, url)) {
          _pendingContentWebViewUrl = null;
          ref.read(teleprompterProvider.notifier).reportEmbeddedSttHostFailure(
                reasonCode: 'webview-init-failed',
                runtimeVersion: runtimeVersion,
              );
        }
        _logContentDebug('content webview init failed');
        LightweightDiagnostics.instance.record(
          'error',
          'Embedded WebView2 initialization failed',
          data: const {'source': 'contentCreator.webviewInit'},
        );
        return;
      }

      if (!_isCurrentContentSttWebViewLoad(generation, url)) {
        await _disposeContentSttWebViewController(controller);
        return;
      }
      _updateContentCreatorState(() {
        _contentWebviewController = controller;
      });
    }

    try {
      await controller.loadUrl(url);
      if (!_isCurrentContentSttWebViewLoad(generation, url)) {
        if (createdController && controller != _contentWebviewController) {
          await _disposeContentSttWebViewController(controller);
        }
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
          ref.read(teleprompterProvider.notifier).reportEmbeddedSttHostFailure(
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

  Future<String?> _readContentWebViewRuntimeVersion() async {
    try {
      final version = await WebviewController.getWebViewVersion().timeout(
        const Duration(seconds: 3),
      );
      return sanitizeWebView2RuntimeVersion(version);
    } catch (_) {
      return null;
    }
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

  void _clearContentSttWebView() {
    _contentWebViewLoadGeneration++;
    _pendingContentWebViewUrl = null;
    _loadedContentWebViewUrl = null;
    final controller = _contentWebviewController;
    if (controller == null) return;
    _updateContentCreatorState(() => _contentWebviewController = null);
    unawaited(_disposeContentSttWebViewController(controller));
  }
}
