part of 'script_editor_screen.dart';

extension _ScriptEditorFilePresentParts on _ScriptEditorScreenState {
  Future<void> _importFile() async {
    final supportedExts = PlatformFileImport.supportedExtensions;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open script',
      type: FileType.custom,
      allowedExtensions: supportedExts,
    );
    if (!mounted) return;
    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.isEmpty) {
      // v3.9.5.59: Fluid navigation fallback
      if (widget.shouldAutoLoad) Navigator.pop(context);
      _setEditorState(() => _isPendingLoad = false);
      return;
    }
    final selectedFile = File(selectedPath);
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
    LightweightDiagnostics.instance.record(
      'editor',
      'file import selected',
      data: {'extension': ext},
    );
    await ref
        .read(settingsProvider.notifier)
        .setLastImportPath(selectedFile.parent.path);
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

    final safeName =
        _currentTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').replaceAll(
              RegExp(
                r'\.(docx?|rtf|txt|text|log|md|pdf|odt|pages|atp)$',
                caseSensitive: false,
              ),
              '',
            );
    final settings = ref.read(settingsProvider);
    final ScriptBackupExport export;
    try {
      export = await LocalBackupService.buildScriptExportAsync(
        title: '$safeName.$format',
        text: text,
        sourceType: format,
        sourcePath: null,
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        textAlign: settings.textAlign,
        futureWordColor: settings.futureWordColor,
        isRtl: _inferEditorTextDirection(text),
        bookmarks: _bookmarks,
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'editor.saveExportBuild',
        data: {'format': format, 'title': _currentTitle},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export ${format.toUpperCase()}: $error'),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // txt, md — plain UTF-8

    // Build filename with guaranteed extension — strip any prior extension first
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save as ${format.toUpperCase()}',
      fileName: export.fileName,
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
    final extension = '.${export.extension.toLowerCase()}';
    final lowerSavedPath = savedPath.toLowerCase();
    final finalPath =
        lowerSavedPath.endsWith(extension) ? savedPath : '$savedPath$extension';
    await File(finalPath).writeAsBytes(
      Uint8List.fromList(export.bytes),
      flush: true,
    );
    LightweightDiagnostics.instance.record(
      'editor',
      'script exported',
      data: {
        'format': format,
        'fileName': finalPath.split(RegExp(r'[\\/]')).last
      },
    );

    if (!mounted) return;

    final name = finalPath.split(RegExp(r'[\\/]')).last;
    await _adoptSavedExportAsActiveScript(
      fileName: name,
      format: format,
      text: text,
      sourcePath: finalPath,
    );
    if (!mounted) return;
    if (!lowerSavedPath.endsWith(extension)) {
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

  bool _inferEditorTextDirection(String text) {
    var rtl = 0;
    var ltr = 0;
    for (final rune in text.runes) {
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

  Future<void> _adoptSavedExportAsActiveScript({
    required String fileName,
    required String format,
    required String text,
    required String sourcePath,
  }) async {
    final exportType = format.toUpperCase();
    final previousSessionId = _currentSessionId;
    final previousSourceType = _sourceType.toUpperCase();
    final identityChanged =
        _currentTitle != fileName || _sourceType.toUpperCase() != exportType;

    if (identityChanged) {
      await _forceRecentUpdate();
      if (!mounted) return;
      _setEditorState(() {
        _currentTitle = fileName;
        _sourceType = exportType;
        _currentSourcePath = sourcePath;
        _currentSessionId =
            'save_${DateTime.now().microsecondsSinceEpoch.toString()}';
      });
    } else {
      _sourceType = exportType;
      _currentSourcePath = sourcePath;
    }

    final settings = ref.read(settingsProvider);
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    await ref.read(settingsProvider.notifier).saveScript(
          text,
          title: _currentTitle,
          type: _sourceType,
          sourcePath: _currentSourcePath,
          sessionId: _currentSessionId,
          historyIndex: _historyIndex,
          fontSize: settings.fontSize,
          fontFamily: settings.fontFamily,
          lineSpacing: settings.lineSpacing,
          letterSpacing: settings.letterSpacing,
          wordSpacing: settings.wordSpacing,
          textAlign: settings.textAlign,
          scriptBgColor: settings.scriptBgColor,
          currentWordColor: settings.currentWordColor,
          futureWordColor: settings.futureWordColor,
          historyJson: historyJson,
        );

    ref.read(scriptProvider.notifier).loadText(
          text,
          title: _currentTitle,
          sourceType: _sourceType,
          sourcePath: _currentSourcePath,
          sessionId: _currentSessionId,
          historyIndex: _historyIndex,
          historyJson: historyJson,
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

    if (identityChanged &&
        previousSourceType == 'TEMP' &&
        previousSessionId != _currentSessionId) {
      await ref.read(settingsProvider.notifier).deleteRecentScript(
            sessionId: previousSessionId,
          );
    }
  }

  Future<void> _confirmDeleteCurrentScript() async {
    final sourcePath = _currentSourcePath?.trim();
    final sourceFile =
        sourcePath == null || sourcePath.isEmpty ? null : File(sourcePath);

    if (!mounted) return;
    final choice = await showScriptDeleteDialog(
      context,
      title: _currentTitle,
      sourcePath: sourcePath,
    );

    if (choice == null || !mounted) return;
    final shouldDeleteOriginal = choice.deleteSourceFile && sourceFile != null;
    _autoSaveTimer?.cancel();
    _recentTimer?.cancel();
    _recentPersistQueued = false;

    try {
      await ref.read(settingsProvider.notifier).deleteRecentScript(
            sessionId: _currentSessionId,
            title: _currentTitle,
          );
      if (shouldDeleteOriginal) {
        await sourceFile.delete();
      }
      ref.read(scriptProvider.notifier).discardActive();
      LightweightDiagnostics.instance.record(
        'editor',
        'script deleted',
        data: {
          'title': _currentTitle,
          'sessionId': _currentSessionId,
          'deletedSourceFile': shouldDeleteOriginal,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldDeleteOriginal
                ? 'Deleted script and source file.'
                : 'Deleted script from the app.',
          ),
        ),
      );
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'scriptEditor.deleteScript',
        data: {
          'title': _currentTitle,
          'sessionId': _currentSessionId,
          'sourcePath': sourcePath ?? '',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this script.')),
      );
    }
  }

  void _startPresenting() async {
    final editorSnapshot = _captureEditorModeReturnSnapshot();
    _suspendEditorFocusForReaderMode();
    LightweightDiagnostics.instance.record(
      'editor',
      'presenter opened',
      data: {
        'title': _currentTitle,
        'sessionId': _currentSessionId,
        'blockCount': _controllers.length,
      },
    );
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    await _forceRecentUpdate();
    try {
      final settings = ref.read(settingsProvider);
      ref.read(scriptProvider.notifier).loadText(
            _getRefinedFullTextWithoutBookmarkSigns(),
            title: _currentTitle,
            sourceType: _sourceType,
            sourcePath: _currentSourcePath,
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
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'scriptEditor.startPresentLoad',
        data: {
          'title': _currentTitle,
          'sessionId': _currentSessionId,
        },
      );
    }
    if (mounted) {
      final returnWordIndex = await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => const TeleprompterScreen()),
      );
      if (mounted) {
        await _loadBookmarksForCurrentScript(force: true);
        await _reconcileEditorBookmarkSignsFromMetadata(recordHistory: false);
        if (returnWordIndex != null) {
          _focusEditorWordIndex(returnWordIndex);
        } else {
          _restoreEditorModeReturnSnapshot(editorSnapshot);
        }
        _onSelectionChanged();
      }
    }
  }

  void _startContentCreator() {
    unawaited(_openContentCreator());
  }

  void _startAudioOnlyContentCreator() {
    unawaited(_openContentCreator(audioOnly: true));
  }

  Future<void> _openContentCreator({bool audioOnly = false}) async {
    final featureName = audioOnly ? 'Audio-only recording' : 'Content Creator';
    if (!await _ensureEditorPremiumAccess(featureName)) return;
    final editorSnapshot = _captureEditorModeReturnSnapshot();
    _suspendEditorFocusForReaderMode();
    LightweightDiagnostics.instance.record(
      'editor',
      audioOnly ? 'audio-only creator opened' : 'content creator opened',
      data: {
        'title': _currentTitle,
        'sessionId': _currentSessionId,
        'blockCount': _controllers.length,
        'audioOnly': audioOnly,
      },
    );
    await _forceRecentUpdate();
    try {
      final settings = ref.read(settingsProvider);
      if (audioOnly) {
        await ref
            .read(settingsProvider.notifier)
            .setContentCreatorRecordingFormat(
              AppSettings.contentCreatorRecordingFormatWav,
            );
        await ref
            .read(settingsProvider.notifier)
            .setContentCreatorRecordingAudioMode(
              AppSettings.contentCreatorRecordingAudioCamera,
            );
      } else {
        await ref
            .read(settingsProvider.notifier)
            .setContentCreatorRecordingFormat(
              AppSettings.contentCreatorRecordingFormatMp4,
            );
        await ref
            .read(settingsProvider.notifier)
            .setContentCreatorRecordingAudioMode(
              AppSettings.contentCreatorRecordingAudioCamera,
            );
      }
      ref.read(scriptProvider.notifier).loadText(
            _getRefinedFullTextWithoutBookmarkSigns(),
            title: _currentTitle,
            sourceType: _sourceType,
            sourcePath: _currentSourcePath,
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
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'scriptEditor.startContentCreatorLoad',
        data: {
          'title': _currentTitle,
          'sessionId': _currentSessionId,
        },
      );
    }
    if (!mounted) return;
    final returnWordIndex = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ContentCreatorScreen(audioOnlyEntry: audioOnly),
      ),
    );
    if (!mounted) return;
    if (returnWordIndex != null) {
      _focusEditorWordIndex(returnWordIndex);
    } else {
      _restoreEditorModeReturnSnapshot(editorSnapshot);
    }
    _onSelectionChanged();
  }
}
