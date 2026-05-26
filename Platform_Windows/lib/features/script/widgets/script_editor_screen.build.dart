part of 'script_editor_screen.dart';

extension _ScriptEditorBuildParts on _ScriptEditorScreenState {
  Widget _buildEditorScreen(BuildContext context) {
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
          onSettings: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppSettingsScreen(
                  initialTab: AppSettingsTab.editor,
                ),
              ),
            );
          },
          onRecord: null,
          onAddBookmark: _addEditorBookmark,
          onRemoveBookmark: () =>
              unawaited(_deleteEditorBookmarkAtCurrentPosition()),
          onPreviousBookmark: () => _jumpEditorBookmark(-1),
          onNextBookmark: () => _jumpEditorBookmark(1),
        ),
      ),
      bottomNavigationBar: _buildBottomActions(
        keyboardVisible: keyboardVisible,
      ),
      body: MouseRegion(
        onExit: (event) {
          final overlay = _overlayKey.currentState;
          overlay?.handlePointerExitedEditor(event.position);
          overlay?.handleBodyPointerExitedEditor(event.position);
        },
        child: Listener(
          onPointerDown: (event) {
            if (_isPointInsideAppSelectionToolbar(event.position)) {
              return;
            }
            if (event.buttons == kPrimaryButton) {
              final overlay = _overlayKey.currentState;
              if (overlay?.isPointInsideHandle(event.position) ?? false) {
                return;
              }
              final replacingAppSelection =
                  _hasAppSelectionForPointerReplacement();
              if (replacingAppSelection) {
                _clearAppSelectionForPointerReplacement(
                  reason: 'pointerDownReplaceAppSelection',
                );
              }
              final startedInsideEditable =
                  overlay?.startDragging(event.position) ?? false;
              if (!startedInsideEditable) return;
              _registerEditorPrimaryClick(event);
            }
          },
          onPointerMove: (event) {
            if (_isPointInsideAppSelectionToolbar(event.position)) return;
            if (event.buttons == kPrimaryButton) {
              final overlay = _overlayKey.currentState;
              if (overlay?.isHandleInteractionActive ?? false) {
                overlay?.updateActiveHandlePointer(event.position);
                return;
              }
              overlay?.updateDragging(event.position);
            }
          },
          onPointerUp: (event) {
            if (_isPointInsideAppSelectionToolbar(event.position)) {
              return;
            }
            final overlayOwnedDrag =
                _overlayKey.currentState?.endDragging() ?? false;
            final gestureKind =
                _pendingNativeSelectionGestureKind ?? 'nativeDrag';
            _pendingNativeSelectionGestureKind = null;
            // After any gesture ends, promote a native single-block partial
            // selection to overlay handles. Doing this on pointer-up (not in the
            // controller listener) prevents the "one letter selected" bug: during
            // a drag the controller fires continuously and the overlay would freeze
            // at the first-delta selection once overlayActive becomes true.
            if (!overlayOwnedDrag) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _promoteNativeSelectionToOverlay(
                    gestureKind: gestureKind,
                  );
                }
              });
            }
          },
          onPointerCancel: (_) {
            _pendingNativeSelectionGestureKind = null;
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
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyA,
                    ): const _SelectAllIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyA,
                    ): const _SelectAllIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyC,
                    ): const _CopyIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyC,
                    ): const _CopyIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyX,
                    ): const _CutIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyX,
                    ): const _CutIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyV,
                    ): const _PasteIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyV,
                    ): const _PasteIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.shift,
                      LogicalKeyboardKey.keyF,
                    ): const _SearchIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.shift,
                      LogicalKeyboardKey.keyF,
                    ): const _SearchIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyZ,
                    ): const _UndoIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyZ,
                    ): const _UndoIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyY,
                    ): const _RedoIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.keyY,
                    ): const _RedoIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.shift,
                      LogicalKeyboardKey.keyZ,
                    ): const _RedoIntent(),
                    LogicalKeySet(
                      LogicalKeyboardKey.meta,
                      LogicalKeyboardKey.shift,
                      LogicalKeyboardKey.keyZ,
                    ): const _RedoIntent(),
                  },
                  child: Actions(
                    actions: {
                      _SelectAllIntent: CallbackAction<_SelectAllIntent>(
                        onInvoke: (intent) {
                          _selectAllBlocks();
                          return null;
                        },
                      ),
                      _CopyIntent: CallbackAction<_CopyIntent>(
                        onInvoke: (intent) {
                          _onCopyClean();
                          return null;
                        },
                      ),
                      _CutIntent: CallbackAction<_CutIntent>(
                        onInvoke: (intent) {
                          _onCut();
                          return null;
                        },
                      ),
                      _PasteIntent: CallbackAction<_PasteIntent>(
                        onInvoke: (intent) {
                          _onPaste();
                          return null;
                        },
                      ),
                      _UndoIntent: CallbackAction<_UndoIntent>(
                        onInvoke: (_) {
                          _undo();
                          return null;
                        },
                      ),
                      _RedoIntent: CallbackAction<_RedoIntent>(
                        onInvoke: (_) {
                          _redo();
                          return null;
                        },
                      ),
                      _SearchIntent: CallbackAction<_SearchIntent>(
                        onInvoke: (intent) {
                          _showEditorSearchDialog();
                          return null;
                        },
                      ),
                    },
                    child: Column(
                      children: [
                        FormattingToolbarMVP(
                          onBold: _onBold,
                          onUnderline: _onUnderline,
                          onItalic: _onItalic,
                          onClear: _onClearFormat,
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
                              _commitHistory(
                                _suiteSection ??
                                    '${_activeSuite.name.toUpperCase()} Session',
                              );
                              _isSuiteDirty = false;
                              _suiteSection = null;
                            }
                            _setEditorState(() {
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
                            _setEditorState(() => _isSuiteDirty = true);
                          },
                        ),
                        Expanded(
                          child: RepaintBoundary(
                            key: _editorArrowTraceBoundaryKey,
                            child: Container(
                              color: Color(settings.scriptBgColor),
                              child: GlobalSelectionOverlay(
                                key: _overlayKey,
                                controllers: _controllers,
                                blockKeys: _blockKeys,
                                settings: settings,
                                scrollController: _editorScrollController,
                                onSelectionDebugEvent: (reason) {
                                  _recordSelectionTrace(reason);
                                },
                                onSelectionChanged: () {
                                  _setEditorState(() {
                                    _isGlobalSelection =
                                        _controllers.isNotEmpty &&
                                            _controllers.every(
                                              (c) => c.isGlobalSelected,
                                            );
                                  });
                                  _scheduleHighlightTrace(
                                    'overlay-selection',
                                  );
                                },
                                child: ListView.builder(
                                  controller: _editorScrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    24,
                                    24,
                                    250,
                                  ),
                                  itemCount: _controllers.length,
                                  cacheExtent: 900,
                                  itemBuilder: (context, index) => Listener(
                                    onPointerDown: (event) {
                                      _verticalArrowPreferredX = null;
                                    },
                                    child: _EditorBlock(
                                      key: _blockKeys[index],
                                      controller: _controllers[index],
                                      focusNode: _focusNodes[index],
                                      settings: settings,
                                      isGlobalSelected: _isGlobalSelection,
                                      inheritedRtl:
                                          _editorBlockResolvedRtl(index),
                                      onTap: () {
                                        _verticalArrowPreferredX = null;
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
                                        index,
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
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: AnimatedBuilder(
                    animation: Listenable.merge(_controllers),
                    builder: (context, child) {
                      if (_isPendingLoad || !_hasAnyActiveEditorSelection) {
                        return const SizedBox.shrink();
                      }
                      return _buildAppSelectionToolbar();
                    },
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
                                  Color(0xFFFFBF00),
                                ),
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
                    ),
                  ),
                if (settings.debugMode)
                  Positioned(bottom: 24, left: 24, child: _buildDebugSentry()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
