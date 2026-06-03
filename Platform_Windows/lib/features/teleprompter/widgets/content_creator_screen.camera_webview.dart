part of 'content_creator_screen.dart';

extension _ContentCreatorCameraWebView on _ContentCreatorScreenState {
  Future<void> _initContentWebViewController() async {
    if (_contentWebviewController != null) return;
    try {
      final controller = WebviewController();
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _updateContentCreatorState(() {
        _contentWebviewController = controller;
      });
      final url = ref.read(teleprompterProvider).sttWebViewUrl;
      if (url != null && url != _loadedContentWebViewUrl) {
        await _loadContentSttWebView(url);
      }
    } catch (e, stack) {
      _logContentDebug('content webview init failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.webviewInit',
      );
    }
  }

  Future<void> _loadContentSttWebView(String url) async {
    WebView2RuntimeConfig.configureForLocalSttUrl(url);
    _loadedContentWebViewUrl = url;
    if (_contentWebviewController == null) {
      await _initContentWebViewController();
    }
    try {
      await _contentWebviewController?.loadUrl(url);
      _logContentDebug('content webview loaded $url');
    } catch (e, stack) {
      _logContentDebug('content webview load failed $e');
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'contentCreator.webviewLoad',
      );
    }
  }
}
