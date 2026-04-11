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
import '../../teleprompter/widgets/content_creator_screen.dart';
import '../../teleprompter/providers/teleprompter_provider.dart';
import '../services/styling_service.dart';
import '../services/docx_service.dart';

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
  @override
  List<MarkupController> get controllers => _controllers;
  @override
  MarkupController? get activeController => _activeController;
  @override
  void saveHistory({required String description, bool debounce = true}) => _saveHistory(description: description, debounce: debounce);

  final List<MarkupController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  final List<GlobalKey> _blockKeys = []; // v3.9.5.66: Managed Coordinate Registry
  String _currentTitle = 'New Project';
  
  TextSelection? _lastSelection;
  MarkupController? _lastFocusedController;
  
  String _sourceType = 'TEMP';
  String? _currentSessionId;
  final List<EditorState> _history = [];
  int _historyIndex = -1;
  static const int _maxHistory = 30;
  
  Color _lastChosenTextColor = const Color(0xFFFFBF00);
  Color _lastChosenHighlightColor = const Color(0x4DFFFFFF);

  bool _isCleaning = false;
  bool _isInit = false;
  bool _isSuiteDirty = false;
  bool _isCommandExecuting = false;
  bool _isGlobalSelection = false;
  bool _isDirty = false;
  bool _isLoading = false;
  bool _isPendingLoad = false;
  EditorSuite _activeSuite = EditorSuite.none;
  Timer? _historyTimer, _recentTimer, _autoSaveTimer;
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
      _isInit = true; // NEW (v3.9.5.59): Prevent double init on auto-load
      _isPendingLoad = true; // NEW (v3.9.5.59): Show amber wheel immediately
      WidgetsBinding.instance.addPostFrameCallback((_) => _importFile());
    }
  }

  Future<void> _runPendingFileLoad(File file) async {
    try {
      // Mirror the per-load setup didChangeDependencies normally performs.
      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
      final result = await ref.read(scriptProvider.notifier).parseFile(file);
      final String content = result.text;
      if (result.fontSize != null) {
        ref.read(settingsProvider.notifier).setFontSize(result.fontSize!);
      }
      if (!mounted) return;
      final String title = file.path.split('/').last;

      // Conflict Detection: Search Recents for matching title (filename)
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
          // Perfect Match: Don't import a duplicate. Just Open it.
          finalContent = existingContent;
          finalType = type;
          finalSessionId = sessionId;
          finalHistoryJson = decoded['historyJson'];
        } else {
          // Content Mismatch: Ask the user.
          if (!mounted) return;
          final String? choice = await showDialog<String>(
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
            if (mounted) Navigator.pop(context); // Dismissed: back out to home
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
      _scheduleRecentUpdate();
    } finally {
      if (mounted) setState(() => _isPendingLoad = false);
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final text = _getRefinedFullText();
      if (text.isEmpty && _currentTitle == 'New Project') return;
      try {
        final settings = ref.read(settingsProvider);
        await ref.read(settingsProvider.notifier).saveScript(
          text, 
          title: _currentTitle, 
          historyIndex: _historyIndex,
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
      } catch (_) {}
    });
  }

  @override
  void didChangeDependencies() {
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

      final notifier = ref.read(settingsProvider.notifier);
      if (script != null) {
        Future.microtask(() {
          notifier.setFontSize(script.fontSize.toDouble());
          notifier.setFontFamily(script.fontFamily);
        });
      }

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
        _applyState(_history[_historyIndex]);
      } else if (_history.isNotEmpty) {
        _applyState(_history.last);
        _historyIndex = _history.length - 1;
      } else {
        _saveHistory(description: 'Initial Load');
      }
      _scheduleRecentUpdate();
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
        else if (_isDirty) _saveHistory(description: 'Edit Text', debounce: false);
      });

      String lastText = text;
      controller.addListener(() {
        if (_isLoading) return;
        if (controller.text == lastText) {
          if (node.hasFocus) { _lastSelection = controller.selection; _onSelectionChanged(); }
          return; 
        }
        lastText = controller.text;
        _isDirty = true;
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
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final controller = _activeController;
    if (controller != null) {
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
    final off = offset ?? controller.selection.baseOffset;
    if (off < 0) return 'left';
    final alignMatches = RegExp(r'\[(?:align=)?(center|left|right)\]').allMatches(text);
    final dirMatches = RegExp(r'\[(rtl|ltr)\]').allMatches(text);
    String found = 'left';
    for (final m in alignMatches) {
      if (m.start <= off) {
         final val = m.group(1)!;
         final nextClose = text.indexOf('[/$val]', m.end);
         if (nextClose == -1 || nextClose == text.indexOf('[/align=$val]', m.end) || nextClose >= off) found = val;
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
    _historyTimer?.cancel(); _recentTimer?.cancel(); _autoSaveTimer?.cancel();
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

  void _saveHistory({String description = 'Edit Text', bool debounce = false}) {
    _historyTimer?.cancel();
    if (debounce) {
      _historyTimer = Timer(const Duration(milliseconds: 300), () => _saveHistory(description: description, debounce: false));
      return;
    }
    if (!_isDirty && !_isSuiteDirty && description == 'Edit Text') return;
    _isDirty = false;
    final settings = ref.read(settingsProvider);
    final state = EditorState(
      text: _getRefinedFullText(), timestamp: DateTime.now(), description: description,
      fontSize: settings.fontSize, fontFamily: settings.fontFamily ?? 'Inter',
      lineSpacing: settings.lineSpacing, letterSpacing: settings.letterSpacing, wordSpacing: settings.wordSpacing,
      scriptBgColor: settings.scriptBgColor, currentWordColor: settings.currentWordColor, futureWordColor: settings.futureWordColor, textAlign: settings.textAlign,
    );
    setState(() {
      if (_historyIndex < _history.length - 1) _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(state); if (_history.length > _maxHistory) _history.removeAt(0);
      _historyIndex = _history.length - 1;
    });
    _scheduleRecentUpdate(); // v3.9.5.71: Immediate Sentry Sync
  }

  void _undo() {
    if (_historyIndex > 0) {
      _isCommandExecuting = true;
      setState(() { _historyIndex--; _applyState(_history[_historyIndex]); });
      _isCommandExecuting = false;
      _forceRecentUpdate();
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      _isCommandExecuting = true;
      setState(() { _historyIndex++; _applyState(_history[_historyIndex]); });
      _isCommandExecuting = false;
      _forceRecentUpdate();
    }
  }

  void _applyState(EditorState state) {
    _loadText(state.text);
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setFontSize(state.fontSize);
    notifier.setFontFamily(state.fontFamily);
    notifier.setLineSpacing(state.lineSpacing);
    notifier.setLetterSpacing(state.letterSpacing);
    notifier.setWordSpacing(state.wordSpacing);
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

  void _onBold() {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        wrapSelection('**', '**', controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global Bold');
    } else {
      wrapSelection('**', '**', skipHistory: skipH);
    }
    if (skipH) _isSuiteDirty = true;
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }
  void _onUnderline() {
    setState(() => _isCommandExecuting = true);
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        wrapSelection('[u]', '[/u]', controllerOverride: c, skipHistory: true);
      }
      _saveHistory(description: 'Global Underline');
    } else {
      wrapSelection('[u]', '[/u]');
    }
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }
  void _onItalic() {
    setState(() => _isCommandExecuting = true);
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        wrapSelection('[i]', '[/i]', controllerOverride: c, skipHistory: true);
      }
      _saveHistory(description: 'Global Italic');
    } else {
      wrapSelection('[i]', '[/i]');
    }
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }

  void onDirection(String dir) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    final targetControllers = _isGlobalSelection ? _controllers : [_activeController].whereType<MarkupController>();
    for (final controller in targetControllers) {
      controller.value = TextEditingValue(
        text: StylingService.applyLayout(controller.text, controller.selection, dir),
        selection: controller.selection,
      );
    }
    if (skipH) {
      _isSuiteDirty = true;
    } else {
      _saveHistory(description: _isGlobalSelection ? 'Global Direction' : 'Direction Change');
    }
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }

  void onAlign(String align) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    final targetControllers = _isGlobalSelection ? _controllers : [_activeController].whereType<MarkupController>();
    for (final controller in targetControllers) {
      controller.value = TextEditingValue(
        text: StylingService.applyLayout(controller.text, controller.selection, align),
        selection: controller.selection,
      );
    }
    if (skipH) {
      _isSuiteDirty = true;
    } else {
      _saveHistory(description: _isGlobalSelection ? 'Global Align' : 'Align Paragraph');
    }
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged(); // refresh active-button state
  }

  void onFontSize(int size) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        applyInlineProperty('size', '[size=$size]', '[/size]', controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global Font Size');
    } else {
      applyInlineProperty('size', '[size=$size]', '[/size]', skipHistory: skipH);
    }
    if (skipH) _isSuiteDirty = true;
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }
  void onFontFamily(String family) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        applyInlineProperty('font', '[font=$family]', '[/font]', controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global Font Family');
    } else {
      applyInlineProperty('font', '[font=$family]', '[/font]', skipHistory: skipH);
    }
    if (skipH) _isSuiteDirty = true;
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }

  void onTextColorSelected(String hex) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0xFFFFBF00);
    setState(() => _lastChosenTextColor = color);
    ref.read(settingsProvider.notifier).setLastChosenTextColor(color.value);
    
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        applyInlineProperty('color', '[color=#$cleanHex]', '[/color]', controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global Text Color');
    } else {
      applyInlineProperty('color', '[color=#$cleanHex]', '[/color]', skipHistory: skipH);
    }
    if (skipH) _isSuiteDirty = true;
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }

  void onBgColorSelected(String hex) {
    setState(() => _isCommandExecuting = true);
    final skipH = _activeSuite != EditorSuite.none;
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0x00FFFFFF);
    setState(() => _lastChosenHighlightColor = color);
    ref.read(settingsProvider.notifier).setLastChosenHighlightColor(color.value);
    
    if (_isGlobalSelection) {
      for (final c in _controllers) {
        applyInlineProperty('bg', '[bg=#$cleanHex]', '[/bg]', controllerOverride: c, skipHistory: true);
      }
      if (!skipH) _saveHistory(description: 'Global Highlight Color');
    } else {
      applyInlineProperty('bg', '[bg=#$cleanHex]', '[/bg]', skipHistory: skipH);
    }
    if (skipH) _isSuiteDirty = true;
    setState(() => _isCommandExecuting = false);
    _onSelectionChanged();
  }

  Future<void> _importFile() async {
    const supportedExts = ['rtf', 'pdf', 'docx', 'doc', 'odt', 'txt', 'md', 'log', 'text'];
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
              const Text('DOCX · DOC · RTF · PDF · TXT · ODT · MD', style: TextStyle(color: Color(0xFFFFBF00), fontSize: 12, fontWeight: FontWeight.bold)),
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
    final text = _getRefinedFullText();
    final bytes = utf8.encode(text);
    await FilePicker.platform.saveFile(dialogTitle: 'Save script', fileName: 'script.txt', bytes: Uint8List.fromList(bytes));
  }

  void _clearScript() {
    setState(() { _loadText(''); _saveHistory(description: 'Clear'); });
  }

  void _startPresenting() {
    ref.read(scriptProvider.notifier).loadText(_getRefinedFullText());
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeleprompterScreen()));
  }

  void _startRecording() {
    ref.read(scriptProvider.notifier).loadText(_getRefinedFullText());
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContentCreatorScreen()));
  }

  Widget _buildBottomActions() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          const SizedBox(width: 8), // ~1% aprox (assuming ~800px width)
          Expanded(
            flex: 485,
            child: ElevatedButton.icon(
              onPressed: _startRecording,
              icon: const Icon(Icons.videocam_rounded, size: 24),
              label: const Text('RECORD', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 12,
                shadowColor: const Color(0xFFFFBF00).withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(width: 12), // ~1% aprox
          Expanded(
            flex: 485,
            child: ElevatedButton.icon(
              onPressed: _startPresenting,
              icon: const Icon(Icons.play_circle_filled_rounded, size: 24),
              label: const Text('PRESENT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 12,
                shadowColor: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
          const SizedBox(width: 8), // ~1% aprox
        ],
      ),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        toolbarHeight: 110,
        backgroundColor: const Color(0xFF0A0A0A),
        automaticallyImplyLeading: false,
        title: ProjectActionsSuite(
          title: _currentTitle,
          onBack: () => Navigator.pop(context),
          onRecord: _startRecording,
          onPresent: _startPresenting,
          onClear: _clearScript,
          onSave: _saveScript,
          onImport: _importFile,
          onRename: _showRenameDialog,
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
      body: Stack(
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
                  final targetControllers = (_isGlobalSelection || (_overlayKey.currentState?.hasSelection ?? false)) 
                      ? _controllers 
                      : [_activeController].whereType<MarkupController>();
                  for (final c in targetControllers) {
                    c.text = c.text.replaceAll(RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*'), '');
                  }
                  setState(() => _isCommandExecuting = false);
                  _saveHistory(description: 'Clear Format');
                },
                onFontSize: onFontSize, onAlign: onAlign, onDirection: onDirection,
                onTextColor: onTextColorSelected, onBgColor: onBgColorSelected, onFontFamily: onFontFamily,
                onBgColorChange: handleBgColorChange, lastTextColor: _lastChosenTextColor, lastHighlightColor: _lastChosenHighlightColor,
                onUndo: _undo, onRedo: _redo, canUndo: _historyIndex > 0, canRedo: _historyIndex < _history.length - 1,
                history: _history, historyIndex: _historyIndex, onHistorySelected: (idx) => setState(() { _historyIndex = idx; _applyState(_history[idx]); }),
                activeSuite: _activeSuite,
                onSuiteToggle: (suite) {
                  final isClosing = suite == EditorSuite.none || suite != _activeSuite;
                  if (isClosing && _isSuiteDirty) { _saveHistory(description: '${_activeSuite.name.toUpperCase()} Session', debounce: false); _isSuiteDirty = false; }
                  setState(() { _activeSuite = (_activeSuite == suite) ? EditorSuite.none : suite; });
                },
                onLayoutInteraction: () => setState(() => _isSuiteDirty = true),
              ),
              Expanded(
                child: Container(
                  color: Color(settings.scriptBgColor),
                  child: GlobalSelectionOverlay(
                    key: _overlayKey,
                    controllers: _controllers,
                    blockKeys: _blockKeys,
                    onSelectionChanged: () => setState(() {}),
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
                          setState(() => _isGlobalSelection = false);
                          _overlayKey.currentState?.clearSelection();
                        },
                        onSelectAll: () {
                          _overlayKey.currentState?.selectAll();
                          setState(() => _isGlobalSelection = true);
                        },
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
    if (_isGlobalSelection) {
      final all = _controllers.map((c) => StylingService.stripTags(c.text)).join('\n');
      Clipboard.setData(ClipboardData(text: all));
      return;
    }
    final controller = _activeController; if (controller == null) return;
    Clipboard.setData(ClipboardData(text: StylingService.stripTags(controller.selection.textInside(controller.text))));
  }

  void _selectAllBlocks() {
    _overlayKey.currentState?.selectAll();
    setState(() => _isGlobalSelection = true);
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
        color: isGlobalSelected ? const Color(0x33FFBF00) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          textSelectionTheme: TextSelectionThemeData(
            selectionColor: isGlobalSelected ? Colors.transparent : null,
          ),
        ),
        child: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
            LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
          },
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
              for (final item in items) {
                if (item.type == ContextMenuButtonType.selectAll) {
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
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editableTextState.contextMenuAnchors,
                buttonItems: customItems,
              );
            },
          ),
        ),
      ),
    );
  }
}

