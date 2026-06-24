part of 'script_editor_screen.dart';

extension _ScriptEditorFilePresentParts on _ScriptEditorScreenState {
  Future<void> _importFile() async {
    _clearRecognizedBlockRange('import-file');
    final supportedExts = PlatformFileImport.supportedExtensions;
    final result = await FilePicker.platform
        .pickFiles(type: FileType.any, allowMultiple: false);
    if (!mounted) return;
    if (result == null || result.files.single.path == null) {
      // v3.9.5.59: Fluid navigation fallback
      if (widget.shouldAutoLoad) Navigator.pop(context);
      _setEditorState(() => _isPendingLoad = false);
      return;
    }
    final selectedFile = File(result.files.single.path!);
    final ext = selectedFile.path.split('.').last.toLowerCase();

    if (!supportedExts.contains(ext)) {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.block_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 10),
            Text("Not Supported",
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${selectedFile.path.split('/').last}"',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('.${ext.toUpperCase()} files cannot be used as scripts.',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              const Text('Supported formats:',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text(PlatformFileImport.formatsLabel,
                  style: const TextStyle(
                      color: Color(0xFFFFBF00),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK",
                    style: TextStyle(
                        color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)))
          ],
        ),
      );
      return;
    }

    // Persist the current script's session before swapping editors so its
    // history index / recent entry are not lost.
    await _forceRecentUpdate();
    if (!mounted) return;

    // Replace this editor with a fresh instance that runs the standard
    // pending-file load flow (conflict detection focuses an existing
    // recent if the file is already known, otherwise it loads as new).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => ScriptEditorScreen(pendingFile: selectedFile)),
    );
  }

  Future<void> _saveScript() async {
    final format = await EditorDialogs.showSaveFormatDialog(context);
    if (format == null || !mounted) return;

    final text = _getRefinedFullText();

    final defaultRtl = _inferEditorTextDirection(text);

    // Generate bytes in the correct format for the chosen file type.
    final List<int> bytes;
    if (format == 'docx') {
      bytes = DocxService.generate(text, defaultRtl: defaultRtl);
    } else if (format == 'rtf') {
      bytes = RtfService.generate(text, defaultRtl: defaultRtl);
    } else if (format == 'odt') {
      bytes = OdtService.generate(text, defaultRtl: defaultRtl);
    } else if (format == 'pdf') {
      bytes = await PdfExportService.generate(text, defaultRtl: defaultRtl);
    } else if (format == 'pages') {
      bytes = PagesService.generate(text);
    } else {
      // txt, md, log, text - visible UTF-8 only; never leak private markup.
      bytes = utf8.encode(
        MarkupExportService.toPlainText(text, defaultRtl: defaultRtl),
      );
    }

    // Build filename with guaranteed extension — strip any prior extension first
    final safeName = _currentTitle
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(
            RegExp(r'\.(txt|pdf|docx|rtf|odt|pages|md|log|text)$',
                caseSensitive: false),
            '');
    final fileName = '$safeName.$format';

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save as ${format.toUpperCase()}',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );

    // If the user saved but the OS stripped the extension, warn them
    if (savedPath != null && !savedPath.endsWith('.$format')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'File saved. Note: you may need to rename it to add ".$format" extension.'),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
    if (savedPath != null) {
      _sourceType = format.toUpperCase();
      await _forceRecentUpdate();
    }
  }

  bool _inferEditorTextDirection(String text) {
    final directionText = _plainTextForDirection(text);
    var rtl = 0;
    var ltr = 0;
    for (final rune in directionText.runes) {
      if ((rune >= 0x0590 && rune <= 0x05FF) ||
          (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F)) {
        rtl++;
      } else if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        ltr++;
      }
    }
    return rtl > 0 && rtl >= ltr;
  }

  String _plainTextForDirection(String text) {
    try {
      return MarkupExportService.toPlainText(text);
    } catch (_) {
      return text;
    }
  }

  void _clearScript() {
    _clearRecognizedBlockRange('clear-script');
    _setEditorState(() {
      _loadText('');
      _saveHistory(description: 'Clear');
    });
  }

  Future<void> _startPresenting({bool continueWalkthrough = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final refinedText = _getRefinedFullTextWithoutBookmarkSigns();
    if (refinedText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add script text before Present mode.')),
      );
      return;
    }
    try {
      await _syncBookmarksFromEditorSigns(notify: false, save: true);
      if (!mounted) return;
      ref.read(scriptProvider.notifier).loadText(
            refinedText,
            title: _currentTitle,
            sourceType: _sourceType,
            sessionId: _currentSessionId,
          );
    } catch (_) {}
    if (mounted) {
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => TeleprompterScreen(
                  showWalkthroughGuide: continueWalkthrough)))
          .then((_) {
        if (mounted) {
          unawaited(_reconcileEditorBookmarkSignsFromMetadata());
        }
      });
    }
  }

  bool _readEditorPremiumAccess() {
    final auth = ref.read(authProvider);
    return auth.hasPremiumAccess;
  }

  Future<bool> _ensureEditorPremiumAccess(String featureName) async {
    if (_readEditorPremiumAccess()) return true;
    final shouldSignIn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('$featureName requires Pro',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Sign in with a Pro account to unlock creator tools.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (shouldSignIn == true) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(initialPasswordMode: true),
        ),
      );
      if (!mounted) return false;
    }
    return _readEditorPremiumAccess();
  }

  void _startContentCreator() {
    unawaited(_openContentCreator());
  }

  void _startAudioOnlyContentCreator() {
    unawaited(_openContentCreator(audioOnly: true));
  }

  Future<void> _openContentCreator({bool audioOnly = false}) async {
    final featureName = audioOnly ? 'Audio recorder' : 'Content Creator';
    if (!await _ensureEditorPremiumAccess(featureName)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _forceRecentUpdate();
    if (!mounted) return;

    try {
      final settings = ref.read(settingsProvider);
      final settingsNotifier = ref.read(settingsProvider.notifier);
      await settingsNotifier.setContentCreatorRecordingFormat(
        audioOnly
            ? AppSettings.contentCreatorRecordingFormatAudio
            : AppSettings.contentCreatorRecordingFormatMp4,
      );
      await settingsNotifier.setContentCreatorRecordingAudioMode(
        AppSettings.contentCreatorRecordingAudioCamera,
      );
      ref.read(scriptProvider.notifier).loadText(
            _getRefinedFullTextWithoutBookmarkSigns(),
            title: _currentTitle,
            sourceType: _sourceType,
            sessionId: _currentSessionId,
            historyIndex: _historyIndex,
            historyJson: jsonEncode(_history.map((e) => e.toJson()).toList()),
            fontSize: settings.fontSize,
            fontFamily: settings.fontFamily,
            lineSpacing: settings.lineSpacing,
            letterSpacing: settings.letterSpacing,
            wordSpacing: settings.wordSpacing,
            textAlign: settings.textAlign,
            scriptBgColor: settings.scriptBgColor,
            currentWordColor: settings.currentWordColor,
            futureWordColor: settings.futureWordColor,
          );
    } catch (_) {}

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContentCreatorScreen(audioOnlyEntry: audioOnly),
      ),
    );
    if (mounted) {
      unawaited(_reconcileEditorBookmarkSignsFromMetadata());
      _onSelectionChanged();
    }
  }

  Widget _buildBottomActions({bool keyboardVisible = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (keyboardVisible && PlatformKeyboard.showDoneBar)
          Container(
            color: const Color(0xFF1C1C1E),
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _keyboardDismissedForSelection = true;
                    ContextMenuController.removeAny();
                    _promoteNativeSelectionToOverlay();
                    FocusScope.of(context).unfocus();
                    _scheduleMobileSelectionGeometryRefresh();
                  },
                  child: const Text('Done',
                      style: TextStyle(
                          color: Color(0xFFFFBF00),
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    key: _walkthroughPresentKey,
                    onPressed: _startPresenting,
                    icon:
                        const Icon(Icons.play_circle_filled_rounded, size: 24),
                    label: const Text('PRESENT',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 12,
                      shadowColor:
                          const Color(0xFFFFBF00).withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _bottomIconAction(
                  icon: Icons.video_camera_front_rounded,
                  tooltip: 'Content Creator',
                  onPressed: _startContentCreator,
                ),
                const SizedBox(width: 8),
                _bottomIconAction(
                  icon: Icons.mic_rounded,
                  tooltip: 'Audio recorder',
                  onPressed: _startAudioOnlyContentCreator,
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomIconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1E1E1E),
            foregroundColor: const Color(0xFFFFBF00),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
