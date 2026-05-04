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
    final treeUri = await AndroidFileAccess.pickExportFolder();
    if (!mounted) return;
    if (treeUri == null || treeUri.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save cancelled.'),
          backgroundColor: Colors.black54,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!await AndroidFileAccess.hasPersistedExportFolder(treeUri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Android did not grant write access to that folder.',
          ),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    await ExportFolderRegistry.save(treeUri);

    final folderExports = await AndroidFileAccess.listExportFolder(treeUri);
    final exactDisplayName =
        ExportNameService.buildDisplayName(baseName, normalizedFormat);
    final exactFolderExport =
        _findDeviceExportByDisplayName(folderExports, exactDisplayName);
    final existingDisplayNames = <String>{
      ...folderExports.map((e) => e.displayName),
    };

    if (exactFolderExport != null && mounted) {
      final choice = await _showExportConflictDialog(
        exactFolderExport.displayName,
        message: '"${exactFolderExport.displayName}" already exists in the '
            'selected folder.',
      );
      if (!mounted || choice == _ExportConflictChoice.cancel) return;
      if (choice == _ExportConflictChoice.replace) {
        await _writeAndroidExport(
          SavedExportEntry(
            baseName: baseName,
            format: normalizedFormat,
            displayName: exactFolderExport.displayName,
            location: exactFolderExport.location,
          ),
          bytes,
          replaced: true,
        );
        return;
      }
    }

    final fileName = exactFolderExport != null
        ? ExportNameService.nextDuplicateDisplayName(
            baseName: baseName,
            format: normalizedFormat,
            existingDisplayNames: existingDisplayNames,
          )
        : ExportNameService.buildDisplayName(baseName, normalizedFormat);

    final createdLocation = await AndroidFileAccess.createExportDocument(
      treeUri: treeUri,
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

    final locationHint = AndroidFileAccess.displayNameHintFromLocation(
      createdLocation,
    );
    final finalName =
        await AndroidFileAccess.displayNameForLocation(createdLocation) ??
            locationHint;

    if (finalName.trim() != fileName ||
        !ExportNameService.hasExpectedExtension(finalName, normalizedFormat)) {
      await AndroidFileAccess.deleteDocument(createdLocation);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The storage provider created "$finalName" instead of "$fileName". '
            'The file was not saved so duplicates stay extension-safe.',
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
        location: createdLocation,
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

  AndroidDocumentEntry? _findDeviceExportByDisplayName(
    List<AndroidDocumentEntry> entries,
    String displayName,
  ) {
    final expected = displayName.toLowerCase().trim();
    for (final entry in entries) {
      if (entry.displayName.toLowerCase().trim() == expected) {
        return entry;
      }
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
