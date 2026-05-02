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
      setState(() => _isPendingLoad = false);
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

    // Generate bytes in the correct format for the chosen file type
    final List<int> bytes;
    if (format == 'docx') {
      bytes = DocxService.generate(text);
    } else if (format == 'rtf') {
      bytes = RtfService.generate(text);
    } else if (format == 'pages') {
      bytes = PagesService.generate(text);
    } else {
      // txt, md — plain UTF-8
      bytes = utf8.encode(text);
    }

    // Build filename with guaranteed extension — strip any prior extension first
    final safeName = _currentTitle
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(
            RegExp(r'\.(txt|pdf|docx|rtf|pages|md)$', caseSensitive: false),
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
  }

  void _clearScript() {
    _clearRecognizedBlockRange('clear-script');
    setState(() {
      _loadText('');
      _saveHistory(description: 'Clear');
    });
  }

  void _startPresenting() {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      unawaited(_saveBookmarks());
      ref.read(scriptProvider.notifier).loadText(
            _getRefinedFullText(),
            title: _currentTitle,
            sourceType: _sourceType,
            sessionId: _currentSessionId,
          );
    } catch (_) {}
    if (mounted) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TeleprompterScreen()))
          .then((_) {
        if (mounted) {
          unawaited(_loadBookmarksForCurrentScript(force: true));
        }
      });
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
                  onPressed: () => FocusScope.of(context).unfocus(),
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
                      shadowColor: const Color(0xFFFFBF00).withOpacity(0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
