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
import '../../../core/services/rich_clipboard.dart';
import '../services/docx_service.dart';
import '../services/rtf_service.dart';
import '../services/pages_service.dart';
import '../../../platform/file_import/platform_file_import.dart';
import '../../../platform/keyboard/platform_keyboard.dart';

// v3.9.5.59: Absolute Atomic Coordinator
// ── Switchboard Orchestrator ──────────────────────────────────────────────────

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class ScriptEditorScreen extends ConsumerStatefulWidget {
  final bool shouldAutoLoad;
  final File? pendingFile;
  const ScriptEditorScreen({super.key, this.shouldAutoLoad = false, this.pendingFile});

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen> with StylingLogicMixin<ScriptEditorScreen> {
  // ── Mixin Implementation for StylingLogicMixin ────────────────────────────
  @override
  List<MarkupController> get controllers => _controllers;
  @override
  MarkupController? get activeController => _lastFocusedController ?? (_controllers.isNotEmpty ? _controllers[0] : null);
  @override
  bool get isGlobalSelection => _isGlobalSelection;
  @override
  set isGlobalSelection(bool value) => setState(() => _isGlobalSelection = value);
  @override
  bool get isCleaning => _isCleaning;
  @override
  set isCleaning(bool value) => setState(() => _isCleaning = value);
  @override
  void saveHistory({required String description, bool debounce = true}) => _saveHistory(description: description, debounce: debounce);

  // ── State Members ──────────────────────────────────────────────────────────
  final List<MarkupController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  final List<GlobalKey> _blockKeys = [];
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

  // v3.9.6: Professional History Bulking
  int _typingCharCount = 0;         // chars typed since last history commit
  Timer? _typingBulkTimer;          // 10-second typing bulk window
  Timer? _suiteAutoSaveTimer;       // 3-second auto-checkpoint while suite is open
  String? _suiteSection;            // current function section within a suite (e.g. 'Bold', 'Font Size')
  final GlobalKey<GlobalSelectionOverlayState> _overlayKey = GlobalKey<GlobalSelectionOverlayState>();

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

  Future<void> _runPendingFileLoad(File file) async {
    try {
      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
      final result = await ref.read(scriptProvider.notifier).parseFile(file);
      final String content = result.text;
      final String title = file.path.split('/').last;

      // Conflict Detection Logic
      String? existingMeta;
      final List<String> recentScripts = ref.read(settingsProvider).recentScripts;
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
        final String existingContent = decoded['fullText'] ?? '';
        final String sessionId = decoded['sessionId'];
        final String type = decoded['type'] ?? 'TXT';

        if (normalize(existingContent) == normalizedNew) {
          finalContent = existingContent;
          finalType = type;
          finalSessionId = sessionId;
          finalHistoryJson = decoded['historyJson'];
        } else {
          if (!mounted) return;
          final choice = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFFBF00), size: 22),
                SizedBox(width: 10),
                Text("Conflict Detected", style: TextStyle(color: Colors.white, fontSize: 17)),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('"$title" is already in your Recents.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('The version on your disk is different from the version in your history. What do you want to do?', style: TextStyle(color: Colors.white70)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text("KEEP HISTORY", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'reload'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFBF00), foregroundColor: Colors.black),
                  child: const Text("RELOAD & DISCARD EDITS", style: TextStyle(fontWeight: FontWeight.bold)),
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
            finalHistoryJson = decoded['historyJson'];
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
      if (mounted) setState(() => _isPendingLoad = false);
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      final text = _getRefinedFullText();
      if (text.isEmpty && _currentTitle == 'New Project') return;
      try { _forceRecentUpdate(); } catch (_) {}
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
      if (script != null && script.historyIndex >= 0 && script.historyIndex < _history.length) {
        _historyIndex = script.historyIndex;
        final s = _history[_historyIndex];
        _loadText(s.text);
        Future.microtask(() { if (mounted) _applySettingsFromState(s); });
      } else if (_history.isNotEmpty) {
        _historyIndex = _history.length - 1;
        final s = _history.last;
        _loadText(s.text);
        Future.microtask(() { if (mounted) _applySettingsFromState(s); });
      } else {
        _saveHistory(description: 'Initial Load');
      }
      _forceRecentUpdate();
    }
  }



  void _clearControllers() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _controllers.clear();
    _focusNodes.clear();
    _blockKeys.clear();
  }

  void _addBlock(int index, {String text = ''}) {
    setState(() {
      final controller = MarkupController(text: text);
      final blockKey = GlobalKey(); // v3.9.5.66
      
      final node = FocusNode(onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
          final currentText = controller.text;
          final sel = controller.selection;
          String p1 = currentText, p2 = '';
          if (sel.isValid) {
            final splits = StylingService.splitBlock(currentText, sel.start);
            p1 = splits[0];
            p2 = splits[1];
            controller.text = p1;
          }
          setState(() {
            final idx = _controllers.indexOf(controller);
            _addBlock(idx + 1, text: p2);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && idx + 1 < _focusNodes.length) {
                _focusNodes[idx + 1].requestFocus();
                _controllers[idx + 1].selection = const TextSelection.collapsed(offset: 0);
              }
            });
          });
          _saveHistory(description: 'Split Paragraph');
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace && controller.text.isEmpty) {
          final idx = _controllers.indexOf(controller);
          if (_controllers.length > 1 && idx != -1) {
            setState(() {
              _controllers.removeAt(idx).dispose();
              _focusNodes.removeAt(idx).dispose();
              _blockKeys.removeAt(idx);
              if (idx > 0) _focusNodes[idx - 1].requestFocus();
            });
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      });
      
      node.addListener(() {
        if (node.hasFocus) { _lastFocusedController = controller; _onSelectionChanged(); }
        else if (_isDirty && !_isCommandExecuting) {
          // Flush any pending typing bulk on focus loss
          if (_typingCharCount > 0) {
            _commitHistory('Edit Text');
          }
          _isDirty = false;
        }
      });

      String lastText = text;
      controller.addListener(() {
        if (_isLoading) return;
        if (controller.text == lastText) {
          if (node.hasFocus) {
            _lastSelection = controller.selection;
            if (!controller.selection.isCollapsed) {
              _preservedSelection = controller.selection;
            }
            _onSelectionChanged();
            // Escalate native full-block select to global Select All.
            // Catches all paths: context menu, keyboard, platform menu.
            // Skip when overlay has active handles (refine mode) to avoid
            // infinite loop: refine clears isGlobal → escalation re-selects → loop.
            final overlayActive = _overlayKey.currentState?.hasSelection ?? false;
            if (!_isGlobalSelection &&
                !_isCommandExecuting &&
                !overlayActive &&
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
        // v4.1.2: When the user edits text (not inside a style command), clear
        // any pinned externalSelection so stale amber doesn't linger after typing.
        if (!_isCommandExecuting && controller.externalSelection != null) {
          controller.externalSelection = null;
          controller.refresh();
        }
        _onBlockChanged();
      });

      _controllers.insert(index, controller);
      _focusNodes.insert(index, node);
      _blockKeys.insert(index, blockKey);
    });
    
    if (text.isEmpty) {
      Future.delayed(Duration.zero, () => _focusNodes[index].requestFocus());
    }
  }

  void _removeBlock(int index) {
    if (_controllers.length <= 1) return;
    setState(() {
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
      _clearControllers();
      final paragraphs = text.split('\n');
      for (int i = 0; i < paragraphs.length; i++) _addBlock(i, text: paragraphs[i]);
      if (_controllers.isEmpty) _addBlock(0);
    } finally {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _isLoading = false;
      });
    }
    // Sync toolbar state after load. Non-empty blocks don't auto-request focus,
    // so _onSelectionChanged never fires — cursorStyleProvider stays at its
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
        // or drag is in progress), do NOT clear — focus events fire before
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
          textColor: _detectColorAtCursor(textColor: true),
          highlightColor: _detectColorAtCursor(textColor: false),
        );
        ref.read(cursorStyleProvider.notifier).state = styles;
      });
    }
  }

  void _scheduleRecentUpdate() {
    _recentTimer?.cancel();
    _recentTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _forceRecentUpdate();
    });
  }

  Future<void> _forceRecentUpdate() async {
    _recentTimer?.cancel();
    final text = _getRefinedFullText();
    if (text.trim().isEmpty) return;
    final settings = ref.read(settingsProvider);
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
      historyJson: jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }

  void _onBlockChanged() {
    if (_isCleaning || _isCommandExecuting) return;
    _saveHistory(description: 'Edit Text', debounce: true);
    _scheduleRecentUpdate();
  }

  Color? _detectColorAtCursor({required bool textColor, int? offset}) {
    final controller = _activeController;
    if (controller == null) return null;
    final text = controller.text;
    final off = offset ?? controller.selection.start;
    final tag = textColor ? '[color=' : '[bg=';
    final closeTag = textColor ? '[/color]' : '[/bg]';
    final matches = RegExp(RegExp.escape(tag) + r'([^\]]+)\]').allMatches(text);
    Color? found;
    for (final m in matches) {
      if (m.start <= off) {
         final nextClose = text.indexOf(closeTag, m.end);
         if (nextClose == -1 || nextClose >= off) {
            final hex = m.group(1)!.trim().replaceFirst('#', '');
            found = Color(int.tryParse('FF$hex', radix: 16) ?? (textColor ? 0xFFFFFFFF : 0x00000000));
         }
      }
    }
    return found ?? const Color(0x00000000);
  }

  String _detectAlignAtCursor({int? offset}) {
    final controller = _activeController;
    if (controller == null) return 'left';
    final text = controller.text;
    // Clamp to 0 when selection is invalid (e.g. focus moved to layout suite).
    // Alignment tags always wrap from position 0 so scanning at 0 is correct.
    final rawOff = offset ?? controller.selection.baseOffset;
    final off = rawOff.clamp(0, text.isEmpty ? 0 : text.length);
    final alignMatches = RegExp(r'\[(?:align=)?(center|left|right)\]').allMatches(text);
    final dirMatches = RegExp(r'\[(rtl|ltr)\]').allMatches(text);
    String found = 'left';
    for (final m in alignMatches) {
      if (m.start <= off) {
        final val = m.group(1)!;
        // Use the correct close tag depending on whether the opening was
        // old-format [right] or new-format [align=right].
        final isNewFormat = m.group(0)!.startsWith('[align=');
        final closeTag = isNewFormat ? '[/align=$val]' : '[/$val]';
        final nextClose = text.indexOf(closeTag, m.end);
        if (nextClose == -1 || nextClose >= off) found = val;
      }
    }
    if (found == 'left') {
       for (final m in dirMatches) {
          if (m.start <= off) {
             final nextClose = text.indexOf('[/${m.group(1)}]', m.end);
             if (nextClose == -1 || nextClose >= off) if (m.group(1) == 'rtl') found = 'right';
          }
       }
    }
    // Mirror the editor's own auto-RTL rule: if no explicit tag was found but
    // the text is predominantly Hebrew, treat it as right-aligned.
    if (found == 'left' && text.isHebrew) found = 'right';
    return found;
  }

  bool _detectStyleAtCursor(String open, String close, {int? offset}) {
    final controller = _activeController;
    if (controller == null) return false;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final mid = (start + (end - start) / 2).floor().clamp(0, text.length);
    bool isPointActive(int off) => _detectStyleAtPoint(text, selection, off, open, close);
    if (selection.isCollapsed) return isPointActive(selection.baseOffset);
    return isPointActive(start) || isPointActive(end) || isPointActive(mid);
  }

  int _detectIntAtCursor(String prefix, int defaultValue) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final selection = controller.selection;
    int valAtPoint(int off) => _detectIntAtPoint(text, selection, off, prefix, defaultValue);
    if (selection.isCollapsed) return valAtPoint(selection.baseOffset);
    final mid = (selection.start + (selection.end - selection.start) / 2).floor().clamp(0, text.length);
    final vMid = valAtPoint(mid);
    if (vMid != defaultValue) return vMid;
    return valAtPoint(selection.start);
  }

  String _detectStringAtCursor(String prefix, String defaultValue) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final selection = controller.selection;
    String valAtPoint(int off) => _detectStringAtPoint(text, selection, off, prefix, defaultValue);
    if (selection.isCollapsed) return valAtPoint(selection.baseOffset);
    final mid = (selection.start + (selection.end - selection.start) / 2).floor().clamp(0, text.length);
    final vMid = valAtPoint(mid);
    if (vMid != defaultValue) return vMid;
    return valAtPoint(selection.start);
  }

  bool _detectStyleAtPoint(String text, TextSelection selection, int off, String open, String close) {
      if (off < 0 || off > text.length) return false;
      bool check(int p) {
        if (p < 0 || p > text.length) return false;
        if (open == '**' && close == '**') {
          final subText = text.substring(0, p);
          final count = RegExp(r'\*\*').allMatches(subText).length;
          return count % 2 != 0;
        }
        final tagIdx = text.lastIndexOf(open, p);
        if (tagIdx == -1) return false;
        final exitIdx = text.indexOf(close, tagIdx + open.length);
        return exitIdx != -1 && exitIdx >= p;
      }
      // Check at cursor, one back, and several nearby positions to handle
      // landing on invisible tag characters (fontSize: 0.1 in MarkupController)
      if (check(off)) return true;
      for (int delta = 1; delta <= open.length + 2; delta++) {
        if (off - delta >= 0 && check(off - delta)) return true;
        if (off + delta <= text.length && check(off + delta)) return true;
      }
      return false;
  }

  int _detectIntAtPoint(String text, TextSelection selection, int off, String prefix, int defaultValue) {
      final openTag = '[' + prefix;
      int check(int p) {
        if (p < 0 || p > text.length) return defaultValue;
        final tagIdx = text.lastIndexOf(openTag, p);
        if (tagIdx == -1) return defaultValue;
        final closeBracket = text.indexOf(']', tagIdx);
        if (closeBracket == -1 || closeBracket > p) return defaultValue;
        final tagName = prefix.split('=').first;
        final closeTag = '[/' + tagName + ']';
        final exitIdx = text.indexOf(closeTag, tagIdx);
        if (exitIdx != -1 && exitIdx < p) return defaultValue;
        if (exitIdx == -1) return defaultValue;
        return int.tryParse(text.substring(tagIdx + openTag.length, closeBracket)) ?? defaultValue;
      }
      final atBoundary = check(off);
      if (atBoundary != defaultValue) return atBoundary;
      // Search nearby positions to handle cursor landing on tag characters
      for (int delta = 1; delta <= openTag.length + 2; delta++) {
        if (off - delta >= 0) { final v = check(off - delta); if (v != defaultValue) return v; }
        if (off + delta <= text.length) { final v = check(off + delta); if (v != defaultValue) return v; }
      }
      return defaultValue;
  }

  String _detectStringAtPoint(String text, TextSelection selection, int off, String prefix, String defaultValue) {
      final openTag = '[' + prefix;
      String check(int p) {
        if (p < 0 || p > text.length) return defaultValue;
        final tagIdx = text.lastIndexOf(openTag, p);
        if (tagIdx == -1) return defaultValue;
        final closeBracket = text.indexOf(']', tagIdx);
        if (closeBracket == -1 || closeBracket > p) return defaultValue;
        final tagName = prefix.split('=').first;
        final closeTag = '[/' + tagName + ']';
        final exitIdx = text.indexOf(closeTag, tagIdx);
        if (exitIdx != -1 && exitIdx < p) return defaultValue;
        if (exitIdx == -1) return defaultValue;
        return text.substring(tagIdx + openTag.length, closeBracket);
      }
      final atBoundary = check(off);
      if (atBoundary != defaultValue) return atBoundary;
      // Search nearby positions to handle cursor landing on tag characters
      for (int delta = 1; delta <= openTag.length + 2; delta++) {
        if (off - delta >= 0) { final v = check(off - delta); if (v != defaultValue) return v; }
        if (off + delta <= text.length) { final v = check(off + delta); if (v != defaultValue) return v; }
      }
      return defaultValue;
  }

  @override
  void dispose() {
    _historyTimer?.cancel(); _recentTimer?.cancel(); _autoSaveTimer?.cancel(); _typingBulkTimer?.cancel(); _suiteAutoSaveTimer?.cancel();
    _clearControllers(); super.dispose();
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _currentTitle);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Rename Production', style: TextStyle(color: Colors.white)),
      content: TextField(controller: controller, autofocus: true, style: const TextStyle(color: Colors.white)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () {
          final newName = controller.text.trim();
          if (newName.isNotEmpty) {
            setState(() => _currentTitle = newName);
            _forceRecentUpdate();
            Navigator.pop(ctx);
          }
        }, child: const Text('Rename', style: TextStyle(color: Color(0xFFFFBF00)))),
      ],
    ));
  }

  String _getRefinedFullText() => _controllers.map((c) => c.text).join('\n').trim();

  /// Clear style at cursor: find the word at cursor, then strip all tags from
  /// just that word — surgically splitting any enclosing styled regions so the
  /// rest of the text keeps its styling.
  void _clearStyleAtCursor(MarkupController c, int cursor) {
    final text = c.text;
    final tagPattern = RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');

    // Step 1: Find the word boundaries at cursor (skipping over tag characters)
    // Walk left to find word start, walk right to find word end,
    // jumping over any tag sequences encountered.
    int wordStart = cursor;
    int wordEnd = cursor;

    // Walk left
    while (wordStart > 0) {
      final prev = wordStart - 1;
      // Check if we're at the end of a tag — skip over it
      bool skippedTag = false;
      for (final m in tagPattern.allMatches(text)) {
        if (m.end == wordStart) {
          wordStart = m.start;
          skippedTag = true;
          break;
        }
      }
      if (skippedTag) continue;
      // Check if previous char is a space/newline
      final ch = text[prev];
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
      wordStart = prev;
    }

    // Walk right
    while (wordEnd < text.length) {
      // Check if we're at the start of a tag — skip over it
      bool skippedTag = false;
      for (final m in tagPattern.allMatches(text)) {
        if (m.start == wordEnd) {
          wordEnd = m.end;
          skippedTag = true;
          break;
        }
      }
      if (skippedTag) continue;
      final ch = text[wordEnd];
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
      wordEnd++;
    }

    if (wordStart >= wordEnd) return;

    // Step 2: Strip tags inside the word range
    final before = text.substring(0, wordStart);
    final wordContent = text.substring(wordStart, wordEnd);
    final after = text.substring(wordEnd);
    final cleanWord = wordContent.replaceAll(tagPattern, '');

    // Step 3: Rebuild text with clean word
    String result = before + cleanWord + after;
    int newCursor = (cursor - (wordEnd - wordStart - cleanWord.length)).clamp(0, result.length);
    // Adjust cursor: it was relative to old text, account for removed tags before cursor
    final tagsBeforeCursor = tagPattern.allMatches(wordContent.substring(0, (cursor - wordStart).clamp(0, wordContent.length)));
    int removedBefore = 0;
    for (final m in tagsBeforeCursor) {
      removedBefore += m.end - m.start;
    }
    newCursor = (cursor - removedBefore).clamp(0, result.length);

    // Step 4: Split any enclosing tags that wrap over the word boundaries
    // so surrounding text keeps its style.
    final wordStartInResult = wordStart;
    final wordEndInResult = wordStart + cleanWord.length;
    result = _splitAllEnclosingStyles(result, wordStartInResult, wordEndInResult, tagPattern);

    // Reclamp cursor
    newCursor = newCursor.clamp(0, result.length);

    c.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Split ALL enclosing style tag pairs around a range, so the range loses
  /// styling but surrounding text keeps it.
  String _splitAllEnclosingStyles(String text, int start, int end, RegExp tagPattern) {
    final families = <String, List<String>>{
      'bold': ['**', '**'],
      'underline': ['[u]', '[/u]'],
      'italic': ['[i]', '[/i]'],
    };
    final paramFamilies = ['color', 'bg', 'size', 'font', 'align'];

    String current = text;
    int curStart = start;
    int curEnd = end;

    for (final entry in families.entries) {
      final result = _splitEnclosingStyle(current, curStart, curEnd, entry.value[0], entry.value[1]);
      if (result != null) {
        current = result[0] as String;
        curStart = result[1] as int;
        curEnd = result[2] as int;
      }
    }
    for (final family in paramFamilies) {
      final openPattern = RegExp(r'\[' + family + r'=[^\]]+\]');
      final close = '[/$family]';
      for (final m in openPattern.allMatches(current)) {
        if (m.start <= curStart) {
          final closeIdx = current.indexOf(close, m.end);
          if (closeIdx != -1 && closeIdx >= curEnd) {
            final result = _splitEnclosingStyle(current, curStart, curEnd, current.substring(m.start, m.end), close);
            if (result != null) {
              current = result[0] as String;
              curStart = result[1] as int;
              curEnd = result[2] as int;
            }
            break;
          }
        }
      }
    }
    return current;
  }

  /// Find enclosing open/close pair around a midpoint. Returns [openStart, openEnd, closeStart, closeEnd] or null.
  List<int>? _findEnclosingPair(String text, int cursor, String open, String close) {
    if (open == '**' && close == '**') {
      final matches = RegExp(r'\*\*').allMatches(text).toList();
      for (int i = 0; i < matches.length - 1; i += 2) {
        final oStart = matches[i].start;
        final oEnd = matches[i].end;
        if (i + 1 < matches.length) {
          final cStart = matches[i + 1].start;
          final cEnd = matches[i + 1].end;
          if (oEnd <= cursor && cStart >= cursor) {
            return [oStart, oEnd, cStart, cEnd];
          }
        }
      }
      return null;
    }
    int searchFrom = cursor;
    while (searchFrom >= 0) {
      final idx = text.lastIndexOf(open, searchFrom);
      if (idx == -1) return null;
      final closeIdx = text.indexOf(close, idx + open.length);
      if (closeIdx != -1 && closeIdx >= cursor) {
        return [idx, idx + open.length, closeIdx, closeIdx + close.length];
      }
      searchFrom = idx - 1;
    }
    return null;
  }

  /// Split an enclosing style around a range: keep style on before/after, remove from range.
  List<Object>? _splitEnclosingStyle(String text, int selStart, int selEnd, String open, String close) {
    final pair = _findEnclosingPair(text, (selStart + selEnd) ~/ 2, open, close);
    if (pair == null) return null;
    final oStart = pair[0], oEnd = pair[1], cStart = pair[2], cEnd = pair[3];

    // Don't split if range covers the full styled content
    if (selStart <= oEnd && selEnd >= cStart) return null;

    final before = text.substring(oEnd, selStart);
    final selected = text.substring(selStart, selEnd);
    final after = text.substring(selEnd, cStart);

    final buf = StringBuffer();
    buf.write(text.substring(0, oStart));
    if (before.isNotEmpty) {
      buf.write(open);
      buf.write(before);
      buf.write(close);
    }
    final newSelStart = buf.length;
    buf.write(selected);
    final newSelEnd = buf.length;
    if (after.isNotEmpty) {
      buf.write(open);
      buf.write(after);
      buf.write(close);
    }
    buf.write(text.substring(cEnd));
    return [buf.toString(), newSelStart, newSelEnd];
  }

  /// Commit a history snapshot immediately (no debounce).
  void _commitHistory(String description) {
    if (_isCleaning) return;
    _historyTimer?.cancel();
    _typingBulkTimer?.cancel();
    _suiteAutoSaveTimer?.cancel();
    _typingCharCount = 0;

    final currentText = _getRefinedFullText();
    // Skip duplicate: don't commit if text + settings match the current head
    if (_historyIndex >= 0 && _historyIndex < _history.length) {
      final head = _history[_historyIndex];
      final settings = ref.read(settingsProvider);
      if (head.text == currentText &&
          head.fontSize == settings.fontSize &&
          head.fontFamily == (settings.fontFamily ?? 'Inter') &&
          head.lineSpacing == settings.lineSpacing &&
          head.letterSpacing == settings.letterSpacing &&
          head.wordSpacing == settings.wordSpacing) {
        return; // No change — skip
      }
    }

    final settings = ref.read(settingsProvider);
    final state = EditorState(
      text: currentText, timestamp: DateTime.now(), description: description,
      fontSize: settings.fontSize, fontFamily: settings.fontFamily ?? 'Inter',
      lineSpacing: settings.lineSpacing, letterSpacing: settings.letterSpacing, wordSpacing: settings.wordSpacing,
      scriptBgColor: settings.scriptBgColor, currentWordColor: settings.currentWordColor, futureWordColor: settings.futureWordColor, textAlign: settings.textAlign,
    );
    setState(() {
      if (_historyIndex < _history.length - 1) _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(state); if (_history.length > 50) _history.removeAt(0);
      _historyIndex = _history.length - 1;
    });
    _scheduleRecentUpdate();
  }

  /// Legacy-compatible entry point used by style commands and explicit saves.
  void _saveHistory({String description = 'Edit Text', bool debounce = false}) {
    if (_isCleaning) return;
    if (debounce) {
      // Typing bulk: accumulate chars, commit after 10 chars or 10 seconds
      _onTypingBulk(description);
      return;
    }
    _commitHistory(description);
  }

  /// Track suite section changes. If the function section changes within the
  /// same suite session, commit the previous section's edits first.
  void _trackSuiteSection(String section) {
    if (_activeSuite == EditorSuite.none) return;
    if (_suiteSection != null && _suiteSection != section && _isSuiteDirty) {
      // Section changed — commit previous section
      _commitHistory(_suiteSection!);
      _isSuiteDirty = false;
    }
    _suiteSection = section;
    _startSuiteAutoSave();
  }

  /// 3-second auto-checkpoint while a suite is open.
  /// Resets on every interaction. If 3s passes with no new interaction
  /// and the suite is dirty, commits a checkpoint.
  void _startSuiteAutoSave() {
    _suiteAutoSaveTimer?.cancel();
    _suiteAutoSaveTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _activeSuite != EditorSuite.none && _isSuiteDirty) {
        _commitHistory(_suiteSection ?? '${_activeSuite.name} Auto-Save');
        _isSuiteDirty = false;
      }
    });
  }

  /// 10-char / 10-second typing bulking.
  void _onTypingBulk(String description) {
    _typingCharCount++;
    if (_typingCharCount >= 10) {
      // Threshold reached — commit now
      _commitHistory(description);
      return;
    }
    // Start or reset the 10-second window timer
    _typingBulkTimer?.cancel();
    _typingBulkTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _typingCharCount > 0) {
        _commitHistory(description);
      }
    });
  }

  void _undo() {
    if (_historyIndex > 0) {
      _isCommandExecuting = true;
      _isDirty = false;
      setState(() { _historyIndex--; _applyState(_history[_historyIndex]); });
      // Keep _isCommandExecuting true until _isLoading resets (100ms)
      // to prevent controller listeners from corrupting history
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _isCommandExecuting = false;
          _isDirty = false;
        }
      });
      _forceRecentUpdate();
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      _isCommandExecuting = true;
      _isDirty = false;
      setState(() { _historyIndex++; _applyState(_history[_historyIndex]); });
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _isCommandExecuting = false;
          _isDirty = false;
        }
      });
      _forceRecentUpdate();
    }
  }

  void _jumpToHistory(int idx) {
    if (idx < 0 || idx >= _history.length || idx == _historyIndex) return;
    _isCommandExecuting = true;
    _isDirty = false;
    setState(() { _historyIndex = idx; _applyState(_history[idx]); });
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _isCommandExecuting = false;
        _isDirty = false;
      }
    });
    _forceRecentUpdate();
  }

  /// Apply settings that modify providers — safe to call outside of build.
  void _applySettingsFromState(EditorState s) {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setFontSize(s.fontSize);
    notifier.setFontFamily(s.fontFamily);
    notifier.setLineSpacing(s.lineSpacing);
    notifier.setLetterSpacing(s.letterSpacing);
    notifier.setWordSpacing(s.wordSpacing);
  }

  void _applyState(EditorState state) {
    _loadText(state.text);
    _applySettingsFromState(state);
  }

  MarkupController? get _activeController {
    for (var i=0; i<_focusNodes.length; i++) if (_focusNodes[i].hasFocus) return _controllers[i];
    return _lastFocusedController ?? (_controllers.isNotEmpty ? _controllers.last : null);
  }

  void handleBgColorChange(int color) {
    _isSuiteDirty = true; // Always treat as session change if color picker is involved
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    if (_activeSuite == EditorSuite.none) {
      _saveHistory(description: 'Change Background', debounce: true);
    }
    if (mounted) setState(() {});
  }

  /// Returns the list of controllers that should receive a style command,
  /// honoring an active overlay selection (refined or global) when present.
  List<MarkupController> _styleTargets() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      final refined = _controllers
          .where((c) => c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed)
          .toList();
      if (refined.isNotEmpty) return refined;
      return List.of(_controllers);
    }
    final active = _activeController;
    return active == null ? <MarkupController>[] : [active];
  }

  void _applyStyleCmd(String open, String close, String label) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    if (skipH) _trackSuiteSection('Style');

    if (_isGlobalSelection) {
      // Per-controller toggle: set full-block externalSelection on each,
      // temporarily disable global flag so the mixin uses single-controller path.
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
        wrapSelection(open, close, controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global $label');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
      final targets = _styleTargets();
      if (hasOverlay && targets.length > 1) {
        // v4.1.3: Apply style, then read c.selection synchronously.
        // wrapSelection sets controller.value (and thus c.selection) in the same
        // Dart call — iOS async platform resets only arrive at event-loop
        // boundaries, so the read is guaranteed correct before we return.
        for (final c in targets) {
          if (c.text.isEmpty) continue;
          final hadSelection = c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed;
          wrapSelection(open, close, controllerOverride: c, skipHistory: true);
          if (hadSelection) {
            final postSel = c.selection;
            if (postSel.isValid && !postSel.isCollapsed) {
              c.externalSelection = postSel;
              c.refresh();
            }
          }
        }
        _overlayKey.currentState?.syncOffsetsFromExternalSelection(_controllers);
        if (!skipH) _saveHistory(description: 'Selection $label');
      } else if (targets.length > 1) {
        for (final c in targets) {
          wrapSelection(open, close, controllerOverride: c, skipHistory: true);
        }
        if (!skipH) _saveHistory(description: 'Selection $label');
      } else if (targets.length == 1) {
        final c = targets.first;
        // v4.1.3: Check whether a selection exists, apply the style, then read
        // c.selection synchronously — it is set by wrapSelection before any iOS
        // platform event can interfere. No visual-offset conversion needed.
        final hadSel =
            (c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed) ||
            !c.selection.isCollapsed;
        wrapSelection(open, close, controllerOverride: c, skipHistory: skipH);
        if (hadSel) {
          final postSel = c.selection;
          if (postSel.isValid && !postSel.isCollapsed) {
            c.externalSelection = postSel;
            c.refresh();
          }
          if (_overlayKey.currentState?.hasSelection ?? false) {
            _overlayKey.currentState?.syncOffsetsFromExternalSelection(_controllers);
          }
        }
      }
    }

    if (skipH) _isSuiteDirty = true;
    // Update cursor style BEFORE clearing _isCommandExecuting,
    // so _onSelectionChanged won't clear global selection prematurely.
    _onSelectionChanged();
    setState(() => _isCommandExecuting = false);
  }

  void _onBold() => _applyStyleCmd('**', '**', 'Bold');
  void _onUnderline() => _applyStyleCmd('[u]', '[/u]', 'Underline');
  void _onItalic() => _applyStyleCmd('[i]', '[/i]', 'Italic');

  void _applyInlineCmd(String family, String open, String close, String label) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    // Section mapping: size → Font Size, font → Font Family, color → Text Color, bg → Highlight
    if (skipH) {
      final sectionMap = {'size': 'Font Size', 'font': 'Font Family', 'color': 'Text Color', 'bg': 'Highlight'};
      _trackSuiteSection(sectionMap[family] ?? label);
    }

    if (_isGlobalSelection) {
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
        applyInlineProperty(family, open, close, controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global $label');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
      final targets = _styleTargets();
      if (hasOverlay && targets.length > 1) {
        // v4.1.3: Same synchronous-read approach as _applyStyleCmd multi-block.
        for (final c in targets) {
          if (c.text.isEmpty) continue;
          final hadSelection = c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed;
          applyInlineProperty(family, open, close, controllerOverride: c, skipHistory: true);
          if (hadSelection) {
            final postSel = c.selection;
            if (postSel.isValid && !postSel.isCollapsed) {
              c.externalSelection = postSel;
              c.refresh();
            }
          }
        }
        _overlayKey.currentState?.syncOffsetsFromExternalSelection(_controllers);
      } else if (targets.length == 1) {
        // v4.1.3: Same synchronous-read approach as _applyStyleCmd single-block.
        final c = targets.first;
        final hadSel =
            (c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed) ||
            !c.selection.isCollapsed;
        applyInlineProperty(family, open, close, controllerOverride: c, skipHistory: true);
        if (hadSel) {
          final postSel = c.selection;
          if (postSel.isValid && !postSel.isCollapsed) {
            c.externalSelection = postSel;
            c.refresh();
          }
          if (_overlayKey.currentState?.hasSelection ?? false) {
            _overlayKey.currentState?.syncOffsetsFromExternalSelection(_controllers);
          }
        }
      } else {
        for (final c in targets) {
          applyInlineProperty(family, open, close, controllerOverride: c, skipHistory: true);
        }
      }
      if (!skipH && targets.isNotEmpty) {
        _saveHistory(description: targets.length > 1 ? 'Global $label' : label);
      }
    }

    if (skipH) _isSuiteDirty = true;
    _onSelectionChanged();
    setState(() => _isCommandExecuting = false);
  }

  void onDirection(String dir) {
    setState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Alignment');

    if (_isGlobalSelection) {
       broadcastAlign(dir, open: '[$dir]', close: '[/$dir]');
       _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final controller in targets) {
        // v4.1.3: Alignment strips/replaces the outer tag, shifting all raw
        // offsets by the tag-length delta. Capture visual offsets (invariant
        // to tag changes) before applying, then re-pin externalSelection after.
        final hadSel = controller.externalSelection != null &&
            controller.externalSelection!.isValid &&
            !controller.externalSelection!.isCollapsed;
        final visStart = hadSel ? MarkupController.rawToVisualOffset(controller.text, controller.externalSelection!.start) : 0;
        final visEnd   = hadSel ? MarkupController.rawToVisualOffset(controller.text, controller.externalSelection!.end)   : 0;
        controller.value = TextEditingValue(
          text: StylingService.applyLayout(controller.text, controller.selection, dir),
          selection: TextSelection.collapsed(offset: 0),
        );
        if (hadSel) {
          final newStart = MarkupController.visualToRawOffset(controller.text, visStart);
          final newEnd   = MarkupController.visualToRawOffset(controller.text, visEnd);
          if (newEnd > newStart) {
            controller.externalSelection = TextSelection(baseOffset: newStart, extentOffset: newEnd);
            controller.refresh();
          }
        }
      }
      if (_overlayKey.currentState?.hasSelection ?? false) {
        _overlayKey.currentState?.syncOffsetsFromExternalSelection(targets);
      }
    }

    if (inSuite) {
      _isSuiteDirty = true;
    } else {
      _commitHistory('Direction: $dir');
    }
    _onSelectionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlayKey.currentState?.refreshPositions();
    });
    setState(() => _isCommandExecuting = false);
  }

  void onAlign(String align) {
    setState(() => _isCommandExecuting = true);
    final inSuite = _activeSuite != EditorSuite.none;
    if (inSuite) _trackSuiteSection('Alignment');

    if (_isGlobalSelection) {
       broadcastAlign(align, open: '[align=$align]', close: '[/align=$align]');
       _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final controller in targets) {
        // v4.1.3: Same visual-offset preservation as onDirection.
        final hadSel = controller.externalSelection != null &&
            controller.externalSelection!.isValid &&
            !controller.externalSelection!.isCollapsed;
        final visStart = hadSel ? MarkupController.rawToVisualOffset(controller.text, controller.externalSelection!.start) : 0;
        final visEnd   = hadSel ? MarkupController.rawToVisualOffset(controller.text, controller.externalSelection!.end)   : 0;
        controller.value = TextEditingValue(
          text: StylingService.applyLayout(controller.text, controller.selection, align),
          selection: TextSelection.collapsed(offset: 0),
        );
        if (hadSel) {
          final newStart = MarkupController.visualToRawOffset(controller.text, visStart);
          final newEnd   = MarkupController.visualToRawOffset(controller.text, visEnd);
          if (newEnd > newStart) {
            controller.externalSelection = TextSelection(baseOffset: newStart, extentOffset: newEnd);
            controller.refresh();
          }
        }
      }
      if (_overlayKey.currentState?.hasSelection ?? false) {
        _overlayKey.currentState?.syncOffsetsFromExternalSelection(targets);
      }
    }

    if (inSuite) {
      _isSuiteDirty = true;
    } else {
      _commitHistory('Align: $align');
    }
    _onSelectionChanged();
    // Directly stamp the chosen alignment into cursorStyleProvider after the
    // detection callback runs — detection is unreliable immediately after an
    // apply because the focus/selection state is in flux.
    // Also refresh overlay handle positions — text moved visually but handles
    // are still at the old coordinates from before the alignment change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cursorStyleProvider.notifier).state =
          ref.read(cursorStyleProvider).copyWith(textAlign: align);
      _overlayKey.currentState?.refreshPositions();
    });
    setState(() => _isCommandExecuting = false);
  }

  void onFontSize(int size) =>
      _applyInlineCmd('size', '[size=$size]', '[/size]', 'Font Size');

  void onFontFamily(String family) =>
      _applyInlineCmd('font', '[font=$family]', '[/font]', 'Font Family');

  /// Restore the selection that was active before a dialog stole focus.
  /// Color picker dialogs cause the TextField to lose focus, collapsing the
  /// selection. This restores it so the style is applied to the right range.
  void _restoreSelectionIfNeeded() {
    final c = _activeController;
    if (c == null) return;
    if (c.selection.isCollapsed && _preservedSelection != null && !_preservedSelection!.isCollapsed) {
      final sel = _preservedSelection!;
      if (sel.end <= c.text.length) {
        c.selection = sel;
      }
    }
  }

  void onTextColorSelected(String hex) {
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final intVal = int.tryParse(cleanHex, radix: 16) ?? 0;
    // "None" color (transparent/0): REMOVE existing color tags instead of wrapping
    if (intVal == 0 || intVal == 0x00000000) {
      _restoreSelectionIfNeeded();
      _removeInlineTags('color', '[/color]');
      return;
    }
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0xFFFFBF00);
    setState(() => _lastChosenTextColor = color);
    ref.read(settingsProvider.notifier).setLastChosenTextColor(color.value);
    _restoreSelectionIfNeeded();
    _applyInlineCmd('color', '[color=#$cleanHex]', '[/color]', 'Text Color');
  }

  void onBgColorSelected(String hex) {
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final intVal = int.tryParse(cleanHex, radix: 16) ?? 0;
    // "None" color (transparent/0): REMOVE existing bg tags instead of wrapping
    if (intVal == 0 || intVal == 0x00000000) {
      _restoreSelectionIfNeeded();
      _removeInlineTags('bg', '[/bg]');
      return;
    }
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0x00FFFFFF);
    setState(() => _lastChosenHighlightColor = color);
    ref.read(settingsProvider.notifier).setLastChosenHighlightColor(color.value);
    _restoreSelectionIfNeeded();
    _applyInlineCmd('bg', '[bg=#$cleanHex]', '[/bg]', 'Highlight Color');
  }

  /// Remove all tags of a given family from the selection (used when "none" color is chosen).
  void _removeInlineTags(String family, String close) {
    setState(() => _isCommandExecuting = true);
    final openPattern = RegExp(r'\[' + family + r'=[^\]]*\]');

    if (_isGlobalSelection) {
      _isGlobalSelection = false;
      for (final c in _controllers) {
        if (c.text.isEmpty) continue;
        c.text = c.text.replaceAll(openPattern, '').replaceAll(close, '');
      }
      _saveHistory(description: 'Remove $family');
      _isGlobalSelection = true;
      _resyncGlobalSelection();
    } else {
      final targets = _styleTargets();
      for (final c in targets) {
        final sel = (c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed)
            ? c.externalSelection!
            : c.selection;
        if (sel.isCollapsed) {
          // Cursor mode: remove enclosing tag pair
          final text = c.text;
          final tagMatch = openPattern.allMatches(text).where((m) {
            final closeIdx = text.indexOf(close, m.end);
            return closeIdx != -1 && m.start <= sel.start && closeIdx + close.length >= sel.end;
          }).toList();
          if (tagMatch.isNotEmpty) {
            final m = tagMatch.last;
            final closeIdx = text.indexOf(close, m.end);
            final newText = text.substring(0, m.start) +
                text.substring(m.end, closeIdx) +
                text.substring(closeIdx + close.length);
            final offset = (sel.start - m.group(0)!.length).clamp(0, newText.length);
            c.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: offset),
            );
          }
        } else {
          // Range mode: strip all family tags within selection
          final before = c.text.substring(0, sel.start);
          final selected = c.text.substring(sel.start, sel.end);
          final after = c.text.substring(sel.end);
          final cleaned = selected.replaceAll(openPattern, '').replaceAll(close, '');
          c.value = TextEditingValue(
            text: before + cleaned + after,
            selection: TextSelection(baseOffset: sel.start, extentOffset: sel.start + cleaned.length),
          );
        }
      }
      if (targets.isNotEmpty) _saveHistory(description: 'Remove $family');
    }
    _onSelectionChanged();
    setState(() => _isCommandExecuting = false);
  }

  Future<void> _importFile() async {
    final supportedExts = PlatformFileImport.supportedExtensions;
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (!mounted) return;
    if (result == null || result.files.single.path == null) {
      // v3.9.5.59: Fluid navigation fallback
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.block_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 10),
            Text("Not Supported", style: TextStyle(color: Colors.white, fontSize: 17)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${selectedFile.path.split('/').last}"', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('.${ext.toUpperCase()} files cannot be used as scripts.', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              const Text('Supported formats:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text(PlatformFileImport.formatsLabel, style: const TextStyle(color: Color(0xFFFFBF00), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK", style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)))],
        ),
      );
      return;
    }

    // Persist the current script's session before swapping editors so its
    // history index / recent entry are not lost.
    await _forceRecentUpdate();
    if (!mounted) return;

    // Replace this editor with a fresh instance that runs the standard
    // pending-file load flow (conflict detection focuses an existing
    // recent if the file is already known, otherwise it loads as new).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ScriptEditorScreen(pendingFile: selectedFile)),
    );
  }

  Future<void> _saveScript() async {
    final format = await EditorDialogs.showSaveFormatDialog(context);
    if (format == null || !mounted) return;

    final text = _getRefinedFullText();

    // Generate bytes in the correct format for the chosen file type
    final List<int> bytes;
    if (format == 'docx') {
      bytes = DocxService.generate(text);
    } else if (format == 'rtf') {
      bytes = RtfService.generate(text);
    } else if (format == 'pages') {
      bytes = PagesService.generate(text);
    } else {
      // txt, md — plain UTF-8
      bytes = utf8.encode(text);
    }

    // Build filename with guaranteed extension — strip any prior extension first
    final safeName = _currentTitle
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\.(txt|pdf|docx|rtf|pages|md)$', caseSensitive: false), '');
    final fileName = '$safeName.$format';

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save as ${format.toUpperCase()}',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );

    // If the user saved but the OS stripped the extension, warn them
    if (savedPath != null && !savedPath.endsWith('.$format')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved. Note: you may need to rename it to add ".$format" extension.'),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _clearScript() {
    setState(() { _loadText(''); _saveHistory(description: 'Clear'); });
  }

  void _startPresenting() {
    try {
      ref.read(scriptProvider.notifier).loadText(_getRefinedFullText());
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeleprompterScreen()));
    }
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
                  child: const Text('Done', style: TextStyle(color: Color(0xFFFFBF00), fontSize: 17, fontWeight: FontWeight.w600)),
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
                  label: const Text('PRESENT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFBF00),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        ),
      ),
      bottomNavigationBar: _buildBottomActions(keyboardVisible: keyboardVisible),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
        children: [
          Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC): const _CopyIntent(),
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC): const _CopyIntent(),
        },
        child: Actions(
          actions: {
            _SelectAllIntent: CallbackAction<_SelectAllIntent>(onInvoke: (intent) {
              _selectAllBlocks(); return null;
            }),
            _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (intent) {
              _onCopyClean(); return null;
            }),
          },
          child: Column(
            children: [
              FormattingToolbarMVP(
                onBold: _onBold, onUnderline: _onUnderline, onItalic: _onItalic,
                onClear: () {
                  setState(() => _isCommandExecuting = true);
                  final tagPattern = RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
                  if (_isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false)) {
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
                        final selected = text.substring(sel.start, sel.end);
                        final after = text.substring(sel.end);
                        final cleaned = selected.replaceAll(tagPattern, '');
                        final intermediate = before + cleaned + after;
                        final cleanEnd = sel.start + cleaned.length;
                        final result = _splitAllEnclosingStyles(intermediate, sel.start, cleanEnd, tagPattern);
                        c.value = TextEditingValue(
                          text: result,
                          selection: TextSelection.collapsed(offset: sel.start),
                        );
                      } else if (sel.isValid && sel.isCollapsed) {
                        // Check if cursor is at end of line/paragraph → Baseline Mode: clear whole script
                        final plainText = text.replaceAll(tagPattern, '');
                        final cursorInPlain = sel.start >= text.length || text.substring(sel.start).replaceAll(tagPattern, '').isEmpty;
                        if (cursorInPlain) {
                          // Baseline Mode: clear ALL tags from ALL blocks
                          for (final ctrl in _controllers) {
                            ctrl.text = ctrl.text.replaceAll(tagPattern, '');
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
                onFontSize: onFontSize, onAlign: onAlign, onDirection: onDirection,
                onTextColor: onTextColorSelected, onBgColor: onBgColorSelected, onFontFamily: onFontFamily,
                onBgColorChange: handleBgColorChange, lastTextColor: _lastChosenTextColor, lastHighlightColor: _lastChosenHighlightColor,
                onUndo: _undo, onRedo: _redo, canUndo: _historyIndex > 0, canRedo: _historyIndex < _history.length - 1,
                history: _history, historyIndex: _historyIndex, onHistorySelected: (idx) => _jumpToHistory(idx),
                activeSuite: _activeSuite,
                onSuiteToggle: (suite) {
                  // Closing = explicitly closing (none), toggling same suite off, or switching suites
                  final willClose = suite == EditorSuite.none || suite == _activeSuite;
                  final willSwitch = suite != _activeSuite && _activeSuite != EditorSuite.none;
                  _suiteAutoSaveTimer?.cancel();
                  if ((willClose || willSwitch) && _isSuiteDirty) {
                    _commitHistory(_suiteSection ?? '${_activeSuite.name.toUpperCase()} Session');
                    _isSuiteDirty = false;
                    _suiteSection = null;
                  }
                  setState(() { _activeSuite = (_activeSuite == suite) ? EditorSuite.none : suite; });
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
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 250),
                      itemCount: _controllers.length,
                      itemBuilder: (context, index) => _EditorBlock(
                        key: _blockKeys[index],
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        settings: settings,
                        isGlobalSelected: _isGlobalSelection,
                        onSubmitted: () => _addBlock(index + 1),
                        onTap: () {
                          if (_isGlobalSelection ||
                              _controllers.any((c) => c.isGlobalSelected) ||
                              (_overlayKey.currentState?.hasSelection ?? false) ||
                              _controllers.any((c) => c.externalSelection != null)) {
                            _clearGlobalSelection();
                          }
                        },
                        onSelectAll: _selectAllBlocks,
                        onCopy: _onCopyClean,
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
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFBF00)),
                        ),
                      ),
                      SizedBox(height: 18),
                      Text('Loading script…',
                          style: TextStyle(color: Color(0xFFFFBF00), fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
             ),
          if (settings.debugMode)
            Positioned(
              bottom: 24, left: 24,
              child: IgnorePointer(child: _buildDebugSentry()),
            ),
        ],
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
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚙️ EDITOR SENTRY', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text('Blocks: ${_controllers.length}', style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Active Block: ${activeIdx != -1 ? activeIdx : "None"}', style: const TextStyle(color: Colors.white, fontSize: 10)),
          if (sel != null)
             Text('Cursor: [${sel.baseOffset}, ${sel.extentOffset}]', style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Global Selection: $_isGlobalSelection', style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('History States: ${_history.length}', style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }

  void _onCopyClean() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      for (int i = 0; i < _controllers.length; i++) {
        final c = _controllers[i];
        final sel = c.externalSelection;
        String slice;
        if (c.isGlobalSelected || sel == null || !sel.isValid) {
          slice = c.text;
        } else if (sel.isCollapsed) {
          continue;
        } else {
          slice = c.text.substring(sel.start, sel.end);
        }
        if (slice.isEmpty) continue;
        if (plainBuf.isNotEmpty) plainBuf.write('\n');
        plainBuf.write(StylingService.stripTags(slice));
        htmlBuf.write(StylingService.markupToHtml(slice));
      }
      if (plainBuf.isEmpty) return;
      RichClipboard.setHtml(plain: plainBuf.toString(), html: htmlBuf.toString());
      return;
    }
    final controller = _activeController;
    if (controller == null) return;
    final slice = controller.selection.textInside(controller.text);
    if (slice.isEmpty) return;
    RichClipboard.setHtml(
      plain: StylingService.stripTags(slice),
      html: StylingService.markupToHtml(slice),
    );
  }

  void _selectAllBlocks() {
    _overlayKey.currentState?.selectAll();
    _isGlobalSelection = true;
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    setState(() {});
    // Refresh after setState so TextFields repaint with new flags.
    for (final c in _controllers) {
      c.refresh();
    }
  }

  void _clearGlobalSelection() {
    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      // Collapse native selection to prevent residual highlight in buildTextSpan.
      // For RTL text, use baseOffset (cursor stays at visual tap position).
      if (!c.selection.isCollapsed) {
        final collapseAt = c.selection.baseOffset.clamp(0, c.text.length);
        c.selection = TextSelection.collapsed(offset: collapseAt);
      }
    }
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    // Safety net: re-clear after Flutter's TextField processes the tap gesture,
    // which can re-establish selection in RTL blocks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool needsRefresh = false;
      for (final c in _controllers) {
        if (c.externalSelection != null) {
          c.externalSelection = null;
          needsRefresh = true;
        }
        if (c.isGlobalSelected) {
          c.isGlobalSelected = false;
          needsRefresh = true;
        }
      }
      if (needsRefresh) {
        for (final c in _controllers) {
          c.refresh();
        }
        setState(() {});
      }
    });
  }

  /// Re-sync externalSelection after a global style operation changes text lengths.
  void _resyncGlobalSelection() {
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
  }

}

class _EditorBlock extends StatelessWidget {
  final MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final bool isGlobalSelected;
  final VoidCallback onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;

  const _EditorBlock({
    super.key,
    required this.controller, required this.focusNode, required this.settings,
    required this.isGlobalSelected, required this.onSubmitted, required this.onTap,
    required this.onSelectAll, required this.onCopy,
  });

  TextAlign? _markupAlign(String text) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(text)) return TextAlign.center;
    if (RegExp(r'\[(?:align=)?right\]').hasMatch(text)) return TextAlign.right;
    if (RegExp(r'\[(?:align=)?left\]').hasMatch(text)) return TextAlign.left;
    return null;
  }

  double _getMaxFontSize(String text, double defaultSize) {
    if (text.isEmpty) return defaultSize;
    final matches = RegExp(r'\[size=(\d+)\]').allMatches(text);
    if (matches.isEmpty) return defaultSize;
    double maxMatch = defaultSize;
    for (final m in matches) {
      final size = double.tryParse(m.group(1)!) ?? defaultSize;
      if (size > maxMatch) maxMatch = size;
    }
    return maxMatch;
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = controller.text.isHebrew;
    final markupAlign = _markupAlign(controller.text);
    final textAlign = markupAlign ?? (isRtl ? TextAlign.right : TextAlign.left);
    final maxFontSize = _getMaxFontSize(controller.text, settings.fontSize);

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyA, control: true): _SelectAllIntent(),
            SingleActivator(LogicalKeyboardKey.keyA, meta: true): _SelectAllIntent(),
            SingleActivator(LogicalKeyboardKey.keyC, control: true): _CopyIntent(),
            SingleActivator(LogicalKeyboardKey.keyC, meta: true): _CopyIntent(),
          },
          child: Actions(
            actions: {
              _SelectAllIntent: CallbackAction<_SelectAllIntent>(onInvoke: (_) {
                onSelectAll();
                return null;
              }),
              _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (_) {
                onCopy();
                return null;
              }),
              // Override the internal EditableText intents too. These are
              // marked Action.overridable inside EditableText, so placing
              // our own handlers at this ancestor wins — catching both the
              // keyboard Cmd+C and Flutter's internal copy dispatch paths.
              CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
                onInvoke: (_) {
                  onCopy();
                  return null;
                },
              ),
              SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
                onInvoke: (_) {
                  onSelectAll();
                  return null;
                },
              ),
            },
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                // Always transparent: all amber selection rendering is handled
                // by MarkupController.buildTextSpan via externalSelection /
                // isGlobalSelected. Native RenderEditable must never paint its
                // own amber highlight or it leaks through when _isGlobalSelection
                // flips to false during a handle drag (Bug 2 fix v4.0.6).
                selectionColor: Colors.transparent,
              ),
            ),
          child: TextField(
            selectionControls: GhostSelectionControls(),
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
            onSubmitted: (_) => onSubmitted(),
            onTap: onTap,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            textAlign: textAlign,
            cursorColor: Colors.amber,
            cursorHeight: maxFontSize,
            strutStyle: StrutStyle(
              fontSize: maxFontSize,
              height: settings.lineSpacing,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: settings.fontSize,
              height: settings.lineSpacing,
              letterSpacing: settings.letterSpacing,
              wordSpacing: settings.wordSpacing,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 2),
            ),
            contextMenuBuilder: (context, editableTextState) {
              final List<ContextMenuButtonItem> items = editableTextState.contextMenuButtonItems;
              final List<ContextMenuButtonItem> customItems = [];
              bool hasSelectAll = false;
              for (final item in items) {
                if (item.type == ContextMenuButtonType.selectAll) {
                  hasSelectAll = true;
                  customItems.add(ContextMenuButtonItem(
                    onPressed: () {
                      ContextMenuController.removeAny();
                      onSelectAll();
                    },
                    type: ContextMenuButtonType.selectAll,
                  ));
                } else if (item.type == ContextMenuButtonType.copy) {
                  customItems.add(ContextMenuButtonItem(
                    onPressed: () {
                      ContextMenuController.removeAny();
                      onCopy();
                    },
                    type: ContextMenuButtonType.copy,
                  ));
                } else {
                  customItems.add(item);
                }
              }
              // Force-inject a global Select All even when the native menu
              // omits it (e.g. the block is already fully selected).
              if (!hasSelectAll) {
                customItems.add(ContextMenuButtonItem(
                  onPressed: () {
                    ContextMenuController.removeAny();
                    onSelectAll();
                  },
                  type: ContextMenuButtonType.selectAll,
                ));
              }
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editableTextState.contextMenuAnchors,
                buttonItems: customItems,
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

