part of 'script_editor_screen.dart';

enum _ExportConflictChoice {
  replace,
  keepBoth,
  cancel,
}

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
    final savedExports = await SavedExportRegistry.load();
    final exactDisplayName =
        ExportNameService.buildDisplayName(baseName, normalizedFormat);
    final exactSavedExport = SavedExportRegistry.findExact(
      entries: savedExports,
      baseName: baseName,
      format: normalizedFormat,
    );
    final existingDisplayNames = <String>{
      ...savedExports
          .where((entry) => ExportNameService.belongsToBaseName(
                displayName: entry.displayName,
                baseName: baseName,
                format: normalizedFormat,
              ))
          .map((entry) => entry.displayName),
    };

    var fileName = exactDisplayName;
    if (exactSavedExport != null && mounted) {
      final choice = await _showExportConflictDialog(
        exactSavedExport.displayName,
        message: '"${exactSavedExport.displayName}" was saved before by '
            'AutoTeleprompter.',
      );
      if (!mounted || choice == _ExportConflictChoice.cancel) return;
      if (choice == _ExportConflictChoice.replace) {
        await _writeAndroidExport(
          exactSavedExport,
          bytes,
          replaced: true,
        );
        return;
      }
      fileName = ExportNameService.nextDuplicateDisplayName(
        baseName: baseName,
        format: normalizedFormat,
        existingDisplayNames: existingDisplayNames,
      );
    }

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

    if (_looksLikeAndroidDuplicateName(
      requestedName: fileName,
      actualName: finalName,
      baseName: baseName,
      format: normalizedFormat,
    )) {
      final exactExport = await _findAndroidExportByDisplayName(
        baseName: baseName,
        format: normalizedFormat,
        displayName: exactDisplayName,
        excludeLocation: finalLocation,
      );
      final choice = await _showExportConflictDialog(
        exactDisplayName,
        message: 'Android found an existing "$exactDisplayName" and created '
            '"$finalName" instead.',
      );
      if (!mounted || choice == _ExportConflictChoice.cancel) {
        await AndroidFileAccess.deleteDocument(finalLocation);
        return;
      }
      if (choice == _ExportConflictChoice.replace) {
        await AndroidFileAccess.deleteDocument(finalLocation);
        if (exactExport == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Android did not give AutoTeleprompter access to the existing '
                '"$exactDisplayName". Save again and choose the existing file '
                'when Android asks where to save.',
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 7),
            ),
          );
          return;
        }
        await _writeAndroidExport(exactExport, bytes, replaced: true);
        return;
      }
    }

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

  Future<_ExportConflictChoice> _showExportConflictDialog(
    String displayName, {
    required String message,
  }) async {
    final result = await showDialog<_ExportConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Replace existing file?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExportConflictChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExportConflictChoice.keepBoth),
            child: const Text('Keep Both'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _ExportConflictChoice.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return result ?? _ExportConflictChoice.cancel;
  }

  bool _looksLikeAndroidDuplicateName({
    required String requestedName,
    required String actualName,
    required String baseName,
    required String format,
  }) {
    final requested = requestedName.toLowerCase().trim();
    final actual = actualName.toLowerCase().trim();
    if (actual == requested) return false;
    return ExportNameService.belongsToBaseName(
      displayName: actualName,
      baseName: baseName,
      format: format,
    );
  }

  Future<SavedExportEntry?> _findAndroidExportByDisplayName({
    required String baseName,
    required String format,
    required String displayName,
    required String excludeLocation,
  }) async {
    final expected = displayName.toLowerCase().trim();
    final candidates = await AndroidFileAccess.findDocumentsByDisplayBase(
      baseName: baseName,
      format: format,
    );
    for (final candidate in candidates) {
      if (candidate.location == excludeLocation) continue;
      if (candidate.displayName.toLowerCase().trim() != expected) continue;
      return SavedExportEntry(
        baseName: baseName,
        format: format.toLowerCase(),
        displayName: candidate.displayName,
        location: candidate.location,
      );
    }
    return null;
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
