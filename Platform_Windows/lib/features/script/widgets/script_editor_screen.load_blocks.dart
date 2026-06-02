part of 'script_editor_screen.dart';

extension _ScriptEditorLoadBlockParts on _ScriptEditorScreenState {
  Future<void> _runPendingFileLoad(File file) async {
    try {
      final settingsBeforeImport = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settingsBeforeImport.lastTextColor);
      _lastChosenHighlightColor =
          Color(settingsBeforeImport.lastHighlightColor);

      final result = await ref.read(scriptProvider.notifier).parseFile(file);
      if (result.isError) {
        if (!mounted) return;
        await _showImportErrorDialog(
          title: file.path.split(RegExp(r'[\\/]')).last,
          message: result.errorMessage ?? result.text,
        );
        return;
      }
      final parsedSettings = ref.read(settingsProvider);
      final settingsNotifier = ref.read(settingsProvider.notifier);
      if (settingsBeforeImport.importColorMode ==
          AppSettings.importColorModeDocument) {
        final parsedBgChanged =
            parsedSettings.scriptBgColor != settingsBeforeImport.scriptBgColor;
        await settingsNotifier.setDocumentImportAppearance(
          scriptBgColor: parsedBgChanged ? parsedSettings.scriptBgColor : null,
        );
      } else {
        await settingsNotifier.resetToDefaultAppearance();
      }
      final String content = result.text;
      final String title = file.path.split(RegExp(r'[\\/]')).last;

      // Conflict Detection Logic
      String? existingMeta;
      final List<String> recentScripts =
          ref.read(settingsProvider).recentScripts;
      String normalize(String? t) => (t ?? '').replaceAll('\r', '').trim();
      final String normalizedNew = normalize(content);

      for (final meta in recentScripts) {
        try {
          final decoded = jsonDecode(meta);
          if (decoded['title'] == title) {
            existingMeta = meta;
            break;
          }
        } catch (error) {
          LightweightDiagnostics.instance.record(
            'script',
            'ignored malformed recent metadata during file conflict check',
            data: {
              'source': 'fileLoadConflictCheck',
              'title': title,
              'error': error.toString(),
            },
          );
        }
      }

      String finalContent = content;
      String finalType = title.split('.').last.toUpperCase();
      String finalSourcePath = file.path;
      String? finalSessionId;
      String? finalHistoryJson;

      if (existingMeta != null) {
        final decoded = jsonDecode(existingMeta);
        final secureData = await SecureScriptStore().readFromMetadata(
          Map<String, dynamic>.from(decoded),
        );
        final String existingContent = secureData?.text ?? '';
        final String sessionId = decoded['sessionId'];
        final String type = decoded['type'] ?? 'TXT';
        final metaSourcePath = decoded['sourcePath'];
        if (metaSourcePath is String && metaSourcePath.trim().isNotEmpty) {
          finalSourcePath = metaSourcePath;
        }

        if (normalize(existingContent) == normalizedNew) {
          finalContent = existingContent;
          finalType = type;
          finalSessionId = sessionId;
          finalHistoryJson = secureData?.historyJson;
        } else {
          if (!mounted) return;
          final choice = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFFBF00), size: 22),
                SizedBox(width: 10),
                Text("Conflict Detected",
                    style: TextStyle(color: Colors.white, fontSize: 17)),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('"$title" is already in your Recents.',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'The version on your disk is different from the version in your history. What do you want to do?',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text("KEEP HISTORY",
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'reload'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black),
                  child: const Text("RELOAD & DISCARD EDITS",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );

          if (choice == 'reload') {
            finalType = type;
            finalSessionId = sessionId;
          } else if (choice == 'cancel') {
            finalContent = existingContent;
            finalType = type;
            finalSessionId = sessionId;
            finalHistoryJson = secureData?.historyJson;
          } else {
            if (mounted) Navigator.pop(context);
            return;
          }
        }
      }

      if (!mounted) return;
      _currentTitle = title;
      _sourceType = finalType;
      _currentSourcePath = finalSourcePath;
      _currentSessionId = finalSessionId ?? _currentSessionId;
      _loadText(finalContent);
      unawaited(_loadBookmarksForCurrentScript());

      if (finalHistoryJson != null) {
        try {
          final List<dynamic> historyData = jsonDecode(finalHistoryJson);
          _history.clear();
          _history.addAll(historyData.map((d) => EditorState.fromJson(d)));
          _historyIndex = _history.length - 1;
          if (_history.isNotEmpty) _applyState(_history.last);
        } catch (error, stack) {
          LightweightDiagnostics.instance.recordError(
            error,
            stack,
            source: 'scriptEditor.fileHistoryRestore',
          );
        }
      } else {
        _saveHistory(description: 'Import');
      }
      _forceRecentUpdate();
    } finally {
      if (mounted) _setEditorState(() => _isPendingLoad = false);
    }
  }

  Future<void> _showImportErrorDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.block_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 10),
          Text(
            'Import Blocked',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.white70)),
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
  }

  void _clearControllers() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
    _blockKeys.clear();
  }

  void _addBlock(int index, {String text = ''}) {
    void insertBlock() {
      final controller = MarkupController(text: text);
      final blockKey = GlobalKey(); // v3.9.5.66

      final node = FocusNode(onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        final key = event.logicalKey;
        if (_isArrowKey(key) || _isHomeEndKey(key)) {
          return _handleEditorArrowKey(node, event);
        }

        if (key == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          final idx = _controllers.indexOf(controller);
          if (idx == -1) return KeyEventResult.handled;
          if (_replaceAppSelectionWithParagraphBreak()) {
            _saveHistory(description: 'Split Paragraph');
            return KeyEventResult.handled;
          }
          final text = controller.text;
          final replacementSelection =
              _selectionForEnterReplacement(controller);
          if (replacementSelection != null) {
            final start =
                replacementSelection.start.clamp(0, text.length).toInt();
            final end =
                replacementSelection.end.clamp(start, text.length).toInt();
            _splitBlockAtSelection(
              controller: controller,
              blockIndex: idx,
              start: start,
              end: end,
            );
          } else {
            final sel = controller.selection;
            if (sel.isValid) {
              final offset = sel.extentOffset.clamp(0, text.length).toInt();
              _splitBlockAtSelection(
                controller: controller,
                blockIndex: idx,
                start: offset,
                end: offset,
              );
            }
          }
          _saveHistory(description: 'Split Paragraph');
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.backspace && controller.text.isEmpty) {
          final idx = _controllers.indexOf(controller);
          if (_controllers.length > 1 && idx != -1) {
            _setEditorState(() {
              _controllers.removeAt(idx).dispose();
              _focusNodes.removeAt(idx).dispose();
              _blockKeys.removeAt(idx);
              if (idx > 0) _focusNodes[idx - 1].requestFocus();
            });
            _saveHistory(description: 'Delete Empty Line');
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.backspace &&
            controller.selection.isCollapsed &&
            _isCaretAtVisibleBlockStart(controller)) {
          final idx = _controllers.indexOf(controller);
          if (idx > 0) {
            if (_isVisuallyEmptyBlock(_controllers[idx - 1].text)) {
              _deletePreviousEmptyBlockFromCaret(idx);
              _saveHistory(description: 'Delete Empty Line');
            } else {
              _joinCurrentBlockIntoPrevious(idx);
              _saveHistory(description: 'Join Paragraph');
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      });

      node.addListener(() {
        if (node.hasFocus) {
          _lastFocusedController = controller;
          // Restore native-selection rendering on focus regain by clearing
          // only the collapsed externalSelection sentinel set during focus
          // loss. A non-collapsed externalSelection is an app-owned selection
          // that must survive toolbar focus changes so typing/replacing still
          // edits the selected text instead of appending at its end.
          if (controller.externalSelection != null &&
              controller.externalSelection!.isCollapsed &&
              !_isGlobalSelection &&
              !(_overlayKey.currentState?.hasSelection ?? false)) {
            controller.externalSelection = null;
            controller.externalVisibleSelection = null;
            controller.refresh();
          }
          _onSelectionChanged();
        } else {
          if (_isDirty && !_isCommandExecuting) {
            // Flush any pending typing bulk on focus loss
            if (_typingCharCount > 0) {
              _commitHistory('Edit Text');
            }
            _isDirty = false;
          }
          // On focus loss, suppress any lingering native selection highlight
          // (set via TextField drag-select). MarkupController otherwise falls
          // through to controller.selection and renders amber on the now-
          // unfocused block - which is the "two highlights at once" bug.
          // Skip while a global multi-block selection or overlay drag is active
          // (their externalSelection values must not be overwritten here).
          final overlayActive = _overlayKey.currentState?.hasSelection ?? false;
          if (!_isGlobalSelection &&
              !_editorToolbarFocusGuard &&
              !overlayActive &&
              !controller.isGlobalSelected &&
              controller.externalVisibleSelection == null &&
              !controller.selection.isCollapsed) {
            controller.externalSelection =
                const TextSelection.collapsed(offset: 0);
            controller.externalVisibleSelection = null;
            controller.refresh();
          }
        }
      });

      String lastText = text;
      controller.addListener(() {
        if (_isLoading) return;
        if (controller.text == lastText) {
          if (node.hasFocus) {
            if (!controller.selection.isCollapsed) {
              _preservedSelection = controller.selection;
            }
            _onSelectionChanged();
            // Escalate native full-block select to global Select All.
            // Catches all paths: context menu, keyboard, platform menu.
            // Skip when overlay has active handles (refine mode) to avoid
            // infinite loop: refine clears isGlobal -> escalation re-selects -> loop.
            final overlayActive =
                _overlayKey.currentState?.hasSelection ?? false;
            if (!_isGlobalSelection &&
                !_isCommandExecuting &&
                !overlayActive &&
                !HardwareKeyboard.instance.isShiftPressed &&
                controller.text.isNotEmpty &&
                controller.selection.baseOffset == 0 &&
                controller.selection.extentOffset == controller.text.length) {
              _selectAllBlocks();
            }
          }
          return;
        }
        final previousText = lastText;
        final hadAppSelectionBeforeEdit = !_isCommandExecuting &&
            (controller.isGlobalSelected ||
                _isGlobalSelection ||
                (_overlayKey.currentState?.hasSelection ?? false) ||
                (controller.externalSelection != null &&
                    controller.externalSelection!.isValid &&
                    !controller.externalSelection!.isCollapsed));
        if (hadAppSelectionBeforeEdit &&
            _replaceAppSelectionWithText(
              editedController: controller,
              previousText: previousText,
              currentText: controller.text,
            )) {
          lastText = controller.text;
          _isDirty = true;
          _verticalArrowPreferredX = null;
          _onBlockChanged();
          return;
        }
        lastText = controller.text;
        _isDirty = true;
        _verticalArrowPreferredX = null;
        // v4.1.2: When the user edits text (not inside a style command), clear
        // any pinned externalSelection so stale amber doesn't linger after typing.
        if (hadAppSelectionBeforeEdit) {
          _clearAppSelectionAfterTextInput(controller);
        } else if (!_isCommandExecuting &&
            controller.externalSelection != null) {
          controller.externalSelection = null;
          controller.externalVisibleSelection = null;
          controller.refresh();
        }
        _onBlockChanged();
      });

      _controllers.insert(index, controller);
      _focusNodes.insert(index, node);
      _blockKeys.insert(index, blockKey);
    }

    if (_isBulkLoadingBlocks) {
      insertBlock();
    } else {
      _setEditorState(insertBlock);
    }

    if (!_isBulkLoadingBlocks && text.isEmpty) {
      Future.delayed(Duration.zero, () => _focusNodes[index].requestFocus());
    }
  }

  TextSelection? _selectionForEnterReplacement(MarkupController controller) {
    final external = controller.externalSelection;
    if (external != null && external.isValid && !external.isCollapsed) {
      return TextSelection(
        baseOffset: external.start,
        extentOffset: external.end,
      );
    }
    final native = controller.selection;
    if (native.isValid && !native.isCollapsed) {
      return TextSelection(baseOffset: native.start, extentOffset: native.end);
    }
    if (controller.isGlobalSelected && controller.text.isNotEmpty) {
      return TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    }
    return null;
  }

  bool _replaceAppSelectionWithParagraphBreak() {
    final ranges = _activeAppSelectionRangesForEnter();
    if (ranges.length <= 1) return false;

    final first = ranges.first;
    final last = ranges.last;
    final firstController = _controllers[first.blockIndex];
    final lastController = _controllers[last.blockIndex];
    final firstStart =
        first.selection.start.clamp(0, firstController.text.length).toInt();
    final lastEnd =
        last.selection.end.clamp(0, lastController.text.length).toInt();
    final before = firstController.text.substring(0, firstStart);
    final after = MarkupController.suffixWithOpenTagContext(
      lastController.text,
      lastEnd,
    );
    final newCaretOffset =
        MarkupController.openTagsAt(lastController.text, lastEnd).length;

    _isCommandExecuting = true;
    final previousBulkState = _isBulkLoadingBlocks;
    try {
      _setEditorState(() {
        firstController.value = TextEditingValue(
          text: before,
          selection: TextSelection.collapsed(offset: before.length),
        );
        for (var i = last.blockIndex; i > first.blockIndex; i--) {
          _controllers.removeAt(i).dispose();
          _focusNodes.removeAt(i).dispose();
          _blockKeys.removeAt(i);
        }
        _isBulkLoadingBlocks = true;
        _addBlock(first.blockIndex + 1, text: after);
        _isBulkLoadingBlocks = previousBulkState;
      });
      _clearAppSelectionAfterTextInput(firstController);
      if (first.blockIndex + 1 < _controllers.length) {
        _lastFocusedController = _controllers[first.blockIndex + 1];
        _controllers[first.blockIndex + 1].selection =
            TextSelection.collapsed(offset: newCaretOffset);
      }
    } finally {
      _isBulkLoadingBlocks = previousBulkState;
      _isCommandExecuting = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || first.blockIndex + 1 >= _focusNodes.length) return;
      _lastFocusedController = _controllers[first.blockIndex + 1];
      _focusNodes[first.blockIndex + 1].requestFocus();
      _controllers[first.blockIndex + 1].selection =
          TextSelection.collapsed(offset: newCaretOffset);
    });
    return true;
  }

  List<_EnterSelectionRange> _activeAppSelectionRangesForEnter() {
    final ranges = <_EnterSelectionRange>[];
    for (var i = 0; i < _controllers.length; i++) {
      final controller = _controllers[i];
      final selection = _appSelectionForEnter(controller);
      if (selection == null) continue;
      ranges.add(_EnterSelectionRange(i, selection));
    }
    return ranges;
  }

  TextSelection? _appSelectionForEnter(MarkupController controller) {
    final length = controller.text.length;
    if (controller.isGlobalSelected) {
      return TextSelection(baseOffset: 0, extentOffset: length);
    }
    final external = controller.externalSelection;
    if (external == null || !external.isValid || external.isCollapsed) {
      return null;
    }
    final start = external.start.clamp(0, length).toInt();
    final end = external.end.clamp(start, length).toInt();
    if (end <= start) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  void _splitBlockAtSelection({
    required MarkupController controller,
    required int blockIndex,
    required int start,
    required int end,
  }) {
    final text = controller.text;
    final safeStart = start.clamp(0, text.length).toInt();
    final safeEnd = end.clamp(safeStart, text.length).toInt();
    final before = text.substring(0, safeStart);
    final after = MarkupController.suffixWithOpenTagContext(text, safeEnd);
    final newCaretOffset = MarkupController.openTagsAt(text, safeEnd).length;

    _isCommandExecuting = true;
    try {
      controller.value = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      _addBlock(blockIndex + 1, text: after);
      _clearAppSelectionAfterTextInput(controller);
      if (blockIndex + 1 < _controllers.length) {
        _lastFocusedController = _controllers[blockIndex + 1];
        _controllers[blockIndex + 1].selection =
            TextSelection.collapsed(offset: newCaretOffset);
      }
    } finally {
      _isCommandExecuting = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && blockIndex + 1 < _focusNodes.length) {
        _lastFocusedController = _controllers[blockIndex + 1];
        _focusNodes[blockIndex + 1].requestFocus();
        _controllers[blockIndex + 1].selection =
            TextSelection.collapsed(offset: newCaretOffset);
      }
    });
  }

  bool _isVisuallyEmptyBlock(String text) {
    return MarkupDecorationParser.visibleText(text).trim().isEmpty;
  }

  bool _isCaretAtVisibleBlockStart(MarkupController controller) {
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    final rawOffset = selection.extentOffset.clamp(0, controller.text.length);
    return MarkupDecorationParser.rawToVisibleOffset(
          controller.text,
          rawOffset,
        ) ==
        0;
  }

  void _deletePreviousEmptyBlockFromCaret(int currentIndex) {
    if (currentIndex <= 0 || currentIndex >= _controllers.length) return;
    final controller = _controllers[currentIndex];
    _setEditorState(() {
      _controllers.removeAt(currentIndex - 1).dispose();
      _focusNodes.removeAt(currentIndex - 1).dispose();
      _blockKeys.removeAt(currentIndex - 1);
    });
    final newIndex = (currentIndex - 1).clamp(0, _controllers.length - 1);
    _lastFocusedController = controller;
    controller.selection = const TextSelection.collapsed(offset: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || newIndex >= _focusNodes.length) return;
      _focusNodes[newIndex].requestFocus();
      controller.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _joinCurrentBlockIntoPrevious(int currentIndex) {
    if (currentIndex <= 0 || currentIndex >= _controllers.length) return;
    final previous = _controllers[currentIndex - 1];
    final current = _controllers[currentIndex];
    final previousText = previous.text;
    final activePrefix =
        MarkupController.openTagsAt(previousText, previousText.length);
    final currentText = MarkupController.stripRedundantLeadingOpenTagContext(
      current.text,
      activePrefix,
    );
    final caretOffset = previousText.length;

    _isCommandExecuting = true;
    try {
      _setEditorState(() {
        previous.value = TextEditingValue(
          text: previousText + currentText,
          selection: TextSelection.collapsed(offset: caretOffset),
        );
        _controllers.removeAt(currentIndex).dispose();
        _focusNodes.removeAt(currentIndex).dispose();
        _blockKeys.removeAt(currentIndex);
      });
      _clearAppSelectionAfterTextInput(previous);
      _lastFocusedController = previous;
      previous.selection = TextSelection.collapsed(offset: caretOffset);
    } finally {
      _isCommandExecuting = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || currentIndex - 1 >= _focusNodes.length) return;
      _lastFocusedController = previous;
      _focusNodes[currentIndex - 1].requestFocus();
      previous.selection = TextSelection.collapsed(offset: caretOffset);
    });
  }

  void _removeBlock(int index) {
    if (_controllers.length <= 1) return;
    _setEditorState(() {
      _controllers[index].dispose();
      _focusNodes[index].dispose();
      _controllers.removeAt(index);
      _focusNodes.removeAt(index);
      _blockKeys.removeAt(index);
    });
  }

  void _loadText(String text) {
    _isLoading = true;
    try {
      _setEditorState(() {
        _clearControllers();
        _isBulkLoadingBlocks = true;
        try {
          final paragraphs = text.split('\n');
          for (int i = 0; i < paragraphs.length; i++) {
            _addBlock(i, text: paragraphs[i]);
          }
          if (_controllers.isEmpty) _addBlock(0);
        } finally {
          _isBulkLoadingBlocks = false;
        }
      });
      if (text.isEmpty && _focusNodes.isNotEmpty) {
        Future.delayed(Duration.zero, () => _focusNodes.first.requestFocus());
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _isLoading = false;
      });
    }
    // Sync toolbar state after load. Non-empty blocks don't auto-request focus,
    // so _onSelectionChanged never fires - cursorStyleProvider stays at its
    // default 'left'. Point lastFocusedController at the first block so
    // _detectAlignAtCursor reads the right text, then run detection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controllers.isNotEmpty) _lastFocusedController = _controllers.first;
      _onSelectionChanged();
    });
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final controller = _activeController;
    if (controller != null) {
      if (_editorToolbarFocusGuard && !_isCommandExecuting) {
        return;
      }
      // v3.9.5.1: Synchronize selection with status broadcast logic
      // Only reset Global Selection if a manual PARTIAL selection occurs.
      // If the selection is collapsed (cursor) or spans the whole block, keep the flag.
      if (_isGlobalSelection && !_isCommandExecuting) {
        // Keep global selection only if the active block is still fully selected
        // (i.e. the notification came from our own _selectAllBlocks).
        // Any other selection state (collapsed tap, partial drag) clears it.
        // Guard: if the overlay has active handles (e.g. alignment was just applied
        // or drag is in progress), do NOT clear - focus events fire before
        // _isCommandExecuting is set and would prematurely destroy the selection.
        if (_overlayKey.currentState?.hasSelection ?? false) return;
        final globalMarkersStillFull = _controllers.isNotEmpty &&
            _controllers.every((c) {
              if (c.text.isEmpty) return true;
              if (c.isGlobalSelected) return true;
              final external = c.externalSelection;
              return external != null &&
                  external.isValid &&
                  external.start <= 0 &&
                  external.end >= c.text.length;
            });
        if (globalMarkersStillFull) return;
        final textLen = controller.text.length;
        final isFullBlock = !controller.selection.isCollapsed &&
            controller.selection.start == 0 &&
            controller.selection.end == textLen;
        if (!isFullBlock) {
          _clearGlobalSelection();
        }
      }

      // Defer provider update to avoid "modified during build" errors
      // when _onSelectionChanged is triggered from controller listeners
      // during setState callbacks.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final settings = ref.read(settingsProvider);
        final styles = CursorStyle(
          isBold: _detectStyleAtCursor('**', '**'),
          isItalic: _detectStyleAtCursor('[i]', '[/i]'),
          isUnderline: _detectStyleAtCursor('[u]', '[/u]'),
          fontSize: _detectIntAtCursor('size=', settings.fontSize.toInt()),
          fontFamily: _detectStringAtCursor('font=', 'Inter'),
          textAlign: _detectAlignAtCursor(),
          textDirection: _detectDirectionAtCursor(),
          textColor: _detectColorAtCursor(textColor: true),
          highlightColor: _detectColorAtCursor(textColor: false),
        );
        ref.read(cursorStyleProvider.notifier).state = styles;
      });
      if (controller.selection.isValid && !controller.selection.isCollapsed) {
        _scheduleHighlightTrace('native-selection');
      }
    }
  }

  void _onBlockChanged() {
    if (_isCleaning || _isCommandExecuting) return;
    _saveHistory(description: 'Edit Text', debounce: true);
    _scheduleRecentUpdate();
  }

  void _clearAppSelectionAfterTextInput(MarkupController editedController) {
    _overlayKey.currentState?.clearSelection();
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.externalVisibleSelection = null;
      if (!identical(c, editedController) &&
          c.selection.isValid &&
          !c.selection.isCollapsed) {
        final collapseAt = c.selection.extentOffset.clamp(0, c.text.length);
        c.selection = TextSelection.collapsed(offset: collapseAt);
      }
      c.refresh();
    }
    _lastFocusedController = editedController;
  }
}

class _EnterSelectionRange {
  final int blockIndex;
  final TextSelection selection;

  const _EnterSelectionRange(this.blockIndex, this.selection);
}
