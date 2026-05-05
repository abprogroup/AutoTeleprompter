part of 'script_editor_screen.dart';

extension _ScriptEditorFilePresentParts on _ScriptEditorScreenState {
  Future<void> _importFile() async {
    final supportedExts = PlatformFileImport.supportedExtensions;
    if (widget.shouldAutoLoad && _isPendingLoad) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExts,
        allowMultiple: false,
        dialogTitle: 'Load Script',
      );
    } catch (error, stack) {
      debugPrint('macOS file picker failed: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.folder_off_rounded, color: Color(0xFFFFBF00), size: 22),
            SizedBox(width: 10),
            Text('Could Not Open Files',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ]),
          content: Text(
            'macOS did not allow the file picker to open. Please try again.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK',
                  style: TextStyle(
                      color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (widget.shouldAutoLoad && mounted) Navigator.pop(context);
      if (mounted) setState(() => _isPendingLoad = false);
      return;
    }
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

    final text = _getRefinedFullTextWithoutBookmarkSigns();

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
      bytes = utf8.encode(MarkupExportService.toPlainText(text));
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
    );

    if (!mounted) return;

    if (savedPath == null) {
      // User cancelled the dialog — make that explicit
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save cancelled.'),
          backgroundColor: Colors.black54,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // On Windows, FilePicker.saveFile only returns the path — it does NOT write
    // the file. We must write it explicitly.
    final finalPath =
        savedPath.endsWith('.$format') ? savedPath : '$savedPath.$format';
    await File(finalPath).writeAsBytes(Uint8List.fromList(bytes));

    if (!mounted) return;

    final name = finalPath.split(RegExp(r'[\\/]')).last;
    if (!savedPath.endsWith('.$format')) {
      // OS stripped the extension — we added it back, but warn the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Saved as "$name" (extension was added automatically).'),
          backgroundColor: Colors.orange[800],
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Saved: $name')),
          ]),
          backgroundColor: Colors.green[800],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _clearScript() {
    setState(() {
      _loadText('');
      _saveHistory(description: 'Clear');
    });
  }

  void _startPresenting() async {
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    try {
      final settings = ref.read(settingsProvider);
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
    if (mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TeleprompterScreen()));
      if (mounted) {
        await _loadBookmarksForCurrentScript(force: true);
        await _reconcileEditorBookmarkSignsFromMetadata(recordHistory: false);
        _onSelectionChanged();
      }
    }
  }
}
