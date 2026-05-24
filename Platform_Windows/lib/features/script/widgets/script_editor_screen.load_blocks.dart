part of 'script_editor_screen.dart';

extension _ScriptEditorLoadBlockParts on _ScriptEditorScreenState {
  Future<void> _runPendingFileLoad(File file) async {
    try {
      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
      final result = await ref.read(scriptProvider.notifier).parseFile(file);
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
        } catch (_) {}
      }

      String finalContent = content;
      String finalType = title.split('.').last.toUpperCase();
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
        } catch (_) {}
      } else {
        _saveHistory(description: 'Import');
      }
      _forceRecentUpdate();
    } finally {
      if (mounted) _setEditorState(() => _isPendingLoad = false);
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_typingCharCount > 0 || (_typingBulkTimer?.isActive ?? false)) {
        _scheduleRecentUpdate();
        return;
      }
      final text = _getRefinedFullTextWithoutBookmarkSigns();
      if (text.isEmpty && _currentTitle == 'New Project') return;
      try {
        unawaited(_forceRecentUpdate());
      } catch (_) {}
    });
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
          final text = controller.text;
          final sel = controller.selection;
          if (sel.isValid) {
            final before = text.substring(0, sel.start);
            final after = text.substring(sel.start);
            controller.text = before;
            _addBlock(idx + 1, text: after);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && idx + 1 < _focusNodes.length) {
                _focusNodes[idx + 1].requestFocus();
                _controllers[idx + 1].selection =
                    const TextSelection.collapsed(offset: 0);
              }
            });
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
        return KeyEventResult.ignored;
      });

      node.addListener(() {
        if (node.hasFocus) {
          _lastFocusedController = controller;
          // Restore native-selection rendering on focus regain by clearing
          // any externalSelection sentinel set during focus loss.
          if (controller.externalSelection != null &&
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
        lastText = controller.text;
        _isDirty = true;
        _verticalArrowPreferredX = null;
        // v4.1.2: When the user edits text (not inside a style command), clear
        // any pinned externalSelection so stale amber doesn't linger after typing.
        if (!_isCommandExecuting && controller.externalSelection != null) {
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

  void _scheduleRecentUpdate({
    Duration delay = const Duration(seconds: 4),
  }) {
    _recentTimer?.cancel();
    _recentTimer = Timer(delay, () {
      if (mounted) unawaited(_forceRecentUpdate());
    });
  }

  Future<void> _forceRecentUpdate() async {
    _recentTimer?.cancel();
    if (_recentPersistRunning) {
      _recentPersistQueued = true;
      return;
    }
    final text = _getRefinedFullTextWithoutBookmarkSigns();
    if (text.trim().isEmpty) return;
    final settings = ref.read(settingsProvider);
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    final fingerprint = _recentPersistenceFingerprint(
      text: text,
      historyJson: historyJson,
      settings: settings,
    );
    if (fingerprint == _lastRecentPersistFingerprint) return;
    _recentPersistRunning = true;
    try {
      await ref.read(settingsProvider.notifier).saveScript(
            text,
            title: _currentTitle,
            type: _sourceType,
            historyIndex: _historyIndex,
            sessionId: _currentSessionId,
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
      _lastRecentPersistFingerprint = fingerprint;
      // Keep scriptProvider.state in sync so that a new ScriptEditorScreen
      // (created on re-entry after navigating away) reads the correct
      // historyIndex and historyJson rather than stale startup values.
      if (mounted) {
        ref.read(scriptProvider.notifier).updateHistory(
              _historyIndex,
              historyJson,
            );
      }
    } finally {
      _recentPersistRunning = false;
      if (_recentPersistQueued && mounted) {
        _recentPersistQueued = false;
        _scheduleRecentUpdate(delay: const Duration(seconds: 2));
      }
    }
  }

  void _rememberCurrentRecentFingerprint() {
    if (_controllers.isEmpty) return;
    final text = _getRefinedFullTextWithoutBookmarkSigns();
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    _lastRecentPersistFingerprint = _recentPersistenceFingerprint(
      text: text,
      historyJson: historyJson,
      settings: ref.read(settingsProvider),
    );
  }

  String _recentPersistenceFingerprint({
    required String text,
    required String historyJson,
    required AppSettings settings,
  }) {
    return [
      _currentTitle,
      _sourceType,
      _currentSessionId ?? '',
      _historyIndex.toString(),
      text.length.toString(),
      text.hashCode.toString(),
      historyJson.length.toString(),
      historyJson.hashCode.toString(),
      settings.fontSize.toStringAsFixed(3),
      settings.fontFamily,
      settings.lineSpacing.toStringAsFixed(3),
      settings.letterSpacing.toStringAsFixed(3),
      settings.wordSpacing.toStringAsFixed(3),
      settings.textAlign,
      settings.scriptBgColor.toString(),
      settings.currentWordColor.toString(),
      settings.futureWordColor.toString(),
    ].join('|');
  }

  void _onBlockChanged() {
    if (_isCleaning || _isCommandExecuting) return;
    _saveHistory(description: 'Edit Text', debounce: true);
    _scheduleRecentUpdate();
  }

  _VerticalLayoutInfo _getVerticalLayout(
    int index, {
    TextSelection? selection,
  }) {
    final controller = _controllers[index];
    final settings = ref.read(settingsProvider);
    final isRtl = _editorBlockResolvedRtl(index);
    final textAlign = EditorTextGeometryService.resolveTextAlign(
      controller.text,
      isRtl: isRtl,
    );

    // 2. Build style
    final style = TextStyle(
      color: Colors.white,
      fontSize: settings.fontSize,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
    );
    final maxFontSize = EditorTextGeometryService.maxFontSize(
      controller.text,
      settings.fontSize,
    );
    final strutStyle = StrutStyle(
      fontSize: maxFontSize,
      height: settings.lineSpacing,
      forceStrutHeight: true,
    );

    // 3. Get width
    double width = 800; // fallback
    final context = _blockKeys[index].currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        width = box.size.width -
            30; // Accounting for Padding(left: 30) in _EditorBlock
      }
    }

    // 4. Paint
    final span = controller.text.isEmpty
        ? TextSpan(text: ' ', style: style)
        : controller.buildTextSpan(
            context: context ?? this.context,
            style: style,
            withComposing: false,
          );
    final painter = TextPainter(
      text: span,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: textAlign,
      strutStyle: strutStyle,
    );
    painter.layout(maxWidth: width > 0 ? width : 800);

    return _VerticalLayoutInfo(
      painter,
      selection ?? controller.selection,
      isRtl: isRtl,
      layoutWidth: width > 0 ? width : 800,
    );
  }
}
