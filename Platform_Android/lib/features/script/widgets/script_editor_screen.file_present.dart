part of 'script_editor_screen.dart';

extension _ScriptEditorFilePresentParts on _ScriptEditorScreenState {
  Future<void> _importFile() async {
    final supportedExts = PlatformFileImport.supportedExtensions;
    final result = await FilePicker.platform
        .pickFiles(type: FileType.any, allowMultiple: false);
    if (!mounted) return;
    if (result == null || result.files.single.path == null) {
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
            Text(
              'Not Supported',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${selectedFile.path.split('/').last}"',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '.${ext.toUpperCase()} files cannot be used as scripts.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              const Text(
                'Supported formats:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                PlatformFileImport.formatsLabel,
                style: const TextStyle(
                  color: Color(0xFFFFBF00),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFFFFBF00),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    await _forceRecentUpdate();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ScriptEditorScreen(pendingFile: selectedFile),
      ),
    );
  }

  Future<void> _saveScript() async {
    final format = await EditorDialogs.showSaveFormatDialog(context);
    if (format == null || !mounted) return;
    final normalizedFormat = format.toLowerCase();

    final text = _getRefinedFullTextWithoutBookmarkSigns();
    final Uint8List bytes;
    if (normalizedFormat == 'docx') {
      bytes = Uint8List.fromList(DocxService.generate(text));
    } else if (normalizedFormat == 'rtf') {
      bytes = Uint8List.fromList(RtfService.generate(text));
    } else if (normalizedFormat == 'pages') {
      bytes = Uint8List.fromList(PagesService.generate(text));
    } else {
      bytes = Uint8List.fromList(
        utf8.encode(MarkupExportService.toPlainText(text)),
      );
    }

    final baseName =
        ExportNameService.sanitizeBaseName(_currentTitle, normalizedFormat);
    final fileName = ExportNameService.buildDisplayName(
      baseName,
      normalizedFormat,
    );

    final createdLocation = await AndroidFileAccess.createExportFile(
      displayName: fileName,
      mimeType: ExportNameService.mimeTypeForFormat(normalizedFormat),
    );
    if (!mounted) return;

    if (createdLocation == null || createdLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not create "$fileName" in the selected folder.',
          ),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    var finalLocation = createdLocation;
    final locationHint =
        AndroidFileAccess.displayNameHintFromLocation(finalLocation);
    var finalName =
        await AndroidFileAccess.displayNameForLocation(createdLocation) ??
            locationHint;

    final repairedName = ExportNameService.repairBrokenDuplicateSuffix(
      finalName,
      normalizedFormat,
    );
    if (repairedName != finalName) {
      final renamedLocation = await AndroidFileAccess.rename(
        finalLocation,
        repairedName,
      );
      if (renamedLocation == null || renamedLocation.trim().isEmpty) {
        await AndroidFileAccess.deleteDocument(finalLocation);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Android created "$finalName", which breaks the file extension. '
              'The file was not saved. Try Keep Both with a different name in '
              'the save picker.',
            ),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 7),
          ),
        );
        return;
      }
      finalLocation = renamedLocation;
      finalName =
          await AndroidFileAccess.displayNameForLocation(finalLocation) ??
              repairedName;
    }

    if (!ExportNameService.hasExpectedExtension(finalName, normalizedFormat)) {
      await AndroidFileAccess.deleteDocument(finalLocation);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Android created "$finalName" without the .$normalizedFormat '
            'extension. The file was not saved.',
          ),
          backgroundColor: Colors.orange[800],
          duration: const Duration(seconds: 7),
        ),
      );
      return;
    }

    await _writeAndroidExport(
      SavedExportEntry(
        baseName: baseName,
        format: normalizedFormat,
        displayName: finalName,
        location: finalLocation,
      ),
      bytes,
    );
  }

  Future<void> _writeAndroidExport(
    SavedExportEntry entry,
    Uint8List bytes, {
    bool replaced = false,
  }) async {
    try {
      await AndroidFileAccess.writeBytes(entry.location, bytes);
      await SavedExportRegistry.record(entry);
    } catch (_) {
      if (!replaced) {
        await AndroidFileAccess.deleteDocument(entry.location);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${replaced ? 'replace' : 'save'} '
            '"${entry.displayName}" in the selected folder.',
          ),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${replaced ? 'Replaced' : 'Saved'}: '
                '${entry.displayName}'),
          ),
        ]),
        backgroundColor: Colors.green[800],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearScript() {
    setState(() {
      _loadText('');
      _saveHistory(description: 'Clear');
    });
  }

  void _startPresenting({bool continueWalkthrough = false}) async {
    final editorSnapshot = _captureEditorModeReturnSnapshot();
    _suspendEditorFocusForReaderMode();
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
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              TeleprompterScreen(showWalkthroughGuide: continueWalkthrough)));
      if (mounted) {
        await _loadBookmarksForCurrentScript(force: true);
        await _reconcileEditorBookmarkSignsFromMetadata(recordHistory: false);
        _restoreEditorModeReturnSnapshot(editorSnapshot);
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
    try {
      final settings = ref.read(settingsProvider);
      await ref
          .read(settingsProvider.notifier)
          .setContentCreatorRecordingFormat(
            audioOnly
                ? AppSettings.contentCreatorRecordingFormatAudio
                : AppSettings.contentCreatorRecordingFormatMp4,
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
    if (!mounted) return;
    _restoreEditorModeReturnSnapshot(editorSnapshot);
    _onSelectionChanged();
  }
}
