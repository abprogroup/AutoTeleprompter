import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../models/cursor_style.dart';
import '../models/editor_state.dart';
import './editor/editor_dialogs.dart';
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
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_screen.dart';
import '../../teleprompter/widgets/content_creator_screen.dart';
import '../../teleprompter/widgets/teleprompter_screen.dart';
import '../models/script_word.dart';
import '../services/styling_service.dart';
import '../services/script_bookmark_service.dart';
import '../../../core/services/rich_clipboard.dart';
import '../services/docx_service.dart';
import '../services/rtf_service.dart';
import '../services/odt_service.dart';
import '../services/pages_service.dart';
import '../services/pdf_export_service.dart';
import '../services/markup_export_service.dart';
import '../services/markup_decoration_service.dart';
import '../services/editor_font_service.dart';
import '../services/editor_text_geometry_service.dart';
import '../../teleprompter/services/word_aligner.dart';
import '../../../platform/file_import/platform_file_import.dart';
import '../../../platform/keyboard/platform_keyboard.dart';

part 'script_editor_screen.load_blocks.dart';
part 'script_editor_screen.vertical_layout.dart';
part 'script_editor_screen.dialogs_history.dart';
part 'script_editor_screen.styling_commands.dart';
part 'script_editor_screen.file_present.dart';
part 'script_editor_screen.build.dart';
part 'script_editor_screen.selection_clipboard.dart';
part 'script_editor_screen.selection_clipboard_commands.dart';
part 'script_editor_screen.selection_clipboard_paste.dart';
part 'script_editor_screen.editor_block.dart';
part 'script_editor_screen.render_decorations.dart';
part 'script_editor_screen.bookmarks.dart';
part 'script_editor_screen.search.dart';
part 'script_editor_screen.keyboard_navigation.dart';
part 'script_editor_screen.keyboard_selection.dart';
part 'script_editor_screen.keyboard_vertical.dart';
part 'script_editor_screen.keyboard_horizontal.dart';
part 'script_editor_screen.keyboard_bookmarks.dart';
part 'script_editor_screen.keyboard_focus.dart';
part 'script_editor_screen.selection_trace_stub.dart';
part 'script_editor_screen.arrow_trace_stub.dart';

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

enum _BlockClipboardKind {
  partialSelection,
  fullScript,
}

class ScriptEditorScreen extends ConsumerStatefulWidget {
  final bool shouldAutoLoad;
  final File? pendingFile;
  const ScriptEditorScreen(
      {super.key, this.shouldAutoLoad = false, this.pendingFile});

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

const String _keyboardBookmarkSign = '\u00BB';

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen>
    with StylingLogicMixin<ScriptEditorScreen>, WidgetsBindingObserver {
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
  String _currentTitle = 'New Project';
  static final _arrowKeyDummyNode = FocusNode();

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

  bool _isInit = false;
  bool _isCleaning = false; // v3.9.5.1: Suppression flag
  bool _isGlobalSelection = false; // v3.9.5.1: Broadcast mode
  bool _isSuiteDirty = false;
  bool _isCommandExecuting = false;
  bool _isDirty = false;
  bool _isLoading = false;
  List<String>? _blockClipboard; // raw markup per block, written by Cut/Copy
  _BlockClipboardKind _blockClipboardKind =
      _BlockClipboardKind.partialSelection;
  String? _plainBlockClipboardText;
  List<String>? _globalSelectionSnapshot;
  DateTime? _globalSelectionSnapshotAt;
  DateTime? _globalSelectionLockUntil;
  String _selectionClipboardDebug = 'idle';
  String _selectionCommandDebug = 'idle';
  _BlockSelectionRange? _recognizedBlockRange;
  String _recognizedBlockRangeDebug = 'idle';
  Timer? _blockClipboardTimer;
  String? _bookmarkScopeKey;
  String? _bookmarkLoadingKey;
  bool _bookmarksLoaded = false;
  List<ScriptBookmark> _bookmarks = const [];
  bool _searchDialogOpen = false;
  String _lastSearchQuery = '';
  bool _editorSearchToolbarVisible = false;
  List<_EditorSearchMatch> _editorSearchMatches = const [];
  int _editorSearchMatchIndex = -1;
  String _lastArrowDecision = 'idle';
  String? _activeArrowEventSignature;
  String? _suppressDuplicateArrowEventSignature;
  String? _handledShiftSelectionEventSignature;
  int _keyboardFocusRepairToken = 0;
  double? _verticalArrowPreferredX;
  SelectionEndpoint? _shiftSelectionAnchor;
  SelectionEndpoint? _shiftSelectionFocus;
  bool _searchWholeWord = false;
  bool _isPendingLoad = false;
  EditorSuite _activeSuite = EditorSuite.none;
  bool _keyboardDismissedForSelection = false;
  Timer? _historyTimer, _recentTimer, _autoSaveTimer;
  Timer? _mobileSelectionRefreshTimer;

  // v3.9.6: Professional History Bulking
  int _typingCharCount = 0; // chars typed since last history commit
  Timer? _typingBulkTimer; // 10-second typing bulk window
  Timer? _suiteAutoSaveTimer; // 3-second auto-checkpoint while suite is open
  String?
      _suiteSection; // current function section within a suite (e.g. 'Bold', 'Font Size')
  final GlobalKey<GlobalSelectionOverlayState> _overlayKey =
      GlobalKey<GlobalSelectionOverlayState>();

  void _setEditorState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
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
  void reassemble() {
    super.reassemble();
    _resetArrowTraceSession('hot reload');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _didChangeDependenciesScriptEditorBody();
  }

  MarkupController? get _activeController {
    for (var i = 0; i < _focusNodes.length; i++) {
      if (_focusNodes[i].hasFocus) return _controllers[i];
    }
    return _lastFocusedController ??
        (_controllers.isNotEmpty ? _controllers.last : null);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleMobileSelectionGeometryRefresh();
  }

  void _scheduleMobileSelectionGeometryRefresh() {
    void refresh() {
      if (!mounted) return;
      ContextMenuController.removeAny();
      _overlayKey.currentState?.refreshPositions();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
    _mobileSelectionRefreshTimer?.cancel();
    _mobileSelectionRefreshTimer =
        Timer(const Duration(milliseconds: 260), refresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onGlobalArrowKey);
    _mobileSelectionRefreshTimer?.cancel();
    _disposeScriptEditorScreenBody();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildScriptEditorScreen(context);
}
