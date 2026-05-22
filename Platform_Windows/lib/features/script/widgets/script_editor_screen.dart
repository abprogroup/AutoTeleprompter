import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
part 'script_editor_screen.vertical_layout.dart';
part 'script_editor_screen.dialogs_history.dart';
part 'script_editor_screen.styling_commands.dart';
part 'script_editor_screen.file_present.dart';
part 'script_editor_screen.debug_bookmarks_search.dart';
part 'script_editor_screen.bookmarks.dart';
part 'script_editor_screen.search.dart';
part 'script_editor_screen.editor_block.dart';
part 'script_editor_screen.build.dart';
part 'script_editor_screen.arrow_trace.dart';
part 'script_editor_screen.highlight_trace.dart';
part 'script_editor_screen.keyboard_navigation.dart';
part 'script_editor_screen.keyboard_selection.dart';
part 'script_editor_screen.keyboard_vertical.dart';
part 'script_editor_screen.keyboard_horizontal.dart';
part 'script_editor_screen.keyboard_focus.dart';

// v3.9.5.59: Absolute Atomic Coordinator
// â”€â”€ Switchboard Orchestrator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  const ScriptEditorScreen({
    super.key,
    this.shouldAutoLoad = false,
    this.pendingFile,
  });

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

const String _keyboardBookmarkSign = '\u00BB';

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen>
    with WidgetsBindingObserver, StylingLogicMixin<ScriptEditorScreen> {
  // Dummy node for HardwareKeyboard â†’ _handleEditorArrowKey bridge
  // (_handleEditorArrowKey never uses the node parameter).
  static final _arrowKeyDummyNode = FocusNode();
  // â”€â”€ Mixin Implementation for StylingLogicMixin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€ State Members â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final List<MarkupController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  final List<GlobalKey> _blockKeys = [];
  final ScrollController _editorScrollController = ScrollController();
  final GlobalKey _editorArrowTraceBoundaryKey = GlobalKey();
  double? _editorScrollOffsetBeforeWindowHide;
  String _currentTitle = 'New Project';

  TextSelection? _lastSelection;

  /// Preserved non-collapsed selection â€” survives focus loss from dialogs.
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
  String _lastArrowTrace = 'No arrow trace captured yet.';
  String? _lastArrowTraceScreenshotPath;
  String? _lastArrowTraceLogPath;
  String _lastHighlightTrace = 'No highlight trace captured yet.';
  String? _lastHighlightTraceScreenshotPath;
  String? _lastHighlightTraceLogPath;
  int _highlightTraceSequence = 0;
  Timer? _highlightTraceTimer;
  int _arrowTraceSequence = 0;
  String _arrowTraceSessionId = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
  bool _debugSentryCollapsed = false;
  String? _activeArrowEventSignature;
  String? _suppressDuplicateArrowEventSignature;
  int _keyboardFocusRepairToken = 0;
  double? _verticalArrowPreferredX;
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
        c.externalVisibleSelection = null;
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
          c.externalVisibleSelection = null;
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
  void reassemble() {
    super.reassemble();
    _resetArrowTraceSession('hot reload');
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_forceRecentUpdate());
      });
      unawaited(_loadBookmarksForCurrentScript());
      // Migrate old metadata-only bookmarks â†’ insert Â» signs into text.
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
    _highlightTraceTimer?.cancel();
    _editorScrollController.dispose();
    _clearControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildEditorScreen(context);
}
