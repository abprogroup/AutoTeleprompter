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
import '../providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../teleprompter/widgets/teleprompter_screen.dart';
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
  const ScriptEditorScreen({super.key, this.shouldAutoLoad = false});

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
  EditorSuite _activeSuite = EditorSuite.none;
  Timer? _historyTimer, _recentTimer, _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _startAutoSave();
    if (widget.shouldAutoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _importFile());
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final text = _getRefinedFullText();
      if (text.isEmpty && _currentTitle == 'New Project') return;
      try {
        await ref.read(settingsProvider.notifier).saveScript(text, title: _currentTitle, historyIndex: _historyIndex);
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

  void _clearControllers() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _controllers.clear();
    _focusNodes.clear();
  }

  void _addBlock(int index, {String? text}) {
    final controller = MarkupController();
    if (text != null) controller.text = text;
    final node = FocusNode(onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        final currentText = controller.text;
        final sel = controller.selection;
        String p1 = currentText, p2 = '';
        if (sel.isValid) {
          p1 = currentText.substring(0, sel.start);
          p2 = currentText.substring(sel.start);
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

    String lastText = text ?? '';
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

    setState(() {
      _controllers.insert(index, controller);
      _focusNodes.insert(index, node);
    });
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
    await ref.read(settingsProvider.notifier).saveScript(text, title: _currentTitle, type: _sourceType, historyIndex: _historyIndex, sessionId: _currentSessionId);
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
      final atBoundary = check(off);
      final nudgedBack = (selection.isCollapsed && off > 0 && text[off-1] != ' ' && text[off-1] != '\n') ? check(off - 1) : false;
      return atBoundary || nudgedBack;
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
      if (selection.isCollapsed && off > 0 && text[off-1] != ' ' && text[off-1] != '\n') return check(off - 1);
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
      if (selection.isCollapsed && off > 0 && text[off-1] != ' ' && text[off-1] != '\n') return check(off - 1);
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
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() { _historyIndex--; _applyState(_history[_historyIndex]); });
      _forceRecentUpdate();
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() { _historyIndex++; _applyState(_history[_historyIndex]); });
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
  }

  MarkupController? get _activeController {
    for (var i=0; i<_focusNodes.length; i++) if (_focusNodes[i].hasFocus) return _controllers[i];
    return _lastFocusedController ?? (_controllers.isNotEmpty ? _controllers.last : null);
  }

  void handleBgColorChange(int color) {
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    _saveHistory(description: 'Change Background', debounce: true);
    if (mounted) setState(() {});
  }

  void _onBold() => setState(() => _isCommandExecuting = true); 
  void _onUnderline() => setState(() => _isCommandExecuting = true); 
  void _onItalic() => setState(() => _isCommandExecuting = true); 

  void onDirection(String dir) {
    final controller = _activeController;
    if (controller == null) return;
    controller.value = TextEditingValue(text: StylingService.applyLayout(controller.text, controller.selection, dir), selection: controller.selection);
    _saveHistory(description: 'Direction Change');
  }

  void onAlign(String align) {
    final controller = _activeController;
    if (controller == null) return;
    controller.value = TextEditingValue(text: StylingService.applyLayout(controller.text, controller.selection, align), selection: controller.selection);
    _saveHistory(description: 'Align Paragraph');
  }

  void onFontSize(int size) { wrapSelection('[size=$size]', '[/size]'); }
  void onFontFamily(String family) { wrapSelection('[font=$family]', '[/font]'); }

  void onTextColorSelected(String hex) {
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0xFFFFBF00);
    setState(() => _lastChosenTextColor = color);
    ref.read(settingsProvider.notifier).setLastChosenTextColor(color.value);
    wrapSelection('[color=#$cleanHex]', '[/color]');
  }

  void onBgColorSelected(String hex) {
    final cleanHex = hex.replaceFirst('#', '').toUpperCase();
    final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0x00FFFFFF);
    setState(() => _lastChosenHighlightColor = color);
    ref.read(settingsProvider.notifier).setLastChosenHighlightColor(color.value);
    wrapSelection('[bg=#$cleanHex]', '[/bg]');
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || !mounted) return;
    final selectedFile = File(result.files.single.path!);
    final String content = await ref.read(scriptProvider.notifier).parseFile(selectedFile);
    _loadText(content); _currentTitle = selectedFile.path.split('/').last;
    _sourceType = _currentTitle.split('.').last.toUpperCase();
    _saveHistory(description: 'Import'); _forceRecentUpdate();
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

  @override
  Widget build(BuildContext context) {
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
          onVideo: _startPresenting,
          onClear: _clearScript,
          onSave: _saveScript,
          onImport: _importFile,
          onRename: _showRenameDialog,
        ),
      ),
      body: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC): const _CopyIntent(),
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC): const _CopyIntent(),
        },
        child: Actions(
          actions: {
            _SelectAllIntent: CallbackAction<_SelectAllIntent>(onInvoke: (intent) {
              setState(() => _isGlobalSelection = true); return null;
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
                  final controller = _activeController; if (controller == null) return;
                  controller.text = controller.text.replaceAll(RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*'), '');
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
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
                    itemCount: _controllers.length,
                    itemBuilder: (context, index) => _EditorBlock(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      settings: settings,
                      isGlobalSelected: _isGlobalSelection,
                      onSubmitted: () => _addBlock(index + 1),
                      onTap: () => setState(() => _isGlobalSelection = false),
                      onSelectAll: () => setState(() => _isGlobalSelection = true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCopyClean() {
    final controller = _activeController; if (controller == null) return;
    Clipboard.setData(ClipboardData(text: StylingService.stripTags(controller.selection.textInside(controller.text))));
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

  const _EditorBlock({
    required this.controller, required this.focusNode, required this.settings,
    required this.isGlobalSelected, required this.onSubmitted, required this.onTap,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: isGlobalSelected ? const Color(0x33FFBF00) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
      child: TextField(
        controller: controller, focusNode: focusNode,
        selectionControls: _CleanSelectionControls(() {
          Clipboard.setData(ClipboardData(text: StylingService.stripTags(controller.selection.textInside(controller.text))));
        }),
        maxLines: null,
        onSubmitted: (_) => onSubmitted(),
        onTap: onTap,
        style: TextStyle(color: Colors.white, fontSize: settings.fontSize),
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }
}

class _CleanSelectionControls extends MaterialTextSelectionControls {
  final VoidCallback onCopy;
  _CleanSelectionControls(this.onCopy);
  @override
  void handleCopy(TextSelectionDelegate delegate) { onCopy(); delegate.hideToolbar(); }
}
