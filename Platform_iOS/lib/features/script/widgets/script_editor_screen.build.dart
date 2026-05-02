part of 'script_editor_screen.dart';

extension _ScriptEditorBuildParts on _ScriptEditorScreenState {
  Widget _buildScriptEditorScreen(BuildContext context) {
    // v3.9.5.71: Style History Sentry
    // Detects when the user changes global formatting and triggers an Undo point + Auto-save
    ref.listen(settingsProvider, (previous, next) {
      if (_isCommandExecuting || previous == null) return;

      final hasStyleChange = previous.fontSize != next.fontSize ||
          previous.fontFamily != next.fontFamily ||
          previous.lineSpacing != next.lineSpacing ||
          previous.letterSpacing != next.letterSpacing ||
          previous.wordSpacing != next.wordSpacing ||
          previous.textAlign != next.textAlign ||
          previous.scriptBgColor != next.scriptBgColor ||
          previous.currentWordColor != next.currentWordColor ||
          previous.futureWordColor != next.futureWordColor;

      if (hasStyleChange) {
        _saveHistory(description: 'Update Styling', debounce: true);
      }
    });

    final settings = ref.watch(settingsProvider);
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          toolbarHeight: 110,
          backgroundColor: const Color(0xFF0A0A0A),
          automaticallyImplyLeading: false,
          title: ProjectActionsSuite(
            title: _currentTitle,
            onBack: () => Navigator.pop(context),
            onPresent: _startPresenting,
            onClear: _clearScript,
            onSave: _saveScript,
            onImport: _importFile,
            onRename: _showRenameDialog,
            onSearch: () => unawaited(_showEditorSearchDialog()),
          ),
        ),
        bottomNavigationBar:
            _buildBottomActions(keyboardVisible: keyboardVisible),
        body: GestureDetector(
          onTap: () {
            _dismissEditorSelectionForUserNavigation('background-tap');
            FocusScope.of(context).unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Shortcuts(
                shortcuts: {
                  LogicalKeySet(
                          LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
                      const _SelectAllIntent(),
                  LogicalKeySet(
                          LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA):
                      const _SelectAllIntent(),
                  LogicalKeySet(
                          LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
                      const _CopyIntent(),
                  LogicalKeySet(
                          LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC):
                      const _CopyIntent(),
                  LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.shift,
                      LogicalKeyboardKey.keyF): const _SearchIntent(),
                  LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.shift,
                      LogicalKeyboardKey.keyF): const _SearchIntent(),
                },
                child: Actions(
                  actions: {
                    _SelectAllIntent:
                        CallbackAction<_SelectAllIntent>(onInvoke: (intent) {
                      _selectAllBlocks();
                      return null;
                    }),
                    _CopyIntent:
                        CallbackAction<_CopyIntent>(onInvoke: (intent) {
                      _onCopyClean();
                      return null;
                    }),
                    _SearchIntent:
                        CallbackAction<_SearchIntent>(onInvoke: (intent) {
                      unawaited(_showEditorSearchDialog());
                      return null;
                    }),
                  },
                  child: Column(
                    children: [
                      FormattingToolbarMVP(
                        onBold: _onBold,
                        onUnderline: _onUnderline,
                        onItalic: _onItalic,
                        onClear: () {
                          setState(() => _isCommandExecuting = true);
                          final tagPattern = RegExp(
                              r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
                          if (_isGlobalSelection ||
                              (_overlayKey.currentState?.hasSelection ??
                                  false)) {
                            // Global: strip ALL tags from every block
                            for (final c in _controllers) {
                              c.text = c.text.replaceAll(tagPattern, '');
                            }
                          } else {
                            final c = _activeController;
                            if (c != null) {
                              final text = c.text;
                              final sel = c.selection;
                              if (sel.isValid && !sel.isCollapsed) {
                                // Selection: strip tags inside the selected range, then
                                // split any enclosing tags so surrounding text keeps style.
                                final before = text.substring(0, sel.start);
                                final selected =
                                    text.substring(sel.start, sel.end);
                                final after = text.substring(sel.end);
                                final cleaned =
                                    selected.replaceAll(tagPattern, '');
                                final intermediate = before + cleaned + after;
                                final cleanEnd = sel.start + cleaned.length;
                                final result = _splitAllEnclosingStyles(
                                    intermediate,
                                    sel.start,
                                    cleanEnd,
                                    tagPattern);
                                c.value = TextEditingValue(
                                  text: result,
                                  selection: TextSelection.collapsed(
                                      offset: sel.start),
                                );
                              } else if (sel.isValid && sel.isCollapsed) {
                                // Check if cursor is at end of line/paragraph → Baseline Mode: clear whole script
                                final plainText =
                                    text.replaceAll(tagPattern, '');
                                final cursorInPlain =
                                    sel.start >= text.length ||
                                        text
                                            .substring(sel.start)
                                            .replaceAll(tagPattern, '')
                                            .isEmpty;
                                if (cursorInPlain) {
                                  // Baseline Mode: clear ALL tags from ALL blocks
                                  for (final ctrl in _controllers) {
                                    ctrl.text =
                                        ctrl.text.replaceAll(tagPattern, '');
                                  }
                                } else {
                                  // Word Mode: clear styles for the word at cursor
                                  _clearStyleAtCursor(c, sel.start);
                                }
                              }
                            }
                          }
                          _isDirty = false;
                          setState(() => _isCommandExecuting = false);
                          _saveHistory(description: 'Clear Format');
                        },
                        onFontSize: onFontSize,
                        onAlign: onAlign,
                        onDirection: onDirection,
                        onTextColor: onTextColorSelected,
                        onBgColor: onBgColorSelected,
                        onFontFamily: onFontFamily,
                        onBgColorChange: handleBgColorChange,
                        onAddBookmark: () => unawaited(_addEditorBookmark()),
                        onRemoveBookmark: () =>
                            unawaited(_deleteEditorBookmarkAtCurrentPosition()),
                        onPreviousBookmark: () =>
                            unawaited(_jumpEditorBookmark(-1)),
                        onNextBookmark: () => unawaited(_jumpEditorBookmark(1)),
                        lastTextColor: _lastChosenTextColor,
                        lastHighlightColor: _lastChosenHighlightColor,
                        onUndo: _undo,
                        onRedo: _redo,
                        canUndo: _historyIndex > 0,
                        canRedo: _historyIndex < _history.length - 1,
                        history: _history,
                        historyIndex: _historyIndex,
                        onHistorySelected: (idx) => _jumpToHistory(idx),
                        activeSuite: _activeSuite,
                        onSuiteToggle: (suite) {
                          // Closing = explicitly closing (none), toggling same suite off, or switching suites
                          final willClose = suite == EditorSuite.none ||
                              suite == _activeSuite;
                          final willSwitch = suite != _activeSuite &&
                              _activeSuite != EditorSuite.none;
                          _suiteAutoSaveTimer?.cancel();
                          if ((willClose || willSwitch) && _isSuiteDirty) {
                            _commitHistory(_suiteSection ??
                                '${_activeSuite.name.toUpperCase()} Session');
                            _isSuiteDirty = false;
                            _suiteSection = null;
                          }
                          setState(() {
                            _activeSuite = (_activeSuite == suite)
                                ? EditorSuite.none
                                : suite;
                          });
                          if (_activeSuite != EditorSuite.none) {
                            _suiteSection = null;
                          }
                        },
                        onLayoutInteraction: (section) {
                          _trackSuiteSection(section);
                          setState(() => _isSuiteDirty = true);
                        },
                      ),
                      Expanded(
                        child: Container(
                          color: Color(settings.scriptBgColor),
                          child: GlobalSelectionOverlay(
                            key: _overlayKey,
                            controllers: _controllers,
                            blockKeys: _blockKeys,
                            onSelectionChanged: () => setState(() {
                              final overlayState = _overlayKey.currentState;
                              _isGlobalSelection = _controllers.isNotEmpty &&
                                  _controllers.every((c) => c.isGlobalSelected);
                              _syncSelectionSnapshotFromOverlay(
                                'overlay-selection',
                                allowShrink:
                                    overlayState?.isRefinedSelection ?? false,
                              );
                            }),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (_) {
                                _overlayKey.currentState?.refreshPositions();
                                return false;
                              },
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 24, 24, 250),
                                itemCount: _controllers.length,
                                itemBuilder: (context, index) {
                                  final overlayHasSelection =
                                      _overlayKey.currentState?.hasSelection ??
                                          false;
                                  return _EditorBlock(
                                    key: _blockKeys[index],
                                    controller: _controllers[index],
                                    focusNode: _focusNodes[index],
                                    settings: settings,
                                    isGlobalSelected: _isGlobalSelection,
                                    hasOverlaySelection: overlayHasSelection,
                                    onSubmitted: () => _addBlock(index + 1),
                                    onTap: () {
                                      _dismissEditorSelectionForUserNavigation(
                                          'block-tap');
                                    },
                                    onSelectAll: _selectAllBlocks,
                                    onCopy: _onCopyClean,
                                    onCut: _onCutClean,
                                    onExtendSelection: () =>
                                        _extendNativeSelectionToOverlay(index),
                                    onPaste: _hasPasteableBlockClipboard
                                        ? _pasteFromGlobalClipboard
                                        : null,
                                    hasBookmark:
                                        _hasBookmarkInEditorBlock(index),
                                    onBookmarkTap: () => unawaited(
                                      _deleteEditorBookmarksForBlock(index),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isPendingLoad)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF0A0A0A),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFFBF00)),
                            ),
                          ),
                          SizedBox(height: 18),
                          Text('Loading script…',
                              style: TextStyle(
                                  color: Color(0xFFFFBF00),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (settings.debugMode)
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: IgnorePointer(child: _buildDebugSentry()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugSentry() {
    final activeIdx = _focusNodes.indexWhere((n) => n.hasFocus);
    final sel = _activeController?.selection;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚙️ EDITOR SENTRY',
              style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text('Blocks: ${_controllers.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Active Block: ${activeIdx != -1 ? activeIdx : "None"}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          if (sel != null)
            Text('Cursor: [${sel.baseOffset}, ${sel.extentOffset}]',
                style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Global Selection: $_isGlobalSelection',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Clipboard: $_selectionClipboardDebug',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('History States: ${_history.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}
