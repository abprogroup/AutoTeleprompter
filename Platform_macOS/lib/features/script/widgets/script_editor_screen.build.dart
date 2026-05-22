part of 'script_editor_screen.dart';

extension _ScriptEditorScreenBuildParts on _ScriptEditorScreenState {
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
        Container(
          color: Colors.black,
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _startPresenting,
                  icon: const Icon(Icons.play_circle_filled_rounded, size: 24),
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
      ],
    );
  }

  Widget _buildScriptEditorScreen(BuildContext context) {
    // v3.9.5.71: Style History Sentry
    // Detects when the user changes global formatting and triggers an Undo point.
    // v4.1.4: Uses a time-only 1.5s debounce timer instead of char-count bulk,
    // so rapid slider drags (line spacing, etc.) only ever produce ONE history entry.
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
        _settingsDebounceTimer?.cancel();
        _settingsDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) _commitHistory('Update Styling');
        });
      }
    });

    final settings = ref.watch(settingsProvider);
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_isPendingLoad) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFBF00)),
                ),
              ),
              SizedBox(height: 18),
              Text(
                'Loading script...',
                style: TextStyle(
                  color: Color(0xFFFFBF00),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
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
          onSearch: _showEditorSearchDialog,
          onAddBookmark: _addEditorBookmark,
          onRemoveBookmark: () =>
              unawaited(_deleteEditorBookmarkAtCurrentPosition()),
          onPreviousBookmark: () => _jumpEditorBookmark(-1),
          onNextBookmark: () => _jumpEditorBookmark(1),
        ),
      ),
      bottomNavigationBar:
          _buildBottomActions(keyboardVisible: keyboardVisible),
      body: MouseRegion(
        onExit: (event) {
          final overlay = _overlayKey.currentState;
          overlay?.handlePointerExitedEditor(event.position);
          overlay?.handleBodyPointerExitedEditor(event.position);
        },
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kPrimaryButton) {
              final overlay = _overlayKey.currentState;
              if (overlay?.isPointInsideHandle(event.position) ?? false) {
                return;
              }
              overlay?.startDragging(event.position);
            }
          },
          onPointerMove: (event) {
            if (event.buttons == kPrimaryButton) {
              final overlay = _overlayKey.currentState;
              if (overlay?.isHandleInteractionActive ?? false) {
                overlay?.updateActiveHandlePointer(event.position);
                return;
              }
              overlay?.updateDragging(event.position);
            }
          },
          onPointerUp: (_) {
            _overlayKey.currentState?.endDragging();
            // After any gesture ends, promote a native single-block partial
            // selection to overlay handles. Doing this on pointer-up (not in the
            // controller listener) prevents the "one letter selected" bug: during
            // a drag the controller fires continuously and the overlay would freeze
            // at the first-delta selection once overlayActive becomes true.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _promoteNativeSelectionToOverlay();
            });
          },
          onPointerCancel: (_) {
            _overlayKey.currentState?.endDragging();
          },
          behavior: HitTestBehavior.translucent,
          // Screen-level Focus shell only. HardwareKeyboard owns arrow routing
          // so a single physical keypress cannot be processed twice.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, __) => KeyEventResult.ignored,
            child: Stack(
              children: [
                Shortcuts(
                  shortcuts: {
                    LogicalKeySet(LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyA): const _SelectAllIntent(),
                    LogicalKeySet(
                            LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA):
                        const _SelectAllIntent(),
                    LogicalKeySet(LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyC): const _CopyIntent(),
                    LogicalKeySet(
                            LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC):
                        const _CopyIntent(),
                    LogicalKeySet(LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyX): const _CutIntent(),
                    LogicalKeySet(
                            LogicalKeyboardKey.meta, LogicalKeyboardKey.keyX):
                        const _CutIntent(),
                    LogicalKeySet(LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyV): const _PasteIntent(),
                    LogicalKeySet(
                            LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV):
                        const _PasteIntent(),
                    LogicalKeySet(
                        LogicalKeyboardKey.control,
                        LogicalKeyboardKey.shift,
                        LogicalKeyboardKey.keyF): const _SearchIntent(),
                    LogicalKeySet(
                        LogicalKeyboardKey.meta,
                        LogicalKeyboardKey.shift,
                        LogicalKeyboardKey.keyF): const _SearchIntent(),
                    LogicalKeySet(LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyZ): const _UndoIntent(),
                    LogicalKeySet(
                            LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
                        const _UndoIntent(),
                    LogicalKeySet(LogicalKeyboardKey.control,
                        LogicalKeyboardKey.keyY): const _RedoIntent(),
                    LogicalKeySet(
                            LogicalKeyboardKey.meta, LogicalKeyboardKey.keyY):
                        const _RedoIntent(),
                    LogicalKeySet(
                        LogicalKeyboardKey.control,
                        LogicalKeyboardKey.shift,
                        LogicalKeyboardKey.keyZ): const _RedoIntent(),
                    LogicalKeySet(
                        LogicalKeyboardKey.meta,
                        LogicalKeyboardKey.shift,
                        LogicalKeyboardKey.keyZ): const _RedoIntent(),
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
                      _CutIntent:
                          CallbackAction<_CutIntent>(onInvoke: (intent) {
                        _onCut();
                        return null;
                      }),
                      _PasteIntent:
                          CallbackAction<_PasteIntent>(onInvoke: (intent) {
                        _onPaste();
                        return null;
                      }),
                      _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
                        _undo();
                        return null;
                      }),
                      _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
                        _redo();
                        return null;
                      }),
                      _SearchIntent:
                          CallbackAction<_SearchIntent>(onInvoke: (intent) {
                        _showEditorSearchDialog();
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
                                  // Check if cursor is at end of line/paragraph.
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
                            // v4.1.4: After stripping alignment tags the text layout shifts,
                            // but cursorStyleProvider and the overlay handles still hold the
                            // old alignment. Force re-detection + handle refresh post-frame.
                            _onSelectionChanged();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              final c = _activeController;
                              if (c != null) {
                                final hasAlign = RegExp(
                                        r'\[(?:align=)?(?:center|left|right)\]')
                                    .hasMatch(c.text);
                                if (!hasAlign) {
                                  ref.read(cursorStyleProvider.notifier).state =
                                      ref
                                          .read(cursorStyleProvider)
                                          .copyWith(textAlign: 'left');
                                }
                              }
                              _overlayKey.currentState?.refreshPositions();
                            });
                          },
                          onFontSize: onFontSize,
                          onAlign: onAlign,
                          onDirection: onDirection,
                          onTextColor: onTextColorSelected,
                          onBgColor: onBgColorSelected,
                          onFontFamily: onFontFamily,
                          onBgColorChange: handleBgColorChange,
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
                              scrollController: _editorScrollController,
                              onSelectionChanged: () => setState(() {
                                _isGlobalSelection = _controllers.isNotEmpty &&
                                    _controllers
                                        .every((c) => c.isGlobalSelected);
                              }),
                              child: SingleChildScrollView(
                                controller: _editorScrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(24, 24, 24, 250),
                                child: Column(
                                  children: List.generate(
                                    _controllers.length,
                                    (index) => Listener(
                                      onPointerDown: (event) {
                                        _verticalArrowPreferredX = null;
                                        if (_isGlobalSelection ||
                                            _controllers.any(
                                                (c) => c.isGlobalSelected) ||
                                            (_overlayKey.currentState
                                                    ?.hasSelection ??
                                                false) ||
                                            _controllers.any((c) =>
                                                c.externalSelection != null)) {
                                          _clearGlobalSelection();
                                        }
                                      },
                                      child: _EditorBlock(
                                        key: _blockKeys[index],
                                        controller: _controllers[index],
                                        focusNode: _focusNodes[index],
                                        settings: settings,
                                        isGlobalSelected: _isGlobalSelection,
                                        inheritedRtl:
                                            _editorBlockResolvedRtl(index),
                                        onSubmitted: () => _addBlock(index + 1),
                                        onTap: () {
                                          // Secondary safety, though Listener should handle it
                                          if (_isGlobalSelection) {
                                            _clearGlobalSelection();
                                          }
                                        },
                                        onSelectAll: _selectAllBlocks,
                                        onCopy: _onCopyClean,
                                        onCut: _onCut,
                                        onPaste: _onPaste,
                                        onUndo: _undo,
                                        onRedo: _redo,
                                        onSearch: _showEditorSearchDialog,
                                        hasBookmark:
                                            _hasBookmarkInEditorBlock(index),
                                        onBookmarkTap: () =>
                                            _deleteEditorBookmarksForBlock(
                                                index),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: _buildEditorSearchToolbar(),
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
      ),
    );
  }

  // Screen-level arrow-key cross-block navigation.
  // HardwareKeyboard handler: fires BEFORE Flutter's focus system, so key-repeat
  // events are never dropped during the async focus-transfer window when crossing
  // a block boundary. Returns true only at boundaries; in-block movement is passed
  // through (returns false) so EditableText's default cursor handling stays intact.
}
