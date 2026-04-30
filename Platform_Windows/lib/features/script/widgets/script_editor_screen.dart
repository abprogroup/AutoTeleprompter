import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/widgets/global_color_picker.dart';
import '../models/script.dart';
import '../models/cursor_style.dart';
import '../models/editor_state.dart';
import './editor/editor_dialogs.dart';
import './editor/lobby_settings_panel.dart';
import './editor/suites/project_actions_mvp.dart';
import './editor/suites/formatting_toolbar_mvp.dart';
import './editor/components/editor_primitives.dart';
import './editor/styling_logic_mixin.dart';
import './editor/markup_controller.dart';
import './editor/components/global_selection_overlay.dart';
import './editor/components/ghost_selection_controls.dart';
import '../providers/script_provider.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../settings/providers/settings_provider.dart';
import '../../teleprompter/widgets/teleprompter_screen.dart';
import '../../teleprompter/providers/teleprompter_provider.dart';
import '../services/styling_service.dart';
import '../services/script_bookmark_service.dart';
import '../../../core/services/rich_clipboard.dart';
import '../services/docx_service.dart';
import '../services/rtf_service.dart';
import '../services/pages_service.dart';
import '../services/markup_export_service.dart';
import '../../teleprompter/services/word_aligner.dart';
import '../../../platform/file_import/platform_file_import.dart';
import '../../../platform/keyboard/platform_keyboard.dart';

part 'script_editor_screen.load_blocks.dart';
part 'script_editor_screen.dialogs_history.dart';
part 'script_editor_screen.styling_commands.dart';
part 'script_editor_screen.file_present.dart';
part 'script_editor_screen.debug_bookmarks_search.dart';
part 'script_editor_screen.editor_block.dart';

// v3.9.5.59: Absolute Atomic Coordinator
// ── Switchboard Orchestrator ──────────────────────────────────────────────────

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _MoveLeftIntent extends Intent {
  const _MoveLeftIntent();
}

class _MoveRightIntent extends Intent {
  const _MoveRightIntent();
}

class ScriptEditorScreen extends ConsumerStatefulWidget {
  final bool shouldAutoLoad;
  final File? pendingFile;
  const ScriptEditorScreen(
      {super.key, this.shouldAutoLoad = false, this.pendingFile});

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen>
    with StylingLogicMixin<ScriptEditorScreen> {
  // ── Mixin Implementation for StylingLogicMixin ────────────────────────────
  @override
  List<MarkupController> get controllers => _controllers;
  @override
  MarkupController? get activeController =>
      _lastFocusedController ??
      (_controllers.isNotEmpty ? _controllers[0] : null);
  @override
  bool get isGlobalSelection => _isGlobalSelection;
  @override
  set isGlobalSelection(bool value) =>
      setState(() => _isGlobalSelection = value);
  @override
  bool get isCleaning => _isCleaning;
  @override
  set isCleaning(bool value) => setState(() => _isCleaning = value);
  @override
  void saveHistory({required String description, bool debounce = true}) =>
      _saveHistory(description: description, debounce: debounce);

  // ── State Members ──────────────────────────────────────────────────────────
  final List<MarkupController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  final List<GlobalKey> _blockKeys = [];
  final ScrollController _editorScrollController = ScrollController();
  String _currentTitle = 'New Project';

  TextSelection? _lastSelection;

  /// Preserved non-collapsed selection — survives focus loss from dialogs.
  /// Updated only when the selection is non-collapsed, so opening a dialog
  /// (which collapses the selection) doesn't overwrite this.
  TextSelection? _preservedSelection;
  MarkupController? _lastFocusedController;

  String _sourceType = 'TEMP';
  String? _currentSessionId;
  final List<EditorState> _history = [];
  int _historyIndex = -1;
  static const int _maxHistory = 50;

  Color _lastChosenTextColor = const Color(0xFFFFBF00);
  Color _lastChosenHighlightColor = const Color(0x4DFFFFFF);
  String _lastSearchQuery = '';
  String? _bookmarkScopeKey;
  String? _bookmarkLoadingKey;
  bool _bookmarksLoaded = false;
  List<ScriptBookmark> _bookmarks = const [];

  bool _isInit = false;
  bool _isCleaning = false; // v3.9.5.1: Suppression flag
  bool _isGlobalSelection = false; // v3.9.5.1: Broadcast mode
  bool _isSuiteDirty = false;
  bool _isCommandExecuting = false;
  bool _isDirty = false;
  bool _isLoading = false;
  bool _isPendingLoad = false;
  EditorSuite _activeSuite = EditorSuite.none;
  Timer? _historyTimer, _recentTimer, _autoSaveTimer;
  Timer?
      _settingsDebounceTimer; // v4.1.4: time-only debounce for slider changes

  // v3.9.6: Professional History Bulking
  int _typingCharCount = 0; // chars typed since last history commit
  Timer? _typingBulkTimer; // 10-second typing bulk window
  Timer? _suiteAutoSaveTimer; // 3-second auto-checkpoint while suite is open
  String?
      _suiteSection; // current function section within a suite (e.g. 'Bold', 'Font Size')
  final GlobalKey<GlobalSelectionOverlayState> _overlayKey =
      GlobalKey<GlobalSelectionOverlayState>();

  @override
  void initState() {
    super.initState();
    _startAutoSave();
    if (widget.pendingFile != null) {
      _isInit = true;
      _isPendingLoad = true;
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runPendingFileLoad(widget.pendingFile!);
      });
    } else if (widget.shouldAutoLoad) {
      _isInit = true;
      _isPendingLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _importFile());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final script = ref.read(scriptProvider);
      String initialText = '';
      String initialTitle = 'Last Session';

      if (script != null) {
        initialText = script.rawText;
        initialTitle = script.title;
        _sourceType = script.sourceType;
        _currentSessionId = script.sessionId;
        Future.microtask(() {
          if (!mounted) return;
          _applySettingsFromScript(script);
        });
      }
      _currentSessionId ??= DateTime.now().millisecondsSinceEpoch.toString();

      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      _loadText(initialText);
      _currentTitle = initialTitle;

      if (script?.historyJson != null) {
        try {
          final List<dynamic> historyData = jsonDecode(script!.historyJson!);
          _history.clear();
          _history.addAll(historyData.map((d) => EditorState.fromJson(d)));
          _historyIndex = _history.length - 1;
        } catch (_) {}
      }

      _isInit = true;
      if (script != null &&
          script.historyIndex >= 0 &&
          script.historyIndex < _history.length) {
        _historyIndex = script.historyIndex;
        final s = _history[_historyIndex];
        _loadText(s.text);
        Future.microtask(() {
          if (mounted) _applySettingsFromState(s);
        });
      } else if (_history.isNotEmpty) {
        _historyIndex = _history.length - 1;
        final s = _history.last;
        _loadText(s.text);
        Future.microtask(() {
          if (mounted) _applySettingsFromState(s);
        });
      } else {
        _saveHistory(description: 'Initial Load');
      }
      _forceRecentUpdate();
      unawaited(_loadBookmarksForCurrentScript());
    }
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _recentTimer?.cancel();
    _autoSaveTimer?.cancel();
    _typingBulkTimer?.cancel();
    _suiteAutoSaveTimer?.cancel();
    _editorScrollController.dispose();
    _clearControllers();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
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
          onAddBookmark: _addEditorBookmark,
          onRemoveBookmark: () =>
              unawaited(_deleteEditorBookmarkAtCurrentPosition()),
          onPreviousBookmark: () => _jumpEditorBookmark(-1),
          onNextBookmark: () => _jumpEditorBookmark(1),
        ),
      ),
      bottomNavigationBar:
          _buildBottomActions(keyboardVisible: keyboardVisible),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Shortcuts(
              shortcuts: {
                LogicalKeySet(
                        LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
                    const _SelectAllIntent(),
                LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA):
                    const _SelectAllIntent(),
                LogicalKeySet(
                        LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
                    const _CopyIntent(),
                LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC):
                    const _CopyIntent(),
                LogicalKeySet(
                    LogicalKeyboardKey.control,
                    LogicalKeyboardKey.shift,
                    LogicalKeyboardKey.keyF): const _SearchIntent(),
                LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift,
                    LogicalKeyboardKey.keyF): const _SearchIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                    const _MoveLeftIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowRight):
                    const _MoveRightIntent(),
              },
              child: Actions(
                actions: {
                  _SelectAllIntent:
                      CallbackAction<_SelectAllIntent>(onInvoke: (intent) {
                    _selectAllBlocks();
                    return null;
                  }),
                  _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (intent) {
                    _onCopyClean();
                    return null;
                  }),
                  _SearchIntent:
                      CallbackAction<_SearchIntent>(onInvoke: (intent) {
                    _showSearchDialog();
                    return null;
                  }),
                  _MoveLeftIntent:
                      CallbackAction<_MoveLeftIntent>(onInvoke: (intent) {
                    if (_isGlobalSelection) {
                      _clearGlobalSelection();
                      if (_controllers.isNotEmpty) {
                        _focusNodes[0].requestFocus();
                        _controllers[0].selection =
                            const TextSelection.collapsed(offset: 0);
                      }
                      return null;
                    }
                    return null; // Let it bubble to FocusNode
                  }),
                  _MoveRightIntent:
                      CallbackAction<_MoveRightIntent>(onInvoke: (intent) {
                    if (_isGlobalSelection) {
                      _clearGlobalSelection();
                      if (_controllers.isNotEmpty) {
                        final last = _controllers.length - 1;
                        _focusNodes[last].requestFocus();
                        _controllers[last].selection = TextSelection.collapsed(
                            offset: _controllers[last].text.length);
                      }
                      return null;
                    }
                    return null; // Let it bubble to FocusNode
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
                            (_overlayKey.currentState?.hasSelection ?? false)) {
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
                                selection:
                                    TextSelection.collapsed(offset: sel.start),
                              );
                            } else if (sel.isValid && sel.isCollapsed) {
                              // Check if cursor is at end of line/paragraph → Baseline Mode: clear whole script
                              final plainText = text.replaceAll(tagPattern, '');
                              final cursorInPlain = sel.start >= text.length ||
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
                            final hasAlign =
                                RegExp(r'\[(?:align=)?(?:center|left|right)\]')
                                    .hasMatch(c.text);
                            if (!hasAlign) {
                              ref.read(cursorStyleProvider.notifier).state = ref
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
                        final willClose =
                            suite == EditorSuite.none || suite == _activeSuite;
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
                            _isGlobalSelection = _controllers.isNotEmpty &&
                                _controllers.every((c) => c.isGlobalSelected);
                          }),
                          child: SingleChildScrollView(
                            controller: _editorScrollController,
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 250),
                            child: Column(
                              children: List.generate(
                                _controllers.length,
                                (index) => _EditorBlock(
                                  key: _blockKeys[index],
                                  controller: _controllers[index],
                                  focusNode: _focusNodes[index],
                                  settings: settings,
                                  isGlobalSelected: _isGlobalSelection,
                                  onSubmitted: () => _addBlock(index + 1),
                                  onTap: () {
                                    if (_isGlobalSelection ||
                                        _controllers
                                            .any((c) => c.isGlobalSelected) ||
                                        (_overlayKey
                                                .currentState?.hasSelection ??
                                            false) ||
                                        _controllers.any((c) =>
                                            c.externalSelection != null)) {
                                      _clearGlobalSelection();
                                    }
                                  },
                                  onSelectAll: _selectAllBlocks,
                                  onCopy: _onCopyClean,
                                  onSearch: _showSearchDialog,
                                  hasBookmark: _hasBookmarkInEditorBlock(index),
                                  onBookmarkTap: () =>
                                      _deleteEditorBookmarksForBlock(index),
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
    );
  }
}
