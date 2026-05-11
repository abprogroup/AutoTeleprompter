import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
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
import '../services/markup_decoration_service.dart';
import '../services/editor_text_geometry_service.dart';
import '../../teleprompter/services/word_aligner.dart';
import '../models/script_word.dart';
import '../../../platform/file_import/platform_file_import.dart';
import '../../../platform/keyboard/platform_keyboard.dart';

part 'script_editor_screen.load_blocks.dart';
part 'script_editor_screen.dialogs_history.dart';
part 'script_editor_screen.styling_commands.dart';
part 'script_editor_screen.file_present.dart';
part 'script_editor_screen.debug_bookmarks_search.dart';
part 'script_editor_screen.bookmarks.dart';
part 'script_editor_screen.search.dart';
part 'script_editor_screen.editor_block.dart';

// v3.9.5.59: Absolute Atomic Coordinator
// ── Switchboard Orchestrator ──────────────────────────────────────────────────

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _CutIntent extends Intent {
  const _CutIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
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

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
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
    with WidgetsBindingObserver, StylingLogicMixin<ScriptEditorScreen> {
  // Dummy node for HardwareKeyboard → _handleEditorArrowKey bridge
  // (_handleEditorArrowKey never uses the node parameter).
  static final _arrowKeyDummyNode = FocusNode();
  static const String _keyboardBookmarkSign = '\u00BB';
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
  double? _editorScrollOffsetBeforeWindowHide;
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
  bool _searchDialogOpen = false;
  bool _searchWholeWord = false;
  bool _editorSearchToolbarVisible = false;
  List<_EditorSearchMatch> _editorSearchMatches = const [];
  int _editorSearchMatchIndex = -1;
  String _lastArrowDecision = 'idle';
  SelectionEndpoint? _shiftSelectionAnchor;
  SelectionEndpoint? _shiftSelectionFocus;
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
  Timer? _historyTimer, _recentTimer, _autoSaveTimer, _clipboardGuardTimer;
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

  void _clearGlobalSelection() {
    if (!mounted) return;
    setState(() {
      _isGlobalSelection = false;
      _overlayKey.currentState?.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        // Collapse native selection to prevent residual highlight in buildTextSpan.
        if (!c.selection.isCollapsed) {
          final collapseAt = c.selection.baseOffset.clamp(0, c.text.length);
          c.selection = TextSelection.collapsed(offset: collapseAt);
        }
        c.refresh();
      }
    });

    // Safety net: re-clear after Flutter's TextField processes any lingering gestures.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool needsRefresh = false;
      for (final c in _controllers) {
        if (c.externalSelection != null || c.isGlobalSelected) {
          c.externalSelection = null;
          c.isGlobalSelected = false;
          needsRefresh = true;
        }
      }
      if (needsRefresh) {
        for (final c in _controllers) c.refresh();
        setState(() {});
      }
    });
  }

  List<String> get _editorRawBlocks =>
      _controllers.map((controller) => controller.text).toList(growable: false);

  bool _editorBlockResolvedRtl(int index) {
    return EditorTextGeometryService.resolveBlockRtl(_editorRawBlocks, index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onGlobalArrowKey);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_editorScrollController.hasClients) {
        _editorScrollOffsetBeforeWindowHide = _editorScrollController.offset;
      }
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final restoreOffset = _editorScrollOffsetBeforeWindowHide;
    if (restoreOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editorScrollController.hasClients) return;
      final max = _editorScrollController.position.maxScrollExtent;
      _editorScrollController.jumpTo(restoreOffset.clamp(0.0, max));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_editorScrollController.hasClients) return;
        final max = _editorScrollController.position.maxScrollExtent;
        _editorScrollController.jumpTo(restoreOffset.clamp(0.0, max));
      });
    });
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

      // Read historyJson and historyIndex DIRECTLY from the persisted recent
      // scripts entry (matched by sessionId).  scriptProvider.state.rawText is
      // only updated by _startPresenting, so it can be stale when the user
      // navigates away and back without going through the presenter.
      String? freshHistoryJson = script?.historyJson;
      int? freshHistoryIndex;
      if (_currentSessionId != null) {
        final recents = ref.read(settingsProvider).recentScripts;
        for (final json in recents) {
          try {
            final meta = jsonDecode(json) as Map<String, dynamic>;
            if (meta['sessionId'] == _currentSessionId) {
              final mj = meta['historyJson'];
              final mi = meta['historyIndex'];
              if (mj is String) freshHistoryJson = mj;
              if (mi is int) freshHistoryIndex = mi;
              break;
            }
          } catch (_) {}
        }
      }

      if (freshHistoryJson != null) {
        try {
          final List<dynamic> historyData = jsonDecode(freshHistoryJson);
          _history.clear();
          _history.addAll(historyData.map((d) => EditorState.fromJson(d)));
          _historyIndex = _history.length - 1;
        } catch (_) {}
      }

      final resolvedHistoryIndex = freshHistoryIndex ?? script?.historyIndex;

      _isInit = true;
      if (resolvedHistoryIndex != null &&
          resolvedHistoryIndex >= 0 &&
          resolvedHistoryIndex < _history.length) {
        _historyIndex = resolvedHistoryIndex;
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
      // Migrate old metadata-only bookmarks → insert » signs into text.
      // Safe to re-run: strips existing signs first, then re-inserts in order.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reconcileEditorBookmarkSignsFromMetadata());
      });
    }
  }

  void _startClipboardGuard(String expectedPlain) {
    _clipboardGuardTimer?.cancel();
    _clipboardGuardTimer = Timer(const Duration(seconds: 20), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      final normalized =
          (current?.text ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (normalized.trimRight() != expectedPlain.trimRight()) {
        RichClipboard.clearInternal();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onGlobalArrowKey);
    _clipboardGuardTimer?.cancel();
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
      ),
    );
  }

  // ── Screen-level arrow-key cross-block navigation ──────────────────────────
  // HardwareKeyboard handler: fires BEFORE Flutter's focus system, so key-repeat
  // events are never dropped during the async focus-transfer window when crossing
  // a block boundary. Returns true only at boundaries; in-block movement is passed
  // through (returns false) so EditableText's default cursor handling stays intact.
  bool _onGlobalArrowKey(KeyEvent event) {
    if (!mounted || _controllers.isEmpty) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_handleGlobalEditingShortcut(event)) return true;
    final hasEditorFocus = _focusNodes.any((n) => n.hasFocus);
    final hasAppSelectionForKeyboard =
        _isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false);
    if (!hasEditorFocus && !hasAppSelectionForKeyboard) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    if (hasEditorFocus && !hasAppSelectionForKeyboard) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      return _extendAppSelectionForArrow(key, keyboard);
    }
    if (_clearAppSelectionForArrow(key)) return true;
    final hasModifier = _hasAnyArrowModifier(keyboard);
    final routeModifiedArrow = _shouldRouteModifiedArrow(key, keyboard);
    if (hasModifier && !routeModifiedArrow) return false;
    _lastArrowDecision = 'arrow ${key.keyLabel}: route';
    return _handleEditorArrowKey(_arrowKeyDummyNode, event) ==
        KeyEventResult.handled;
  }

  bool _clearStaleOverlaySelectionForShift(HardwareKeyboard keyboard) {
    if (!keyboard.isShiftPressed || _isGlobalSelection) return false;
    final overlay = _overlayKey.currentState;
    final session = overlay?.selectionSessionSnapshot;
    if (overlay == null || !(overlay.hasSelection)) return false;
    // Use the editor's synchronous focus authority, not FocusNode iteration.
    // FocusNode ownership can lag for one key repeat after app-owned
    // Ctrl/Shift selection crosses a block, which made the stale-overlay guard
    // clear a valid overlay and restart selection in the next block.
    final controller = _lastFocusedController;
    if (controller == null) {
      _shiftSelectionAnchor = null;
      _shiftSelectionFocus = null;
      overlay.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        c.refresh();
      }
      setState(() {
        _isGlobalSelection = false;
        _lastArrowDecision = 'shift stale overlay cleared: no focus';
      });
      return true;
    }
    final block = _controllers.indexOf(controller);
    if (block < 0) return false;
    final selection = controller.selection;
    if (!selection.isValid) {
      _shiftSelectionAnchor = null;
      _shiftSelectionFocus = null;
      overlay.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        c.refresh();
      }
      setState(() {
        _isGlobalSelection = false;
        _lastArrowDecision = 'shift stale overlay cleared: invalid selection';
      });
      return true;
    }
    final offset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final visibleOverlayRange = _hasVisibleAppSelectionRange();
    if (session != null &&
        visibleOverlayRange &&
        session.focus.block == block &&
        session.focus.offset == offset) {
      return false;
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    overlay.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.refresh();
    }
    setState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = visibleOverlayRange
          ? 'shift stale overlay cleared focus ${session?.focus} != $block:$offset'
          : 'shift stale overlay cleared invisible at $block:$offset';
    });
    return true;
  }

  bool _hasVisibleAppSelectionRange() {
    if (_isGlobalSelection) return true;
    for (final c in _controllers) {
      if (c.isGlobalSelected) return true;
      final selection = c.externalSelection;
      if (selection != null && selection.isValid && !selection.isCollapsed) {
        return true;
      }
    }
    return false;
  }

  bool _shouldRouteModifiedArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    if (_isPlainArrowModifierState(keyboard)) {
      return true;
    }
    if (keyboard.isMetaPressed) return false;
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  bool _hasAnyArrowModifier(HardwareKeyboard keyboard) =>
      keyboard.isControlPressed ||
      keyboard.isShiftPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed;

  bool _isPlainArrowModifierState(HardwareKeyboard keyboard) =>
      !_hasAnyArrowModifier(keyboard);

  bool _isControlArrowModifierState(
    HardwareKeyboard keyboard, {
    bool allowShift = true,
  }) {
    return keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        (allowShift || !keyboard.isShiftPressed);
  }

  bool _isAltArrowModifierState(HardwareKeyboard keyboard) {
    return keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed;
  }

  bool _handleGlobalEditingShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final hasShortcutModifier =
        keyboard.isControlPressed || keyboard.isMetaPressed;
    if (!hasShortcutModifier || keyboard.isAltPressed) return false;
    final hasAppSelection =
        _isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false);
    if (!hasAppSelection) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyC) {
      _overlayKey.currentState?.endDragging();
      _onCopyClean();
      _lastArrowDecision = 'shortcut copy: app selection';
      return true;
    }
    if (key == LogicalKeyboardKey.keyX) {
      _overlayKey.currentState?.endDragging();
      _onCut();
      _lastArrowDecision = 'shortcut cut: app selection';
      return true;
    }
    if (key == LogicalKeyboardKey.keyV) {
      _overlayKey.currentState?.endDragging();
      unawaited(_onPaste());
      _lastArrowDecision = 'shortcut paste: app selection';
      return true;
    }
    return false;
  }

  bool _clearAppSelectionForArrow(LogicalKeyboardKey key) {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (!_isGlobalSelection && !hasOverlay) return false;
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    final collapseToEnd = _collapseSelectionToEndForArrow(key);
    final target = _appSelectionEdge(collapseToEnd: collapseToEnd);
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      final selection = c.selection;
      if (selection.isValid && !selection.isCollapsed) {
        final offset = collapseToEnd
            ? selection.end.clamp(0, c.text.length).toInt()
            : selection.start.clamp(0, c.text.length).toInt();
        c.selection = TextSelection.collapsed(offset: offset);
      }
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.refresh();
    }
    setState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = target == null
          ? 'clear selection ${key.keyLabel}: no target'
          : 'clear selection ${key.keyLabel}: ${target.block}:${target.offset}';
    });
    if (target != null) {
      _lastFocusedController = _controllers[target.block];
      _focusNodes[target.block].requestFocus();
      _controllers[target.block].selection =
          TextSelection.collapsed(offset: target.offset);
      _scrollEditorBlockIntoView(target.block);
    }
    return true;
  }

  bool _collapseSelectionToEndForArrow(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) return true;
    if (key == LogicalKeyboardKey.arrowUp) return false;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }

    final session = _overlayKey.currentState?.selectionSessionSnapshot;
    final focusBlock = session?.focus.block;
    final active = _activeController ?? _lastFocusedController;
    final activeIndex = active == null ? -1 : _controllers.indexOf(active);
    final blockIndex = focusBlock != null &&
            focusBlock >= 0 &&
            focusBlock < _controllers.length
        ? focusBlock
        : activeIndex;
    final isRtl = blockIndex >= 0 ? _editorBlockResolvedRtl(blockIndex) : false;
    if (key == LogicalKeyboardKey.arrowLeft) return isRtl;
    return !isRtl;
  }

  ({int block, int offset})? _appSelectionEdge({
    required bool collapseToEnd,
  }) {
    ({int block, int offset})? first;
    ({int block, int offset})? last;
    for (var i = 0; i < _controllers.length; i++) {
      final c = _controllers[i];
      final sel = c.externalSelection;
      final fullBlock = c.isGlobalSelected;
      final hasRange =
          fullBlock || (sel != null && sel.isValid && !sel.isCollapsed);
      if (!hasRange) continue;
      final start = fullBlock ? 0 : sel!.start.clamp(0, c.text.length).toInt();
      final end =
          fullBlock ? c.text.length : sel!.end.clamp(0, c.text.length).toInt();
      final low = start < end ? start : end;
      final high = start > end ? start : end;
      first ??= (block: i, offset: low);
      last = (block: i, offset: high);
    }
    if (first == null || last == null) {
      final active = _activeController;
      if (active == null) return null;
      final idx = _controllers.indexOf(active);
      if (idx < 0) return null;
      final sel = active.selection;
      final offset = collapseToEnd
          ? sel.end.clamp(0, active.text.length).toInt()
          : sel.start.clamp(0, active.text.length).toInt();
      return (block: idx, offset: offset);
    }
    return collapseToEnd ? last : first;
  }

  bool _extendAppSelectionForArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    final seed = _shiftSelectionSeed(keyboard);
    if (seed == null) {
      _lastArrowDecision = 'shift ${key.keyLabel}: no focused caret';
      return true;
    }
    final anchor = seed.anchor;
    final focus = seed.focus;
    final target = _shiftArrowTarget(
      key: key,
      keyboard: keyboard,
      focus: focus,
    );
    if (target == null) {
      _lastArrowDecision =
          'shift ${key.keyLabel}: boundary ${focus.block}:${focus.offset}';
      return true;
    }
    if (target.block == focus.block && target.offset == focus.offset) {
      _lastArrowDecision =
          'shift ${key.keyLabel}: unchanged ${focus.block}:${focus.offset}';
      return true;
    }
    final adjusted = _clampKeyboardTargetAtAnchor(
      anchor: anchor,
      focus: focus,
      target: SelectionEndpoint(block: target.block, offset: target.offset),
    );
    if (_sameEndpoint(anchor, adjusted)) {
      _collapseAppSelectionTo(anchor,
          reason: 'extend-collapse ${key.keyLabel}');
      return true;
    }
    _setAppSelectionFromAnchorToFocus(anchor, adjusted);
    _lastArrowDecision =
        'extend ${key.keyLabel}: ${anchor.block}:${anchor.offset}-${adjusted.block}:${adjusted.offset}';
    return true;
  }

  ({SelectionEndpoint anchor, SelectionEndpoint focus})? _shiftSelectionSeed(
    HardwareKeyboard keyboard,
  ) {
    final visibleOverlayRange = _hasVisibleAppSelectionRange();
    final session = _overlayKey.currentState?.selectionSessionSnapshot;
    if (visibleOverlayRange && session != null) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (anchor: session.anchor, focus: session.focus);
    }
    final rememberedAnchor = _shiftSelectionAnchor;
    final rememberedFocus = _shiftSelectionFocus;
    if (visibleOverlayRange &&
        rememberedAnchor != null &&
        rememberedFocus != null) {
      return (anchor: rememberedAnchor, focus: rememberedFocus);
    }
    _clearStaleOverlaySelectionForShift(keyboard);
    final controller = _lastFocusedController ?? _activeController;
    if (controller == null) return null;
    final block = _controllers.indexOf(controller);
    if (block < 0) return null;
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final realAnchor = SelectionEndpoint(
      block: block,
      offset: selection.baseOffset.clamp(0, controller.text.length).toInt(),
    );
    final realFocus = SelectionEndpoint(
      block: block,
      offset: selection.extentOffset.clamp(0, controller.text.length).toInt(),
    );
    final currentVisibleOverlayRange = _hasVisibleAppSelectionRange();
    if (session != null &&
        currentVisibleOverlayRange &&
        _sameEndpoint(session.focus, realFocus)) {
      return (anchor: session.anchor, focus: session.focus);
    }
    if (currentVisibleOverlayRange || _isGlobalSelection) {
      _overlayKey.currentState?.clearSelection();
      for (final c in _controllers) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
        c.refresh();
      }
      _isGlobalSelection = false;
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    return (anchor: realAnchor, focus: realFocus);
  }

  ({int block, int offset})? _shiftArrowTarget({
    required LogicalKeyboardKey key,
    required HardwareKeyboard keyboard,
    required SelectionEndpoint focus,
  }) {
    if (_isPlainShiftVerticalArrow(key, keyboard)) {
      return _plainShiftVerticalLineTarget(
        block: focus.block,
        offset: focus.offset,
        key: key,
      );
    }
    return _arrowTargetFromPosition(
      key: key,
      block: focus.block,
      offset: focus.offset,
      keyboard: keyboard,
      allowInBlockHorizontalStep:
          !keyboard.isControlPressed && !keyboard.isAltPressed,
      allowInBlockVerticalStep: true,
    );
  }

  bool _isPlainShiftVerticalArrow(
    LogicalKeyboardKey key,
    HardwareKeyboard keyboard,
  ) {
    return keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown);
  }

  ({int block, int offset})? _plainShiftVerticalLineTarget({
    required int block,
    required int offset,
    required LogicalKeyboardKey key,
    bool crossBlockOnly = false,
  }) {
    if (block < 0 || block >= _controllers.length) return null;
    final moveUp = key == LogicalKeyboardKey.arrowUp;
    final controller = _controllers[block];
    final safeOffset = offset.clamp(0, controller.text.length).toInt();
    final layout = _getVerticalLayout(
      block,
      selection: TextSelection.collapsed(offset: safeOffset),
    );
    final preferredX = layout.currentX;
    final visibleText = StylingService.stripTags(controller.text);
    if (visibleText.trim().isEmpty) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: moveUp,
        preferredX: preferredX,
      );
    }

    final plainText = layout.painter.text?.toPlainText() ?? '';
    if (plainText.isEmpty) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: moveUp,
        preferredX: preferredX,
      );
    }

    final painterOffset = safeOffset.clamp(0, plainText.length).toInt();
    final line = layout.painter.getLineBoundary(
      TextPosition(offset: painterOffset),
    );
    if (moveUp && line.start <= 0) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: true,
        preferredX: preferredX,
      );
    }
    if (!moveUp && line.end >= plainText.length) {
      return _plainShiftVerticalCrossBlockTarget(
        fromBlock: block,
        moveUp: false,
        preferredX: preferredX,
      );
    }
    if (crossBlockOnly) return null;

    final targetOffset = layout
        .visualVerticalTargetRawOffset(
          rawText: controller.text,
          rawOffset: safeOffset,
          moveUp: moveUp,
        )
        ?.clamp(0, controller.text.length)
        .toInt();
    if (targetOffset == null) return null;
    if (targetOffset == safeOffset) return null;
    return (block: block, offset: targetOffset);
  }

  ({int block, int offset})? _plainShiftVerticalCrossBlockTarget({
    required int fromBlock,
    required bool moveUp,
    required double preferredX,
  }) {
    final targetBlock = fromBlock + (moveUp ? -1 : 1);
    if (targetBlock < 0 || targetBlock >= _controllers.length) return null;
    final targetController = _controllers[targetBlock];
    if (StylingService.stripTags(targetController.text).trim().isEmpty) {
      return (block: targetBlock, offset: 0);
    }
    final fallbackOffset =
        moveUp ? MarkupController.safeEndOffset(targetController.text) : 0;
    final layout = _getVerticalLayout(
      targetBlock,
      selection: TextSelection.collapsed(offset: fallbackOffset),
    );
    final offset = layout
        .getPositionAtX(
          preferredX,
          fromBottom: moveUp,
          rawText: targetController.text,
        )
        .clamp(0, targetController.text.length)
        .toInt();
    return (block: targetBlock, offset: offset);
  }

  bool _sameEndpoint(SelectionEndpoint a, SelectionEndpoint b) =>
      a.block == b.block && a.offset == b.offset;

  int _compareEndpoints(SelectionEndpoint a, SelectionEndpoint b) {
    if (a.block != b.block) return a.block.compareTo(b.block);
    return a.offset.compareTo(b.offset);
  }

  SelectionEndpoint _clampKeyboardTargetAtAnchor({
    required SelectionEndpoint anchor,
    required SelectionEndpoint focus,
    required SelectionEndpoint target,
  }) {
    final focusSide = _compareEndpoints(focus, anchor);
    final targetSide = _compareEndpoints(target, anchor);
    if (focusSide == 0 || targetSide == 0) return target;
    if ((focusSide < 0 && targetSide > 0) ||
        (focusSide > 0 && targetSide < 0)) {
      return anchor;
    }
    return target;
  }

  void _setAppSelectionFromAnchorToFocus(
    SelectionEndpoint anchor,
    SelectionEndpoint focus,
  ) {
    _shiftSelectionAnchor = anchor;
    _shiftSelectionFocus = focus;
    _lastFocusedController = _controllers[focus.block];
    _focusNodes[focus.block].requestFocus();
    _controllers[focus.block].selection =
        TextSelection.collapsed(offset: focus.offset);
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: anchor.block,
      anchorOffset: anchor.offset,
      focusBlock: focus.block,
      focusOffset: focus.offset,
    );
    _scrollEditorBlockIntoView(focus.block);
  }

  void _collapseAppSelectionTo(SelectionEndpoint target,
      {required String reason}) {
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.refresh();
    }
    setState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = '$reason: ${target.block}:${target.offset}';
    });
    _lastFocusedController = _controllers[target.block];
    _focusNodes[target.block].requestFocus();
    _controllers[target.block].selection =
        TextSelection.collapsed(offset: target.offset);
    _scrollEditorBlockIntoView(target.block);
  }

  KeyEventResult _handleEditorArrowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }

    // Global selection short-circuit: any arrow collapses + repositions cursor.
    if (_isGlobalSelection) {
      _clearGlobalSelection();
      if (_controllers.isEmpty) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowLeft) {
        _crossToBlock(0, atOffset: 0);
      } else {
        final last = _controllers.length - 1;
        _crossToBlock(last, atOffset: _controllers[last].text.length);
      }
      return KeyEventResult.handled;
    }

    final controller = _lastFocusedController;
    if (controller == null) return KeyEventResult.ignored;
    final idx = _controllers.indexOf(controller);
    if (idx < 0) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    if (_isControlArrowModifierState(keyboard) &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      return _handleControlVerticalArrowKey(
        key: key,
        controller: controller,
        blockIndex: idx,
        extendSelection: keyboard.isShiftPressed,
      );
    }

    if (keyboard.isShiftPressed) {
      final shifted = _extendNativeShiftSelectionAcrossBlockIfNeeded(
        key: key,
        keyboard: keyboard,
        controller: controller,
        blockIndex: idx,
        selection: controller.selection,
      );
      if (shifted) return KeyEventResult.handled;
    }

    if (_isPlainArrowModifierState(keyboard) &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final safeOffset = controller.selection.extentOffset
          .clamp(0, controller.text.length)
          .toInt();
      final isRtl = _editorBlockResolvedRtl(idx);
      final target = _plainShiftVerticalLineTarget(
        block: idx,
        offset: safeOffset,
        key: key,
        crossBlockOnly: !isRtl,
      );
      if (target == null) {
        return isRtl ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      if (target.block == idx) {
        controller.selection = TextSelection.collapsed(
          offset: target.offset.clamp(0, controller.text.length).toInt(),
        );
        _lastArrowDecision = 'visual ${key.keyLabel}: $idx:${target.offset}';
      } else {
        _crossToBlock(target.block, atOffset: target.offset);
        _lastArrowDecision =
            'visual ${key.keyLabel}: ${target.block}:${target.offset}';
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp && idx > 0) {
      final layout = _getVerticalLayout(idx);
      if (layout.isAtTop) {
        _crossToBlock(idx - 1, x: layout.currentX, atEnd: true);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowDown && idx < _controllers.length - 1) {
      final layout = _getVerticalLayout(idx);
      if (layout.isAtBottom) {
        _crossToBlock(idx + 1, x: layout.currentX, atEnd: false);
        return KeyEventResult.handled;
      }
    }

    // Left/Right are routed through the shared visual geometry helper. Keeping
    // raw/logical fallbacks here caused old RTL behavior to fight the rendered
    // caret positions.
    final isRtl = _editorBlockResolvedRtl(idx);
    final sel = controller.selection;
    final textLen = controller.text.length;

    return _handleHorizontalArrowKey(
          key: key,
          controller: controller,
          blockIndex: idx,
          isRtl: isRtl,
          selection: sel,
          textLength: textLen,
          manualInBlock: _isPlainArrowModifierState(keyboard),
        ) ??
        KeyEventResult.ignored;
  }

  KeyEventResult _handleControlVerticalArrowKey({
    required LogicalKeyboardKey key,
    required MarkupController controller,
    required int blockIndex,
    required bool extendSelection,
  }) {
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final focusOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final target = _controlVerticalTarget(
      blockIndex: blockIndex,
      focusOffset: focusOffset,
      moveUp: key == LogicalKeyboardKey.arrowUp,
    );
    if (target == null) {
      _lastArrowDecision =
          'ctrl ${key.keyLabel}: boundary $blockIndex:$focusOffset';
      return KeyEventResult.ignored;
    }

    if (extendSelection) {
      final anchorOffset =
          selection.baseOffset.clamp(0, controller.text.length).toInt();
      _extendControlVerticalSelection(
        anchorBlock: blockIndex,
        anchorOffset: anchorOffset,
        targetBlock: target.block,
        targetOffset: target.offset,
      );
    } else {
      _crossToBlock(target.block, atOffset: target.offset);
    }
    _lastArrowDecision =
        'ctrl ${key.keyLabel}: ${target.block}:${target.offset}';
    return KeyEventResult.handled;
  }

  String _keyboardNavigationText(String text) =>
      text.replaceAll(_keyboardBookmarkSign, '');

  int _keyboardRawToNavigationOffset(String text, int rawOffset) {
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    var navigationOffset = 0;
    for (var i = 0; i < safeRaw; i++) {
      if (text[i] == _keyboardBookmarkSign) continue;
      navigationOffset++;
    }
    return navigationOffset;
  }

  int _keyboardNavigationToRawOffset(String text, int navigationOffset) {
    if (navigationOffset <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == _keyboardBookmarkSign) continue;
      seen++;
      if (seen >= navigationOffset) return i + 1;
    }
    return text.length;
  }

  int _keyboardNavigationSafeEndOffset(String text) {
    final navigationText = _keyboardNavigationText(text);
    return MarkupController.safeEndOffset(navigationText);
  }

  ({int block, int offset})? _controlVerticalTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, text.length).toInt();
    final navigationFocus = _keyboardRawToNavigationOffset(text, safeFocus);
    if (moveUp) {
      if (navigationFocus > 0) {
        return (
          block: blockIndex,
          offset: _keyboardNavigationToRawOffset(text, 0),
        );
      }
      if (blockIndex > 0) return (block: blockIndex - 1, offset: 0);
      return null;
    }

    final navigationEnd = _keyboardNavigationSafeEndOffset(text);
    if (navigationFocus < navigationEnd) {
      return (
        block: blockIndex,
        offset: _keyboardNavigationToRawOffset(text, navigationEnd),
      );
    }
    if (blockIndex < _controllers.length - 1) {
      final nextText = _controllers[blockIndex + 1].text;
      final nextNavigationEnd = _keyboardNavigationSafeEndOffset(nextText);
      return (
        block: blockIndex + 1,
        offset: _keyboardNavigationToRawOffset(nextText, nextNavigationEnd),
      );
    }
    return null;
  }

  void _extendControlVerticalSelection({
    required int anchorBlock,
    required int anchorOffset,
    required int targetBlock,
    required int targetOffset,
  }) {
    if (anchorBlock == targetBlock) {
      final controller = _controllers[anchorBlock];
      controller.selection = TextSelection(
        baseOffset: anchorOffset.clamp(0, controller.text.length).toInt(),
        extentOffset: targetOffset.clamp(0, controller.text.length).toInt(),
      );
      _lastFocusedController = controller;
      _focusNodes[anchorBlock].requestFocus();
      _scrollEditorBlockIntoView(anchorBlock);
      return;
    }

    _lastFocusedController = _controllers[targetBlock];
    _focusNodes[targetBlock].requestFocus();
    _controllers[targetBlock].selection =
        TextSelection.collapsed(offset: targetOffset);
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: anchorBlock,
      anchorOffset: anchorOffset,
      focusBlock: targetBlock,
      focusOffset: targetOffset,
    );
    _scrollEditorBlockIntoView(targetBlock);
  }

  bool _extendNativeShiftSelectionAcrossBlockIfNeeded({
    required LogicalKeyboardKey key,
    required HardwareKeyboard keyboard,
    required MarkupController controller,
    required int blockIndex,
    required TextSelection selection,
  }) {
    if (!selection.isValid) return false;
    final focusOffset =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final target = _isPlainShiftVerticalArrow(key, keyboard)
        ? _plainShiftVerticalLineTarget(
            block: blockIndex,
            offset: focusOffset,
            key: key,
            crossBlockOnly: true,
          )
        : _arrowTargetFromPosition(
            key: key,
            block: blockIndex,
            offset: focusOffset,
            keyboard: keyboard,
            allowInBlockHorizontalStep: false,
            allowInBlockVerticalStep: false,
          );
    final anchorOffset =
        selection.baseOffset.clamp(0, controller.text.length).toInt();
    if (target == null) return false;
    if (target.block == blockIndex) {
      if (target.offset == focusOffset) return false;
      controller.selection = TextSelection(
        baseOffset: anchorOffset,
        extentOffset: target.offset.clamp(0, controller.text.length).toInt(),
      );
      _lastFocusedController = controller;
      _focusNodes[blockIndex].requestFocus();
      _scrollEditorBlockIntoView(blockIndex);
      _lastArrowDecision =
          'shift same ${key.keyLabel}: $blockIndex:$anchorOffset-$blockIndex:${target.offset}';
      return true;
    }
    _lastFocusedController = _controllers[target.block];
    _focusNodes[target.block].requestFocus();
    _controllers[target.block].selection =
        TextSelection.collapsed(offset: target.offset);
    _overlayKey.currentState?.setKeyboardSelection(
      anchorBlock: blockIndex,
      anchorOffset: anchorOffset,
      focusBlock: target.block,
      focusOffset: target.offset,
    );
    _scrollEditorBlockIntoView(target.block);
    _lastArrowDecision =
        'shift cross ${key.keyLabel}: $blockIndex:$anchorOffset-${target.block}:${target.offset}';
    return true;
  }

  ({int block, int offset})? _arrowTargetFromPosition({
    required LogicalKeyboardKey key,
    required int block,
    required int offset,
    required HardwareKeyboard keyboard,
    required bool allowInBlockHorizontalStep,
    required bool allowInBlockVerticalStep,
  }) {
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (keyboard.isControlPressed) {
        return _controlVerticalTarget(
          blockIndex: block,
          focusOffset: offset,
          moveUp: key == LogicalKeyboardKey.arrowUp,
        );
      }
      return _verticalBoundaryTarget(
        blockIndex: block,
        focusOffset: offset,
        moveUp: key == LogicalKeyboardKey.arrowUp,
        allowInBlockStep: allowInBlockVerticalStep,
      );
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_isControlArrowModifierState(keyboard)) {
        return _controlHorizontalWordTarget(
          blockIndex: block,
          rawOffset: offset,
          key: key,
        );
      }
      if (_isAltArrowModifierState(keyboard)) {
        return _altHorizontalTarget(
          blockIndex: block,
          rawOffset: offset,
          key: key,
        );
      }
      return _horizontalTargetFromPosition(
        blockIndex: block,
        rawOffset: offset,
        key: key,
        allowInBlockStep: allowInBlockHorizontalStep,
      );
    }
    return null;
  }

  ({int block, int offset})? _controlHorizontalWordTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final rawText = _controllers[blockIndex].text;
    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final layout = _getVerticalLayout(
      blockIndex,
      selection: TextSelection.collapsed(offset: safeRaw),
    );
    final visualTarget = layout.visualWordTargetRawOffset(
      rawText: rawText,
      rawOffset: safeRaw,
      moveLeft: key == LogicalKeyboardKey.arrowLeft,
    );
    if (visualTarget != null) {
      final safeTarget = visualTarget.clamp(0, rawText.length).toInt();
      if (safeTarget != safeRaw) {
        return (block: blockIndex, offset: safeTarget);
      }
    }

    return _horizontalBoundaryTargetFromPosition(
      blockIndex: blockIndex,
      rawOffset: safeRaw,
      key: key,
    );
  }

  ({int block, int offset})? _altHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeOffset = rawOffset.clamp(0, text.length).toInt();
    final endOffset = MarkupController.safeEndOffset(text);
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (safeOffset > 0) return (block: blockIndex, offset: 0);
      if (blockIndex > 0) return (block: blockIndex - 1, offset: 0);
      return null;
    }
    if (safeOffset < endOffset) return (block: blockIndex, offset: endOffset);
    if (blockIndex < _controllers.length - 1) {
      final nextText = _controllers[blockIndex + 1].text;
      return (
        block: blockIndex + 1,
        offset: MarkupController.safeEndOffset(nextText),
      );
    }
    return null;
  }

  ({int block, int offset})? _verticalBoundaryTarget({
    required int blockIndex,
    required int focusOffset,
    required bool moveUp,
    required bool allowInBlockStep,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final safeFocus = focusOffset.clamp(0, text.length).toInt();
    final endOffset = MarkupController.safeEndOffset(text);
    if (moveUp) {
      if (safeFocus > 0 && allowInBlockStep) {
        return (block: blockIndex, offset: 0);
      }
      if (safeFocus <= 0 && blockIndex > 0) {
        return (
          block: blockIndex - 1,
          offset:
              MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
        );
      }
      return null;
    }
    if (safeFocus < endOffset && allowInBlockStep) {
      return (block: blockIndex, offset: endOffset);
    }
    if (safeFocus >= endOffset && blockIndex < _controllers.length - 1) {
      return (block: blockIndex + 1, offset: 0);
    }
    return null;
  }

  ({int block, int offset})? _horizontalTargetFromPosition({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool allowInBlockStep,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final rawText = _controllers[blockIndex].text;
    final visibleText = StylingService.stripTags(rawText);
    if (visibleText.trim().isEmpty) {
      return _horizontalBoundaryTargetFromPosition(
        blockIndex: blockIndex,
        rawOffset: rawOffset,
        key: key,
      );
    }

    final safeRaw = rawOffset.clamp(0, rawText.length).toInt();
    final currentVisible = MarkupController.rawToVisualOffset(
      rawText,
      safeRaw,
    ).clamp(0, visibleText.length).toInt();
    final currentRaw =
        MarkupController.visualToRawOffset(rawText, currentVisible);

    final layout = _getVerticalLayout(
      blockIndex,
      selection: TextSelection.collapsed(offset: currentRaw),
    );
    final targetRaw = layout.visualHorizontalTargetRawOffset(
      rawText: rawText,
      rawOffset: currentRaw,
      moveLeft: key == LogicalKeyboardKey.arrowLeft,
    );
    if (targetRaw != null) {
      if (!allowInBlockStep) return null;
      final target = targetRaw.clamp(0, rawText.length).toInt();
      if (target == safeRaw) return null;
      return (block: blockIndex, offset: target);
    }

    return _horizontalBoundaryTargetFromPosition(
      blockIndex: blockIndex,
      rawOffset: rawOffset,
      key: key,
    );
  }

  ({int block, int offset})? _horizontalBoundaryTargetFromPosition({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final controller = _controllers[blockIndex];
    final isRtl = _editorBlockResolvedRtl(blockIndex);
    final visibleText = StylingService.stripTags(controller.text);
    final visibleLength = visibleText.length;
    final safeRaw = rawOffset.clamp(0, controller.text.length).toInt();
    final visibleOffset = MarkupController.rawToVisualOffset(
      controller.text,
      safeRaw,
    ).clamp(0, visibleLength).toInt();
    final atVisibleStart = visibleOffset <= 0;
    final atVisibleEnd = visibleOffset >= visibleLength;

    if (!isRtl) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (!atVisibleStart) return null;
        if (blockIndex <= 0) return null;
        return (
          block: blockIndex - 1,
          offset:
              MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
        );
      }
      if (!atVisibleEnd) return null;
      if (blockIndex >= _controllers.length - 1) return null;
      return (block: blockIndex + 1, offset: 0);
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!atVisibleEnd) return null;
      if (blockIndex >= _controllers.length - 1) return null;
      return (block: blockIndex + 1, offset: 0);
    }
    if (!atVisibleStart) return null;
    if (blockIndex <= 0) return null;
    return (
      block: blockIndex - 1,
      offset: MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
    );
  }

  KeyEventResult? _handleHorizontalArrowKey({
    required LogicalKeyboardKey key,
    required MarkupController controller,
    required int blockIndex,
    required bool isRtl,
    required TextSelection selection,
    required int textLength,
    required bool manualInBlock,
  }) {
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return null;
    }

    if (!selection.isCollapsed) {
      if (!isRtl) return KeyEventResult.ignored;
      final offset = key == LogicalKeyboardKey.arrowLeft
          ? selection.end.clamp(0, textLength).toInt()
          : selection.start.clamp(0, textLength).toInt();
      controller.selection = TextSelection.collapsed(offset: offset);
      return KeyEventResult.handled;
    }

    final keyboard = HardwareKeyboard.instance;
    if (!isRtl) {
      final plainArrow = _isPlainArrowModifierState(keyboard);
      if (plainArrow) {
        final bookmarkTarget = _leadingBookmarkPlainHorizontalTarget(
          blockIndex: blockIndex,
          rawOffset: selection.baseOffset,
          key: key,
        );
        if (bookmarkTarget != null) {
          controller.selection =
              TextSelection.collapsed(offset: bookmarkTarget.offset);
          return KeyEventResult.handled;
        }
      }
      if (!plainArrow) {
        if (_isControlArrowModifierState(keyboard, allowShift: false)) {
          final boundaryTarget = _ltrControlHorizontalBoundaryTarget(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
          );
          if (boundaryTarget == null) return KeyEventResult.ignored;
          _crossToBlock(boundaryTarget.block, atOffset: boundaryTarget.offset);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final boundaryTarget = _horizontalBoundaryTargetFromPosition(
        blockIndex: blockIndex,
        rawOffset: selection.baseOffset,
        key: key,
      );
      if (boundaryTarget == null) return KeyEventResult.ignored;
      _crossToBlock(boundaryTarget.block, atOffset: boundaryTarget.offset);
      return KeyEventResult.handled;
    }

    final target = _isControlArrowModifierState(keyboard)
        ? _controlHorizontalWordTarget(
            blockIndex: blockIndex,
            rawOffset: selection.baseOffset,
            key: key,
          )
        : _isAltArrowModifierState(keyboard)
            ? _altHorizontalTarget(
                blockIndex: blockIndex,
                rawOffset: selection.baseOffset,
                key: key,
              )
            : _horizontalTargetFromPosition(
                blockIndex: blockIndex,
                rawOffset: selection.baseOffset,
                key: key,
                allowInBlockStep: manualInBlock,
              );
    if (target == null) {
      return isRtl ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (target.block != blockIndex) {
      _crossToBlock(target.block, atOffset: target.offset);
      return KeyEventResult.handled;
    }
    controller.selection = TextSelection.collapsed(offset: target.offset);
    return KeyEventResult.handled;
  }

  ({int block, int offset})? _leadingBookmarkPlainHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    if (!text.startsWith(_keyboardBookmarkSign)) return null;
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    final afterLeadingBookmarks = _firstRawOffsetAfterLeadingBookmarkCluster(
      text,
    );
    if (key == LogicalKeyboardKey.arrowRight &&
        safeRaw < afterLeadingBookmarks) {
      return (block: blockIndex, offset: afterLeadingBookmarks);
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        safeRaw > 0 &&
        safeRaw <= afterLeadingBookmarks) {
      return (block: blockIndex, offset: 0);
    }
    return null;
  }

  int _firstRawOffsetAfterLeadingBookmarkCluster(String text) {
    var offset = 0;
    var moved = true;
    while (moved && offset < text.length) {
      moved = false;
      while (offset < text.length && text[offset] == _keyboardBookmarkSign) {
        offset++;
        moved = true;
      }
      final tagMatch = MarkupDecorationParser.tagRegex.matchAsPrefix(
        text,
        offset,
      );
      if (tagMatch != null && tagMatch.start == offset) {
        offset = tagMatch.end;
        moved = true;
      }
    }
    return offset;
  }

  ({int block, int offset})? _ltrControlHorizontalBoundaryTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    // Native EditableText keeps normal LTR word jumps inside the block. This
    // helper only catches cross-block movement after hidden tags/bookmarks are
    // removed from the boundary calculation.
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final navigationText = _keyboardNavigationText(text);
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    final navigationOffset =
        _keyboardRawToNavigationOffset(text, safeRaw).clamp(
      0,
      navigationText.length,
    );
    final navigationEnd = _keyboardNavigationSafeEndOffset(text);
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (navigationOffset > 0) return null;
      if (blockIndex <= 0) return null;
      return (
        block: blockIndex - 1,
        offset:
            MarkupController.safeEndOffset(_controllers[blockIndex - 1].text),
      );
    }
    if (navigationOffset < navigationEnd) return null;
    if (blockIndex >= _controllers.length - 1) return null;
    return (block: blockIndex + 1, offset: 0);
  }

  /// Moves focus and the caret to [targetIdx]. Updates `_lastFocusedController`
  /// SYNCHRONOUSLY before requesting focus, so the very next KeyRepeatEvent
  /// finds the correct controller — without that sync update, a long-press
  /// can stall at a paragraph boundary because the FocusNode listener that
  /// updates `_lastFocusedController` only fires on the next microtask.
  ///
  /// Provide either [atOffset] (exact char offset) or [x] (preserve x-position
  /// across vertical jumps) + [atEnd] (true = bottom line, false = top line).
  void _crossToBlock(int targetIdx, {int? atOffset, double? x, bool? atEnd}) {
    if (targetIdx < 0 || targetIdx >= _controllers.length) return;
    _lastFocusedController = _controllers[targetIdx];
    _focusNodes[targetIdx].requestFocus();
    final text = _controllers[targetIdx].text;
    int offset;
    if (atOffset != null) {
      final raw = atOffset.clamp(0, text.length);
      // When entering a block at the END (arrowLeft cross-block), walk backward
      // past any trailing invisible tags so the cursor isn't trapped just after a
      // tag's end where MarkupController would snap it back on every arrowLeft.
      offset = (atOffset >= text.length)
          ? MarkupController.safeEndOffset(text)
          : raw;
    } else if (x != null) {
      final layout = _getVerticalLayout(targetIdx);
      offset = layout.getPositionAtX(
        x,
        fromBottom: atEnd ?? false,
        rawText: text,
      );
    } else {
      final raw = atEnd == true ? text.length : 0;
      offset = atEnd == true ? MarkupController.safeEndOffset(text) : raw;
    }
    _controllers[targetIdx].selection = TextSelection.collapsed(offset: offset);
    _lastArrowDecision = 'cross block $targetIdx:$offset';
    _scrollEditorBlockIntoView(targetIdx);
  }
}
