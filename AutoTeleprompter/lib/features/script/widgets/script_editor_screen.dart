import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';

import '../providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../services/docx_service.dart';
import 'teleprompt_selector_sheet.dart';
import '../../script/models/script_word.dart';
import '../../teleprompter/widgets/teleprompter_screen.dart';
import '../../teleprompter/widgets/content_creator_screen.dart';
import '../../teleprompter/providers/teleprompter_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/widgets/global_color_picker.dart';

// v3.22.1: Industrial Strength Synchronization Bridge
final cursorStyleProvider = StateProvider<_CursorStyle>((ref) => _CursorStyle());

class _CursorStyle {
  final bool isBold, isItalic, isUnderline;
  final int fontSize;
  final String fontFamily, textAlign, direction;
  final Color? textColor, highlightColor;
  _CursorStyle({this.isBold=false, this.isItalic=false, this.isUnderline=false, this.fontSize=18, this.fontFamily='Inter', this.textAlign='left', this.direction='ltr', this.textColor, this.highlightColor});
}

// ── Markup-rendering TextEditingController ────────────────────────────────────

class _MarkupController extends TextEditingController {
  _MarkupController({String? text}) : super(text: text);

  static const _tagStyle = TextStyle(
    color: Colors.transparent,
    backgroundColor: Colors.transparent,
    fontSize: 0.1,
    letterSpacing: 0,
    wordSpacing: 0,
  );

  static final _markupRegex = RegExp(
    r'\[color=([^\]]+)\](.*?)\[\/color\]'
    r'|\[bg=([^\]]+)\](.*?)\[\/bg\]'
    r'|\*\*(.*?)\*\*'
    r'|\[u\](.*?)\[\/u\]'
    r'|\[i\](.*?)\[\/i\]'
    r'|\[size=(\d+)\](.*?)\[\/size\]'
    r'|\[(?:align=)?(center|left|right)\](.*?)\[\/(?:align=)?\10\]'
    r'|\[(?:align=)?(rtl|ltr)\](.*?)\[\/(?:align=)?\12\]'
    r'|\[font=([^\]]+)\](.*?)\[\/font\]'
    r'|(\[(?:\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?|size=\d+)\])',
    dotAll: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final fullText = value.text;
    final composing = value.composing;
    final hasComposing = composing.isValid && withComposing && value.isComposingRangeValid;

    if (!hasComposing) {
      return _buildMarkup(fullText, style);
    }

    final underline = (style ?? const TextStyle()).merge(const TextStyle(decoration: TextDecoration.underline));
    return TextSpan(style: style, children: [
      _buildMarkup(fullText.substring(0, composing.start), style),
      TextSpan(text: fullText.substring(composing.start, composing.end), style: underline),
      _buildMarkup(fullText.substring(composing.end), style),
    ]);
  }

  TextSpan _buildMarkup(String text, TextStyle? base) {
    if (text.isEmpty) return TextSpan(text: '', style: base);

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _markupRegex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }

      if (m.group(1) != null && m.group(2) != null) {
        final hex = m.group(1)!.trim().replaceFirst('#', '');
        final colorValue = int.tryParse('FF$hex', radix: 16) ?? 0xFFFFBF00;
        final color = Color(colorValue);
        final s = (base ?? const TextStyle()).merge(TextStyle(color: color));
        spans.add(TextSpan(text: '[color=#$hex]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(2)!, s));
        spans.add(TextSpan(text: '[/color]', style: _tagStyle));
      } else if (m.group(3) != null && m.group(4) != null) {
        final hex = m.group(3)!.trim().replaceFirst('#', '');
        final color = Color(int.tryParse('FF$hex', radix: 16) ?? 0x00000000);
        final s = (base ?? const TextStyle()).merge(TextStyle(backgroundColor: color.withOpacity(0.5)));
        spans.add(TextSpan(text: '[bg=#$hex]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(4)!, s));
        spans.add(TextSpan(text: '[/bg]', style: _tagStyle));
      } else if (m.group(5) != null) {
        final s = (base ?? const TextStyle()).merge(const TextStyle(fontWeight: FontWeight.bold));
        spans.add(TextSpan(text: '**', style: _tagStyle));
        spans.add(_buildMarkup(m.group(5)!, s));
        spans.add(TextSpan(text: '**', style: _tagStyle));
      } else if (m.group(6) != null) {
        final s = (base ?? const TextStyle()).merge(const TextStyle(decoration: TextDecoration.underline));
        spans.add(TextSpan(text: '[u]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(6)!, s));
        spans.add(TextSpan(text: '[/u]', style: _tagStyle));
      } else if (m.group(7) != null) {
        final s = (base ?? const TextStyle()).merge(const TextStyle(fontStyle: FontStyle.italic));
        spans.add(TextSpan(text: '[i]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(7)!, s));
        spans.add(TextSpan(text: '[/i]', style: _tagStyle));
      } else if (m.group(8) != null && m.group(9) != null) {
        final editorSize = double.tryParse(m.group(8)!) ?? 18.0;
        final s = (base ?? const TextStyle()).merge(TextStyle(fontSize: editorSize));
        spans.add(TextSpan(text: '[size=${m.group(8)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(9)!, s));
        spans.add(TextSpan(text: '[/size]', style: _tagStyle));
      } else if (m.group(10) != null && m.group(11) != null) {
        // Alignment tags: Categorical Rebuild to prevent RangeError
        final val = m.group(10)!;
        final content = m.group(11)!;
        final openTag = '[${val == "center" || val == "left" || val == "right" ? "align=$val" : val}]';
        final closeTag = '[/${val == "center" || val == "left" || val == "right" ? "align=$val" : val}]';
        spans.add(TextSpan(text: openTag, style: _tagStyle));
        spans.add(_buildMarkup(content, base));
        spans.add(TextSpan(text: closeTag, style: _tagStyle));
      } else if (m.group(12) != null && m.group(13) != null) {
        // Direction tags: Categorical Rebuild to prevent Tail-Biting Index Error
        final val = m.group(12)!;
        final content = m.group(13)!;
        final openTag = '[$val]';
        final closeTag = '[/$val]';
        spans.add(TextSpan(text: openTag, style: _tagStyle));
        spans.add(_buildMarkup(content, base));
        spans.add(TextSpan(text: closeTag, style: _tagStyle));
      } else if (m.group(14) != null && m.group(15) != null) {
        final family = m.group(14)!;
        TextStyle s = base ?? const TextStyle();
        try { s = GoogleFonts.getFont(family, textStyle: s); } catch (_) {}
        spans.add(TextSpan(text: '[font=$family]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(15)!, s));
        spans.add(TextSpan(text: '[/font]', style: _tagStyle));
      } else if (m.group(16) != null) {
        spans.add(TextSpan(text: m.group(16)!, style: _tagStyle));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}

// ── Editor State Model ──────────────────────────────────────────────────────

class _EditorState {
  final String text;
  final DateTime timestamp;
  final String description;
  final double lineSpacing;
  final double letterSpacing;
  final double wordSpacing;
  final int scriptBgColor;
  final int currentWordColor;
  final int futureWordColor;
  final String textAlign;

  _EditorState({
    required this.text,
    required this.timestamp,
    required this.description,
    required this.lineSpacing,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.scriptBgColor,
    required this.currentWordColor,
    required this.futureWordColor,
    required this.textAlign,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'description': description,
    'lineSpacing': lineSpacing,
    'letterSpacing': letterSpacing,
    'wordSpacing': wordSpacing,
    'scriptBgColor': scriptBgColor,
    'currentWordColor': currentWordColor,
    'futureWordColor': futureWordColor,
    'textAlign': textAlign,
  };

  factory _EditorState.fromJson(Map<String, dynamic> json) => _EditorState(
    text: json['text'] as String,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    description: json['description'] as String? ?? 'Edit',
    lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 1.0,
    letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
    wordSpacing: (json['wordSpacing'] as num?)?.toDouble() ?? 0.0,
    scriptBgColor: json['scriptBgColor'] as int? ?? 0xFF000000,
    currentWordColor: json['currentWordColor'] as int? ?? 0xFFFFBF00,
    futureWordColor: json['futureWordColor'] as int? ?? 0xFFFFFFFF,
    textAlign: json['textAlign'] as String? ?? 'center',
  );
}

// ── Main Screen ──────────────────────────────────────────────────────────────

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

enum _EditorSuite { none, text, layout, color }

class ScriptEditorScreen extends ConsumerStatefulWidget {
  final bool shouldAutoLoad;
  const ScriptEditorScreen({super.key, this.shouldAutoLoad = false});

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen> {
  final List<_MarkupController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  String _currentTitle = 'New Project';
  
  TextSelection? _lastSelection;
  _MarkupController? _lastFocusedController;
  int _lastSelectionOffset = -1;
  
  bool _isSavedToFile = false;
  String _sourceType = 'TEMP';
  int _lastFocusedIndex = 0;
  final List<_EditorState> _history = [];
  int _historyIndex = -1;
  static const int _maxHistory = 30;
  Color _lastChosenTextColor = const Color(0xFFFFBF00);
  Color _lastChosenHighlightColor = const Color(0x4DFFFFFF);

  bool _colorAsText = true;
  bool _isInit = false;
  bool _isCleaning = false; 
  bool _isGlobalSelection = false; 
  bool _isDirty = false; 
  bool _isLoading = false; 
  bool _isDebugMinimized = false;
  _EditorSuite _activeSuite = _EditorSuite.none;
  final List<String> _debugLogs = [];
  Timer? _historyTimer, _recentTimer, _autoSaveTimer;
  DateTime? _lastTap;
  int _titleTaps = 0;

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
      final currentText = _getRefinedFullText();
      if (currentText.isEmpty && _currentTitle == 'New Project') {
        return;
      }

      try {
        final text = _getRefinedFullText();
        final currentTitle = _currentTitle;
        if (!mounted) return;
        final notifier = ref.read(settingsProvider.notifier);
        await notifier.saveScript(text, title: currentTitle, historyIndex: _historyIndex);
      } catch (e) {
        final err = e.toString().toLowerCase();
        if (!err.contains('disposed') && !err.contains('defunct')) {
           debugPrint('Auto-Save Error: $e');
        }
      }
    });
  }

  String? _currentSessionId;

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

      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      _loadText(initialText);
      _currentTitle = initialTitle;

      if (script?.historyJson != null) {
        try {
          final List<dynamic> historyData = jsonDecode(script!.historyJson!);
          _history.clear();
          _history.addAll(historyData.map((d) => _EditorState.fromJson(d)));
          _historyIndex = _history.length - 1;
        } catch (e) {
          debugPrint('History Restore Error: $e');
        }
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
      for (int i = 0; i < paragraphs.length; i++) {
        _addBlock(i, text: paragraphs[i]);
      }
      if (_controllers.isEmpty) _addBlock(0);
    } finally {
      // Debounce the release so immediate focus events after load are still muted
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
    final controller = _MarkupController();
    if (text != null) controller.text = text;
    final node = FocusNode(onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      
      _debugLog('Key Event: ${event.logicalKey.debugName} (Shift: ${HardwareKeyboard.instance.isShiftPressed})');
      
      // Enter to add new block
      if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        _debugLog('Enter pressed - Triggering new block');
        _addBlock(_controllers.indexOf(controller) + 1);
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
      if (node.hasFocus) {
        _lastFocusedController = controller;
        _onSelectionChanged();
      } else if (_isDirty) {
        _saveHistory(description: 'Edit Text', debounce: false);
      }
    });

    String lastText = text ?? '';
    controller.addListener(() {
      if (_isLoading) return;
      final newText = controller.text;
      final newSelection = controller.selection;

      if (newText == lastText) {
         if (node.hasFocus) {
            _lastSelection = newSelection;
            _onSelectionChanged();
         }
         return; 
      }

      if (node.hasFocus) {
        if (_isGlobalSelection && !newSelection.isCollapsed) {
           final textLen = newText.length;
           if (newSelection.start != 0 || newSelection.end != textLen) {
              setState(() => _isGlobalSelection = false);
           }
        }
        _onSelectionChanged();
      }
      
      lastText = newText;
      _isDirty = true;
      _onBlockChanged();
    });

    setState(() {
      _controllers.insert(index, controller);
      _focusNodes.insert(index, node);
    });
  }

  void _debugLog(String message) {
    final log = '[${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}] $message';
    debugPrint('[EDITOR_DEBUG] $log');
    setState(() {
      _debugLogs.add(log);
      if (_debugLogs.length > 50) _debugLogs.removeAt(0);
    });
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final controller = _activeController;
    if (controller != null) {
       final selection = controller.selection;
       if (selection.isValid) {
         final text = selection.isCollapsed ? "|" : '"${selection.textInside(controller.text)}"';
         _debugLog('[TRACE] Selection: ${selection.start}-${selection.end} | Focal Text: $text');
       }
       
       final offset = (selection.baseOffset != -1) ? selection.baseOffset : _lastSelectionOffset;
       
       if (selection.baseOffset != -1) {
          _lastSelection = selection;
          _lastSelectionOffset = selection.baseOffset;
       }
       
       final styles = _CursorStyle(
           isBold: _detectStyleAtCursor('**', '**', offset: offset),
           isItalic: _detectStyleAtCursor('[i]', '[/i]', offset: offset),
           isUnderline: _detectStyleAtCursor('[u]', '[/u]', offset: offset),
           fontSize: _detectFontSizeAtCursor(offset: offset),
           fontFamily: _detectFontFamilyAtCursor(offset: offset),
           textAlign: _detectAlignAtCursor(offset: offset),
           direction: _detectDirectionAtCursor(offset: offset),
        );
        _debugLog('Broadcast Style: B:${styles.isBold} I:${styles.isItalic} U:${styles.isUnderline} Fs:${styles.fontSize} Align:${styles.textAlign}');
        ref.read(cursorStyleProvider.notifier).state = styles;
    }
    setState(() {});
  }

  void _scheduleRecentUpdate() {
    _recentTimer?.cancel();
    _recentTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _triggerRecentUpdate(_currentTitle, _getRefinedFullText());
      }
    });
  }

  void _onBlockChanged() {
    if (_isCleaning) return;
    _saveHistory(description: 'Edit Text', debounce: true);
    _scheduleRecentUpdate();
  }

  @override
  void dispose() {
    if (_isDirty) {
      final text = _getRefinedFullText();
      ref.read(settingsProvider.notifier).saveScript(text, title: _currentTitle, historyIndex: _historyIndex);
    }
    _historyTimer?.cancel();
    _recentTimer?.cancel();
    _autoSaveTimer?.cancel();
    _clearControllers();
    super.dispose();
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Rename Production', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New Title',
            hintStyle: const TextStyle(color: Colors.white24),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setState(() => _currentTitle = newName);
                _triggerRecentUpdate(newName, _getRefinedFullText());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename', style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getRefinedFullText() {
    return _controllers.map((c) => c.text.trim()).join('\n').trim();
  }

  void _triggerRecentUpdate(String title, String content, [int? forcedIndex]) {
    if (!mounted) return;
    if (content.trim().isEmpty && title == 'New Script') return;
    final settings = ref.read(settingsProvider);
    
    final styleRegex = RegExp(r'\[[^\]]*\]|\[[^\]]*$|\*\*');
    final cleanSnippetContent = content.replaceAll(styleRegex, '').trim();
    final snippet = cleanSnippetContent.length > 50 ? cleanSnippetContent.substring(0, 50) : cleanSnippetContent;

    final meta = jsonEncode({
      'sessionId': _currentSessionId,
      'title': title,
      'historyIndex': forcedIndex ?? _historyIndex,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'type': _sourceType,
      'snippet': snippet,
      'fullText': content,
      'historyJson': jsonEncode(_history.length > 20 ? _history.sublist(_history.length - 20) : _history),
      'style': {
        'scriptBgColor': settings.scriptBgColor,
        'currentWordColor': settings.currentWordColor,
        'futureWordColor': settings.futureWordColor,
        'lineSpacing': settings.lineSpacing,
        'letterSpacing': settings.letterSpacing,
        'wordSpacing': settings.wordSpacing,
        'fontSize': settings.fontSize,
      }
    });
    ref.read(settingsProvider.notifier).addToRecent(meta);
  }

  void _saveHistory({String description = 'Edit Text', bool debounce = false}) {
    _historyTimer?.cancel();
    if (debounce) {
      _historyTimer = Timer(const Duration(milliseconds: 300), () => _saveHistory(description: description, debounce: false));
      return;
    }

    if (!_isDirty && description == 'Edit Text') return;
    _isDirty = false;

    final fullText = _getRefinedFullText();
    final settings = ref.read(settingsProvider);
    final state = _EditorState(
      text: fullText,
      timestamp: DateTime.now(),
      description: description,
      lineSpacing: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
      scriptBgColor: settings.scriptBgColor,
      currentWordColor: settings.currentWordColor,
      futureWordColor: settings.futureWordColor,
      textAlign: settings.textAlign,
    );

    setState(() {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(state);
      if (_history.length > _maxHistory) _history.removeAt(0);
      _historyIndex = _history.length - 1;
    });

    ref.read(settingsProvider.notifier).saveScript(fullText, title: _currentTitle, historyIndex: _historyIndex);
  }

  void _undo() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _applyState(_history[_historyIndex]);
      
      final text = _getRefinedFullText();
      ref.read(settingsProvider.notifier).saveScript(text, title: _currentTitle, historyIndex: _historyIndex);
      _triggerRecentUpdate(_currentTitle, text, _historyIndex);
      _debugLog('Undo Action -> ${text.length > 20 ? text.substring(0, 20) + "..." : text}');
      if (mounted) setState(() {});
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _applyState(_history[_historyIndex]);
      
      final text = _getRefinedFullText();
      ref.read(settingsProvider.notifier).saveScript(text, title: _currentTitle, historyIndex: _historyIndex);
      _triggerRecentUpdate(_currentTitle, text, _historyIndex);
      _debugLog('Redo Action -> ${text.length > 20 ? text.substring(0, 20) + "..." : text}');
      if (mounted) setState(() {});
    }
  }

  Color? _detectColorAtCursor({required bool textColor}) {
    final controller = _activeController;
    if (controller == null) return null;
    final selection = controller.selection;
    if (!selection.isValid) return null;
    
    final text = controller.text;
    final offset = selection.start;
    final end = selection.end;
    final tag = textColor ? '[color=' : '[bg=';
    final closeTag = textColor ? '[/color]' : '[/bg]';
    
    if (!selection.isCollapsed && offset != end) {
       final selectedText = text.substring(offset, end);
       final pattern = RegExp(RegExp.escape(tag) + r'([^\]]+)\](.*?)' + RegExp.escape(closeTag), dotAll: true);
       final matches = pattern.allMatches(selectedText);
       
       Set<String> foundHexes = {};
       int taggedLength = 0;
       for (final m in matches) {
          foundHexes.add(m.group(1)!.trim().toUpperCase());
          taggedLength += m.group(0)!.length;
       }
       
       if (foundHexes.length > 1 || (foundHexes.isNotEmpty && taggedLength < selectedText.length)) {
          return const Color(0x00000000);
       }
       
       if (foundHexes.length == 1 && taggedLength == selectedText.length) {
          final hex = foundHexes.first.replaceFirst('#', '');
          return Color(int.tryParse('FF$hex', radix: 16) ?? (textColor ? 0xFFFFFFFF : 0x00000000));
       }
       
       final outerMatches = RegExp(RegExp.escape(tag) + r'([^\]]+)\]').allMatches(text);
       for (final m in outerMatches) {
          if (m.start <= offset) {
             final nextClose = text.indexOf(closeTag, m.end);
             if (nextClose != -1 && nextClose >= end) {
                final hex = m.group(1)!.trim().replaceFirst('#', '');
                return Color(int.tryParse('FF$hex', radix: 16) ?? (textColor ? 0xFFFFFFFF : 0x00000000));
             }
          }
       }
       return const Color(0x00000000);
    }

    final matches = RegExp(RegExp.escape(tag) + r'([^\]]+)\]').allMatches(text);
    Color? found;
    for (final m in matches) {
      if (m.start <= offset) {
         final nextClose = text.indexOf(closeTag, m.end);
         if (nextClose == -1 || nextClose >= offset) {
            final hex = m.group(1)!.trim().replaceFirst('#', '');
            found = Color(int.tryParse('FF$hex', radix: 16) ?? (textColor ? 0xFFFFFFFF : 0x00000000));
         }
      }
    }
    return found ?? const Color(0x00000000);
  }

  int _detectFontSizeAtCursor({int? offset}) {
    final controller = _activeController;
    if (controller == null) return 18;
    final text = controller.text;
    final off = offset ?? controller.selection.baseOffset;
    if (off < 0) return 18;

    final matches = RegExp(r'\[size=(\d+)\]').allMatches(text);
    int found = 18;
    for (final m in matches) {
      if (m.start <= off) {
         final nextClose = text.indexOf('[/size]', m.end);
         if (nextClose == -1 || nextClose >= off) {
            found = int.tryParse(m.group(1)!) ?? 18;
         }
      }
    }
    return found;
  }

  String _detectFontFamilyAtCursor({int? offset}) {
    final controller = _activeController;
    if (controller == null) return 'Inter';
    final text = controller.text;
    final off = offset ?? controller.selection.baseOffset;
    if (off < 0) return 'Inter';

    final matches = RegExp(r'\[font=([^\]]+)\]').allMatches(text);
    String found = 'Inter';
    for (final m in matches) {
      if (m.start <= off) {
         final nextClose = text.indexOf('[/font]', m.end);
         if (nextClose == -1 || nextClose >= off) {
            found = m.group(1)!;
         }
      }
    }
    return found;
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
         if (nextClose == -1 || nextClose == text.indexOf('[/align=$val]', m.end) || nextClose >= off) {
            found = val;
         }
      }
    }
    
    if (found == 'left') {
       for (final m in dirMatches) {
          if (m.start <= off) {
             final nextClose = text.indexOf('[/${m.group(1)}]', m.end);
             if (nextClose == -1 || nextClose >= off) {
                if (m.group(1) == 'rtl') found = 'right';
             }
          }
       }
    }
    return found;
  }

  String _detectDirectionAtCursor({required int offset}) {
    if (_detectStyleAtCursor('[rtl]', '[/rtl]', offset: offset)) return 'rtl';
    return 'ltr';
  }

  bool _detectStyleAtCursor(String open, String close, {int? offset}) {
    final controller = _activeController;
    if (controller == null) return false;
    final text = controller.text;
    
    // v3.35.5: Smart Probe Point - look at the first character inside the selection if applicable
    int off = offset ?? controller.selection.start;
    if (controller.selection.isValid && !controller.selection.isCollapsed && offset == null) {
       off = (controller.selection.start + 1).clamp(0, text.length);
    }
    if (off < 0 || off > text.length) return false;

    // v3.35.5: High-Fidelity Backward Traversal (Handles Nested Hierarchy)
    final tagIdx = text.lastIndexOf(open, off);
    if (tagIdx == -1) return false;
    
    // Ensure this specific tag wasn't closed before reaching the probe point
    final exitIdx = text.indexOf(close, tagIdx);
    return exitIdx == -1 || exitIdx >= off;
  }

  void _applyState(_EditorState state) {
    _loadText(state.text);
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setLineSpacing(state.lineSpacing);
    notifier.setLetterSpacing(state.letterSpacing);
    notifier.setWordSpacing(state.wordSpacing);
    notifier.setScriptBgColor(state.scriptBgColor);
    notifier.setCurrentWordColor(state.currentWordColor);
    notifier.setFutureWordColor(state.futureWordColor);
    notifier.setTextAlign(state.textAlign);
    if (mounted) setState(() {});
  }

  _MarkupController? get _activeController {
    for (var i=0; i<_focusNodes.length; i++) {
        if (_focusNodes[i].hasFocus) return _controllers[i];
    }
    return _lastFocusedController ?? (_controllers.isNotEmpty ? _controllers.last : null);
  }

  void _wrapSelection(String open, String close, {bool isToggle = true}) {
    final controller = _activeController;
    if (controller == null) return;
    
    TextSelection selection = controller.selection;
    if ((!selection.isValid || selection.isCollapsed) && _lastSelection != null && controller == _lastFocusedController) {
       selection = _lastSelection!;
    }

    if (!selection.isValid) return;

    final text = controller.text;

    if (selection.isCollapsed && text.isNotEmpty && !_isGlobalSelection) {
       int start = selection.start;
       int end = selection.start;
       while (start > 0 && !RegExp(r'\s|\[|\]').hasMatch(text[start - 1])) start--;
       while (end < text.length && !RegExp(r'\s|\[|\]').hasMatch(text[end])) end++;
       if (start != end) {
          selection = TextSelection(baseOffset: start, extentOffset: end);
       }
    }

    if (_isGlobalSelection) {
       setState(() => _isCleaning = true);
       try {
          for (final c in _controllers) {
             if (c.text.isEmpty) continue;
             c.text = '$open${c.text.replaceAll(RegExp(r'\[.*?\]|\*\*'), '')}$close';
          }
       } finally {
          setState(() { 
             _isCleaning = false; 
             _isGlobalSelection = false; 
          });
       }
       _saveHistory(description: 'Global Format');
       return;
    }

     if (selection.isCollapsed) return;
    final selectedText = text.substring(selection.start, selection.end);
    
    bool isToggling = false;
    if (open.isNotEmpty && close.isNotEmpty && isToggle) {
       final prefix = text.substring(0, selection.start);
       final suffix = text.substring(selection.end);
       if (prefix.endsWith(open) && suffix.startsWith(close)) {
          final newText = text.replaceRange(selection.end, selection.end + close.length, '');
          final finalText = newText.replaceRange(selection.start - open.length, selection.start, '');
          controller.value = TextEditingValue(
            text: finalText,
            selection: TextSelection(baseOffset: selection.start - open.length, extentOffset: selection.end - open.length),
          );
          isToggling = true;
       } else if (selectedText.startsWith(open) && selectedText.endsWith(close)) {
          final inner = selectedText.substring(open.length, selectedText.length - close.length);
          final newText = text.replaceRange(selection.start, selection.end, inner);
          controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection(baseOffset: selection.start, extentOffset: selection.start + inner.length),
          );
          isToggling = true;
       }
    }

    if (!isToggling) {
      String processedText = selectedText;
      
      final isColor = open.startsWith('[color=');
      final isBg = open.startsWith('[bg=');
      final isAlign = open.contains('align=') || open.startsWith('[center') || open.startsWith('[left') || open.startsWith('[right');
      final isDir = open.startsWith('[rtl') || open.startsWith('[ltr');
      final isSize = open.startsWith('[size=');
      final isFont = open.startsWith('[font=');
      final isBold = (open == '**');
      final isItalic = (open == '[i]');
      final isUnderline = (open == '[u]');

      if (isColor || isBg || isAlign || isDir || isSize || isFont || isBold || isItalic || isUnderline) {
         String openPattern;
         String closePattern;
         
         if (isColor) { openPattern = r'\[color=[^\]]+\]'; closePattern = r'\[\/color\]'; }
         else if (isBg) { openPattern = r'\[bg=[^\]]+\]'; closePattern = r'\[\/bg\]'; }
         else if (isAlign) { openPattern = r'\[(?:align=)?(?:center|left|right)\]'; closePattern = r'\[\/(?:align=)?(?:center|left|right)\]'; }
         else if (isDir) { openPattern = r'\[(?:rtl|ltr)\]'; closePattern = r'\[\/(?:rtl|ltr)\]'; }
         else if (isSize) { openPattern = r'\[size=\d+\]'; closePattern = r'\[\/size\]'; }
         else if (isFont) { openPattern = r'\[font=[^\]]+\]'; closePattern = r'\[\/font\]'; }
         else if (isBold) { openPattern = r'\*\*'; closePattern = r'\*\*'; }
         else if (isItalic) { openPattern = r'\[i\]'; closePattern = r'\[\/i\]'; }
         else { openPattern = r'\[u\]'; closePattern = r'\[\/u\]'; }

         final prefix = text.substring(0, selection.start);
         final suffix = text.substring(selection.end);
         
         final match = RegExp(openPattern).allMatches(prefix).lastOrNull;
         if (match != null) {
            final closeMatch = RegExp(closePattern).allMatches(text).where((m) => m.start >= selection.end).firstOrNull;
            if (closeMatch != null) {
               final tagStart = match.start;
               final tagEnd = closeMatch.end;
               final innerContent = text.substring(match.end, closeMatch.start);
               
               if (match.group(0) == open) {
                  final finalNewText = text.replaceRange(tagStart, tagEnd, innerContent);
                  controller.value = TextEditingValue(
                     text: finalNewText,
                     selection: TextSelection(baseOffset: selection.start - (match.group(0)!.length), extentOffset: selection.end - (match.group(0)!.length)),
                  );
                  _saveHistory(description: 'Toggle Style');
                  _onSelectionChanged();
                  return;
               }
            }
         }

         // v3.25.0: Non-Destructive Tag Guard - only strip tags that exactly match the target style type
         // prevent highlight application from stripping bold or color tags
         processedText = processedText.replaceAll(RegExp(openPattern + '|' + closePattern), '');
      }

      processedText = open + processedText + close;
      _debugLog('Wrapping: $open...$close | Selection: ${selection.start}-${selection.end}');
      
      final newText = text.replaceRange(selection.start, selection.end, processedText);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: selection.start, extentOffset: selection.start + processedText.length),
      );
    }
    _saveHistory(description: 'Format Text');
    _onSelectionChanged();
  }

  void _handleBgColorChange(int color) {
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    _saveHistory(description: 'Change Background', debounce: true);
    if (mounted) setState(() {});
  }

  void _onBold() => _wrapSelection('**', '**');
  void _onUnderline() => _wrapSelection('[u]', '[/u]');
  void _onItalic() => _wrapSelection('[i]', '[/i]');
  void _onAlign(String align) {
     if (_activeController == null) return;
     final currentStyle = _detectCurrentStyle();
     if (currentStyle.textAlign == align) return; // Selection Lock: don't toggle off

     if (_isGlobalSelection) {
        setState(() => _isCleaning = true);
        try {
           for (final c in _controllers) {
              final clean = c.text.replaceAll(RegExp(r'\[(?:center|left|right)\]|\[\/(?:center|left|right)\]'), '');
              c.text = '[$align]$clean[/$align]';
           }
        } finally {
           setState(() { _isCleaning = false; _isGlobalSelection = false; });
        }
        _saveHistory(description: 'Global Align');
     } else {
        // Strict replacement: clean existing alignment tags before applying new one
        _wrapSelection('[$align]', '[/$align]', isToggle: false);
     }
  }

  void _onDirection(String dir) {
     if (_activeController == null) return;
     final currentStyle = _detectCurrentStyle();
     if (currentStyle.direction == dir) return; // Selection Lock: don't toggle off

     // Strict replacement: clean existing direction tags before applying new one
     _wrapSelection('[$dir]', '[/$dir]', isToggle: false);
  }
  void _onFontSize(int size) => _wrapSelection('[size=$size]', '[/size]');
  void _onFontFamily(String family) => _wrapSelection('[font=$family]', '[/font]');

  void _onTextColorSelected(String hex) {
     final cleanHex = hex.replaceFirst('#', '').toUpperCase();
     final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0xFFFFBF00);
     setState(() => _lastChosenTextColor = color);
     ref.read(settingsProvider.notifier).setLastChosenTextColor(color.value);
     _wrapSelection('[color=#$cleanHex]', '[/color]');
  }

  void _onBgColorSelected(String hex) {
     final cleanHex = hex.replaceFirst('#', '').toUpperCase();
     final color = Color(int.tryParse('FF$cleanHex', radix: 16) ?? 0x00000000);
     setState(() => _lastChosenHighlightColor = color);
     ref.read(settingsProvider.notifier).setLastChosenHighlightColor(color.value);
     _wrapSelection('[bg=#$cleanHex]', '[/bg]');
  }

  Future<void> _importFile() async {
    const supportedExts = ['rtf', 'pdf', 'docx', 'doc', 'odt', 'txt', 'md', 'log', 'text'];
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (!mounted || result == null || result.files.single.path == null) return;
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

    final String content = await ref.read(scriptProvider.notifier).parseFile(selectedFile);
    if (!mounted) return;
    final title = selectedFile.path.split('/').last;
    final settings = ref.read(settingsProvider);
    Map<String, dynamic>? conflictMeta;

    for (final item in settings.recentScripts) {
      try {
        final meta = jsonDecode(item);
        if (meta['title'] == title) {
          final bool contentMatch = meta['fullText'] == content;
          if (!contentMatch) conflictMeta = meta;
          break;
        }
      } catch (_) {}
    }

    if (conflictMeta != null) {
      final choice = await _showConflictDialog(title, conflictMeta);
      if (!mounted || choice == null) return;
      if (choice == 'history') {
        _isLoading = true;
        _loadText(conflictMeta['fullText']);
        _currentTitle = title;
        _sourceType = conflictMeta['type'] ?? 'FILE';
        _currentSessionId = conflictMeta['sessionId'];
        
        if (conflictMeta.containsKey('historyJson')) {
           try {
             final List<dynamic> historyData = jsonDecode(conflictMeta['historyJson']);
             _history.clear();
             for (var item in historyData) {
                _history.add(_EditorState.fromJson(item));
             }
             _historyIndex = conflictMeta['historyIndex'] ?? _history.length - 1;
             
             if (_historyIndex >= 0 && _historyIndex < _history.length) {
                _applyState(_history[_historyIndex]);
             }
           } catch (e) {
             debugPrint('History Restoration Failed: $e');
           }
        }

        if (conflictMeta.containsKey('style')) {
           ref.read(settingsProvider.notifier).applySessionStyles(conflictMeta['style']);
        }
        
        _scheduleRecentUpdate();
        setState(() {});
        return;
      }
    }

    await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
    if (!mounted) return;
    await ref.read(scriptProvider.notifier).importFile(selectedFile);
    if (!mounted) return;
    final script = ref.read(scriptProvider);
    if (script != null) {
      _loadText(script.rawText);
      _currentTitle = script.title;
      _sourceType = script.sourceType;
      _saveHistory(description: 'Import File');
      _scheduleRecentUpdate();
      setState(() {});
    }
  }

  Future<String?> _showConflictDialog(String title, Map<String, dynamic> history) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(children: [
          Icon(Icons.history_edu_rounded, color: Color(0xFFFFBF00)),
          SizedBox(width: 10),
          Text("Conflict Detected", style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          "The script '$title' has been modified outside the app or has an existing history version.\n\n"
          "Would you like to discard your previous in-app edits or keep the history version?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reload'),
            child: const Text("RELOAD & DISCARD", style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'history'),
            child: const Text("KEEP HISTORY", style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveScript() async {
    final text = _getRefinedFullText();
    if (text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Script is empty.')));
      return;
    }

    final format = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Save Format', style: TextStyle(color: Colors.white)),
        content: const Text('Choose format:', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'pdf'), child: const Text('PDF (.pdf)')),
          TextButton(onPressed: () => Navigator.pop(context, 'docx'), child: const Text('Word (.docx)')),
          TextButton(onPressed: () => Navigator.pop(context, 'rtf'), child: const Text('Rich Text (.rtf)')),
          TextButton(onPressed: () => Navigator.pop(context, 'txt'), child: const Text('Plain Text (.txt)')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
    if (format == null || !mounted) return;

    final nameCtrl = TextEditingController(text: 'my_script');
    final prefs = await SharedPreferences.getInstance();
    final usedNames = prefs.getStringList('used_script_names') ?? [];
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SaveNameDialog(nameCtrl: nameCtrl, usedNames: usedNames, format: format),
    );
    if (result == null || !mounted) return;
    final String chosenName = result['name'];

    final List<int> bytes = format == 'docx' 
        ? DocxService.generate(text)
        : format == 'rtf' 
            ? utf8.encode(_toRtf(text)) 
            : utf8.encode(text);

    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save script',
        fileName: '$chosenName.$format',
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      if (savedPath != null) {
        _isSavedToFile = true;
        _sourceType = format.toUpperCase();
        if (!usedNames.contains(chosenName)) {
           usedNames.add(chosenName);
           await prefs.setStringList('used_script_names', usedNames);
        }
        await ref.read(settingsProvider.notifier).saveScript(text);
        if (!mounted) return;
        _currentTitle = chosenName;
        _triggerRecentUpdate(chosenName, text);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!'), backgroundColor: Color(0xFF2A6B2A)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  void _clearScript() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Clear script?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _loadText('');
              ref.read(scriptProvider.notifier).loadText('');
              _saveHistory(description: 'Clear');
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _startPresenting() {
    final text = _getRefinedFullText().trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter text first.')));
      return;
    }
    ref.read(scriptProvider.notifier).loadText(text);
    ref.read(teleprompterProvider.notifier).resetPosition();
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const TeleprompterScreen(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  String _toRtf(String text) {
    String processed = text.replaceAllMapped(RegExp(r'\*\*([^\*]+)\*\*'), (m) => '\\b ${m[1]}\\b0 ');
    final buf = StringBuffer();
    buf.write(r'{\rtf1\ansi\ansicpg65001\uc0' '\n');
    buf.write(r'{\fonttbl\f0\froman\fcharset0 TimesNewRoman;}' '\n');
    buf.write(r'\f0\fs28' '\n');
    for (final line in processed.split('\n')) {
      if (line.isEmpty) { buf.write(r'\par' '\n'); continue; }
      for (final char in line.runes) {
        if (char > 127) {
          buf.write('\\u${char > 32767 ? char - 65536 : char}?');
        } else {
          final c = String.fromCharCode(char);
          if (c == '\\' || c == '{' || c == '}') buf.write('\\');
          buf.write(c);
        }
      }
      buf.write(r'\par' '\n');
    }
    buf.write('}');
    return buf.toString();
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
        title: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                IconButton(icon: const Icon(Icons.videocam, color: Color(0xFFFFBF00)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContentCreatorScreen()))),
                IconButton(icon: const Icon(Icons.settings), onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const LobbySettingsPanel())),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearScript),
                IconButton(icon: const Icon(Icons.save_alt), onPressed: _saveScript),
                IconButton(icon: const Icon(Icons.folder_open), onPressed: _importFile),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(_currentTitle.trim(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFFFBF00)), onPressed: _showRenameDialog),
              ],
            ),
          ],
        ),
      ),
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
                  setState(() => _isGlobalSelection = true);
                  return null;
                }),
                _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (intent) {
                  _onCopyClean();
                  return null;
                }),
              },
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: _FormattingToolbar(
                    onBold: () {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Bold Suite Clicked | Target: $text');
                      _onBold();
                    },
                    onUnderline: () {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Underline Suite Clicked | Target: $text');
                      _onUnderline();
                    },
                    onItalic: () {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Italic Suite Clicked | Target: $text');
                      _onItalic();
                    },
                    onClear: () {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Paragraph';
                      _debugLog('[ACTION] Clear Style Clicked | Target: $text');
                      final controller = _activeController;
                      if (controller == null) return;
                      final selection = controller.selection;
                      final styleRegex = RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
                      if (selection == null || !selection.isValid || selection.isCollapsed) {
                        setState(() => _isCleaning = true);
                        try {
                          for (final c in _controllers) c.text = c.text.replaceAll(styleRegex, '');
                          ref.read(settingsProvider.notifier).setScriptBgColor(0xFF000000);
                          _saveHistory(description: 'Hard Reset Styles & Background', debounce: false);
                        } finally {
                          setState(() => _isCleaning = false);
                        }
                      } else {
                        final fullText = controller.text;
                        final cleanedText = fullText.replaceAll(styleRegex, '');
                        controller.value = TextEditingValue(text: cleanedText, selection: const TextSelection.collapsed(offset: 0));
                        _saveHistory(description: 'Clear Paragraph Styles');
                      }
                      _onSelectionChanged();
                    },
                    onFontSize: (v) {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Font Size ($v) | Target: $text');
                      _onFontSize(v);
                    },
                    onAlign: (v) {
                      _debugLog('[ACTION] Align Suite ($v) applied to paragraph');
                      _onAlign(v);
                    },
                    onDirection: (v) {
                      _debugLog('[ACTION] Direction Suite ($v) applied to paragraph');
                      _onDirection(v);
                    },
                    onTextColor: (v) {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Text Color ($v) | Target: $text');
                      _onTextColorSelected(v);
                    },
                    onBgColor: (v) {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Highlight Color ($v) | Target: $text');
                      _onBgColorSelected(v);
                    },
                    onFontFamily: (v) {
                      final sel = _activeController?.selection;
                      final text = (sel != null && sel.isValid) ? '"${sel.textInside(_activeController!.text)}"' : 'Nothing';
                      _debugLog('[ACTION] Font Family ($v) | Target: $text');
                      _onFontFamily(v);
                    },
                    lastTextColor: _detectColorAtCursor(textColor: true) ?? _lastChosenTextColor,
                    lastHighlightColor: _detectColorAtCursor(textColor: false) ?? _lastChosenHighlightColor,
                    onBgColorChange: _handleBgColorChange,
                    onUndo: () { 
                      _debugLog('[ACTION] Undo Pressed');
                      _undo(); 
                      _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), _historyIndex); 
                    },
                    onRedo: () { 
                      _debugLog('[ACTION] Redo Pressed');
                      _redo(); 
                      _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), _historyIndex); 
                    },
                    history: _history,
                    historyIndex: _historyIndex,
                    onHistorySelected: (idx) {
                       _debugLog('[ACTION] History Restore: $idx');
                       setState(() { _historyIndex = idx; _applyState(_history[idx]); });
                       _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), idx);
                    },
                    canUndo: _historyIndex > 0,
                    canRedo: _historyIndex < _history.length - 1,
                    activeSuite: _activeSuite,
                    onSuiteToggle: (suite) {
                      setState(() {
                         _activeSuite = (_activeSuite == suite) ? _EditorSuite.none : suite;
                      });
                    },
                  ),
                ),
                Expanded(
                    child: Container(
                      color: Color(settings.scriptBgColor),
                      child: Shortcuts(
                        shortcuts: {
                          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
                          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA): const _SelectAllIntent(),
                        },
                        child: Actions(
                          actions: {
                            _SelectAllIntent: CallbackAction<_SelectAllIntent>(onInvoke: (intent) {
                              setState(() => _isGlobalSelection = true);
                              return null;
                            }),
                          },
                          child: ListView.builder(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
                            itemCount: _controllers.length,
                            itemBuilder: (context, index) => _EditorBlock(
                              key: ValueKey(_controllers[index].hashCode),
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              settings: settings,
                              isGlobalSelected: _isGlobalSelection,
                              onSubmitted: () => _addBlock(index + 1),
                              onDelete: () {
                                if (_controllers.length > 1) {
                                  setState(() {
                                    _controllers.removeAt(index).dispose();
                                    _focusNodes.removeAt(index).dispose();
                                    if (index > 0) _focusNodes[index-1].requestFocus();
                                  });
                                }
                              },
                              onTap: () {
                                setState(() {
                                  _isGlobalSelection = false;
                                });
                              },
                              onSelectAll: () {
                                setState(() => _isGlobalSelection = true);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _EditorStatusBar(
                    wordCount: _getRefinedFullText().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length,
                    scrollSpeed: ref.watch(settingsProvider).scrollSpeed,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _startPresenting,
                        icon: const Icon(Icons.play_arrow_rounded, size: 28),
                        label: const Text('Start Presenting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFBF00), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_activeSuite != _EditorSuite.none)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _activeSuite = _EditorSuite.none),
                child: Container(color: Colors.transparent),
              ),
            ),
          if (_activeSuite != _EditorSuite.none)
            Positioned(
              bottom: 110,
              left: 12,
              right: 12,
              child: _buildActiveSuite(),
            ),
          _buildDebugConsole(),
        ],
      ),
    );
  }

  void _onCopyClean() {
    final controller = _activeController;
    if (controller == null) return;
    final selection = controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final text = selection.textInside(controller.text);
      final tagsRegex = RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
      final cleaned = text.replaceAll(tagsRegex, '');
      Clipboard.setData(ClipboardData(text: cleaned));
      _debugLog('[ACTION] Clean Copy: "$cleaned"');
    }
  }

  Widget _buildActiveSuite() {
    final style = _detectCurrentStyle();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFBF00), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_activeSuite.name.toUpperCase(), style: const TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                onPressed: () => setState(() => _activeSuite = _EditorSuite.none),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white12, height: 1)),
          if (_activeSuite == _EditorSuite.text)
            _TextMenu(onBold: _onBold, onItalic: _onItalic, onUnderline: _onUnderline, onClear: () {}, onFontSize: _onFontSize, onFontFamily: _onFontFamily),
          if (_activeSuite == _EditorSuite.layout)
             _LayoutMenu(onAlign: _onAlign, onDirection: _onDirection),
          if (_activeSuite == _EditorSuite.color)
             _ColorMenu(onTextColor: _onTextColorSelected, onBgColor: _onBgColorSelected, lastTextColor: style.textColor ?? _lastChosenTextColor, lastHighlightColor: style.highlightColor ?? _lastChosenHighlightColor, onBgColorChange: _handleBgColorChange),
        ],
      ),
    );
  }

  _CursorStyle _detectCurrentStyle() {
    final controller = _activeController;
    if (controller == null) return _CursorStyle(isBold: false, isItalic: false, isUnderline: false, fontSize: 18, fontFamily: 'Inter', textAlign: 'center', direction: 'ltr');
    
    final selection = controller.selection;
    final offset = selection.isValid ? selection.start : 0;
    
    return _CursorStyle(
      isBold: _detectStyleAtCursor('**', '**', offset: offset),
      isItalic: _detectStyleAtCursor('_', '_', offset: offset),
      isUnderline: _detectStyleAtCursor('<u>', '</u>', offset: offset),
      fontSize: _detectIntAtCursor('size=', 18, offset: offset),
      fontFamily: _detectStringAtCursor('font=', 'Inter', offset: offset),
      textAlign: _detectAlignmentAtCursor(offset: offset),
      direction: _detectDirectionAtCursor(offset: offset),
      textColor: _detectColorAtCursor(textColor: true),
      highlightColor: _detectColorAtCursor(textColor: false),
    );
  }

  String _detectAlignmentAtCursor({required int offset}) {
    if (_detectStyleAtCursor('[center]', '[/center]', offset: offset)) return 'center';
    if (_detectStyleAtCursor('[right]', '[/right]', offset: offset)) return 'right';
    return 'left';
  }


  Widget _buildDebugConsole() {
    if (_isDebugMinimized) {
      return Positioned(
        bottom: 70,
        left: 10,
        child: GestureDetector(
          onTap: () => setState(() => _isDebugMinimized = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.analytics_outlined, size: 16, color: Colors.black),
                const SizedBox(width: 6),
                const Text('Sentry Logs', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      bottom: 60,
      left: 6,
      right: 6,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange, width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: const BoxDecoration(color: Color(0xFF1A1A00), borderRadius: BorderRadius.vertical(top: Radius.circular(9))),
              child: Row(
                children: [
                  const Text('📡 EDITOR SENTRY', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.content_copy, color: Colors.orange, size: 12),
                    label: const Text('COPY LOGS', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _debugLogs.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied!')));
                    },
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.remove, color: Colors.orange, size: 12),
                    label: const Text('HIDE', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                    onPressed: () => setState(() => _isDebugMinimized = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(8),
                itemCount: _debugLogs.length,
                itemBuilder: (context, idx) {
                  final log = _debugLogs[_debugLogs.length - 1 - idx];
                  return Text(log, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _detectIntAtCursor(String prefix, int defaultValue, {required int offset}) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final openTag = '[' + prefix;
    
    // v3.35.6: Probing inside selection if applicable to catch nested tags
    final off = (controller.selection.isValid && !controller.selection.isCollapsed && offset == controller.selection.start)
        ? (offset + 1).clamp(0, text.length)
        : offset;

    final tagIdx = text.lastIndexOf(openTag, off);
    if (tagIdx == -1) return defaultValue;
    
    final closeBracket = text.indexOf(']', tagIdx);
    if (closeBracket == -1 || closeBracket > off) return defaultValue;
    
    final tagName = prefix.split('=').first;
    final closeTag = '[/' + tagName + ']';
    
    final exitIdx = text.indexOf(closeTag, tagIdx);
    if (exitIdx != -1 && exitIdx < off) return defaultValue;
    
    final val = text.substring(tagIdx + openTag.length, closeBracket);
    return int.tryParse(val) ?? defaultValue;
  }

  String _detectStringAtCursor(String prefix, String defaultValue, {required int offset}) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final openTag = '[' + prefix;

    // v3.35.7: Selection-Aware Probe to catch nested tags past selection boundaries
    final off = (controller.selection.isValid && !controller.selection.isCollapsed && offset == controller.selection.start)
        ? (offset + 1).clamp(0, text.length)
        : offset;
    
    final tagIdx = text.lastIndexOf(openTag, off);
    if (tagIdx == -1) return defaultValue;
    
    final closeBracket = text.indexOf(']', tagIdx);
    if (closeBracket == -1 || closeBracket > off) return defaultValue;
    
    final tagName = prefix.replaceAll('=', '');
    final closeTag = '[/' + tagName + ']';
    
    final exitIdx = text.indexOf(closeTag, tagIdx);
    if (exitIdx != -1 && exitIdx < off) return defaultValue;
    
    return text.substring(tagIdx + openTag.length, closeBracket);
  }
}

class _EditorStatusBar extends StatelessWidget {
  final int wordCount;
  final double scrollSpeed;
  const _EditorStatusBar({required this.wordCount, required this.scrollSpeed});
  String _formatDuration(int words, double speed) {
    if (words == 0) return "0:00";
    final durationMinutes = words / (160.0 * (speed / 100.0 > 0 ? speed / 100.0 : 1.0));
    final seconds = (durationMinutes * 60).round();
    return "${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}";
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Words: $wordCount", style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Row(children: [const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFFFBF00)), const SizedBox(width: 4), Text("Est. Duration: ${_formatDuration(wordCount, scrollSpeed)}", style: const TextStyle(color: Color(0xFFFFBF00), fontSize: 12, fontWeight: FontWeight.bold))]),
        ],
      ),
    );
  }
}

class _FormattingToolbar extends StatelessWidget {
  final VoidCallback onBold, onUnderline, onItalic, onClear, onUndo, onRedo;
  final ValueChanged<int> onFontSize;
  final ValueChanged<String> onAlign, onDirection, onTextColor, onBgColor, onFontFamily;
  final ValueChanged<int> onBgColorChange;
  final Color lastTextColor, lastHighlightColor;
  final bool canUndo, canRedo;
  final List<_EditorState> history;
  final int historyIndex;
  final ValueChanged<int> onHistorySelected;
  final _EditorSuite activeSuite;
  final ValueChanged<_EditorSuite> onSuiteToggle;

  const _FormattingToolbar({required this.onBold, required this.onUnderline, required this.onItalic, required this.onClear, required this.onFontSize, required this.onAlign, required this.onDirection, required this.onTextColor, required this.onBgColor, required this.onFontFamily, required this.onBgColorChange, required this.lastTextColor, required this.lastHighlightColor, required this.onUndo, required this.onRedo, required this.canUndo, required this.canRedo, required this.history, required this.historyIndex, required this.onHistorySelected, required this.activeSuite, required this.onSuiteToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _ToolBtn(label: '⎌', tooltip: 'Undo', onTap: onUndo, color: canUndo ? Colors.white : Colors.white10),
          const SizedBox(width: 8),
          _ToolBtn(label: '↻', tooltip: 'Redo', onTap: onRedo, color: canRedo ? Colors.white : Colors.white10),
          const SizedBox(width: 2),
          _HistoryMenu(history: history, historyIndex: historyIndex, onHistorySelected: onHistorySelected),
          const SizedBox(width: 24),
          _ToolBtn(label: 'C', tooltip: 'Clear All Formatting', onTap: onClear, color: Colors.redAccent),
          const SizedBox(width: 16),
          _FormatPopup(label: 'TEXT', icon: Icons.text_fields_rounded, active: activeSuite == _EditorSuite.text, onTap: () => onSuiteToggle(_EditorSuite.text)),
          const SizedBox(width: 16),
          _FormatPopup(label: 'LAYOUT', icon: Icons.format_align_center_rounded, active: activeSuite == _EditorSuite.layout, onTap: () => onSuiteToggle(_EditorSuite.layout)),
          const SizedBox(width: 16),
          _FormatPopup(label: 'COLOR', icon: Icons.palette_rounded, active: activeSuite == _EditorSuite.color, onTap: () => onSuiteToggle(_EditorSuite.color)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _FormatPopup extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _FormatPopup({required this.label, required this.icon, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: active ? Colors.white12 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? const Color(0xFFFFBF00) : Colors.white70, size: 20),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: active ? const Color(0xFFFFBF00) : Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _HistoryMenu extends StatelessWidget {
  final List<_EditorState> history;
  final int historyIndex;
  final ValueChanged<int> onHistorySelected;
  const _HistoryMenu({required this.history, required this.historyIndex, required this.onHistorySelected});
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    icon: Icon(Icons.history, size: 20, color: history.isEmpty ? Colors.white10 : Colors.white70),
    color: const Color(0xFF1F1F1F),
    onSelected: onHistorySelected,
    itemBuilder: (_) => history.asMap().entries.toList().reversed.map((e) => PopupMenuItem(value: e.key, child: Text('${e.value.description} (${e.value.timestamp.hour}:${e.value.timestamp.minute.toString().padLeft(2,"0")})', style: TextStyle(color: e.key == historyIndex ? const Color(0xFFFFBF00) : Colors.white70, fontSize: 13)))).toList(),
  );
}

class _TextMenu extends ConsumerWidget {
  final VoidCallback onBold, onItalic, onUnderline, onClear;
  final ValueChanged<int> onFontSize;
  final ValueChanged<String> onFontFamily;
  const _TextMenu({required this.onBold, required this.onItalic, required this.onUnderline, required this.onClear, required this.onFontSize, required this.onFontFamily});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(cursorStyleProvider);
    return Row(children: [
      _ToolBtn(label: 'B', tooltip: 'Bold', onTap: onBold, bold: true, active: style.isBold), 
      _ToolBtn(label: 'I', tooltip: 'Italic', onTap: onItalic, italic: true, active: style.isItalic), 
      _ToolBtn(label: 'U', tooltip: 'Underline', onTap: onUnderline, underline: true, active: style.isUnderline), 
      const SizedBox(width: 8), 
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)), 
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: style.fontSize, 
            dropdownColor: const Color(0xFF1F1F1F), 
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54), 
            style: const TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold, fontSize: 12), 
            onChanged: (v) { if (v != null) onFontSize(v); }, 
            items: [14, 18, 24, 28, 32, 40, 48, 56, 64, 72, 80, 96, 120].map((s) => DropdownMenuItem(value: s, child: Text('${s}px'))).toList()
          )
        )
      ), 
      const SizedBox(width: 8), 
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)), 
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: style.fontFamily, 
            dropdownColor: const Color(0xFF1F1F1F), 
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54), 
            style: const TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold, fontSize: 12), 
            onChanged: (v) { if (v != null) onFontFamily(v); }, 
            items: ['Inter', 'Roboto', 'Outfit', 'Montserrat', 'Open Sans', 'Lato'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList()
          )
        )
      ), 
    ]);
  }
}

class _LayoutMenu extends ConsumerWidget {
  final ValueChanged<String> onAlign, onDirection;
  const _LayoutMenu({required this.onAlign, required this.onDirection});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final style = ref.watch(cursorStyleProvider);

    return Column(mainAxisSize: MainAxisSize.min, children: [
       Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ToolBtnIcon(icon: Icons.format_align_left, tooltip: 'Align Left', onTap: () => onAlign('left'), active: style.textAlign == 'left'), 
          _ToolBtnIcon(icon: Icons.format_align_center, tooltip: 'Align Center', onTap: () => onAlign('center'), active: style.textAlign == 'center'), 
          _ToolBtnIcon(icon: Icons.format_align_right, tooltip: 'Align Right', onTap: () => onAlign('right'), active: style.textAlign == 'right')
       ]), 
       const SizedBox(height: 16), 
       _SliderRow(label: 'Line Spacing', value: settings.lineSpacing, min: 1.0, max: 3.0, onChanged: (v) => notifier.setLineSpacing(v)), 
       _SliderRow(label: 'Letter Spacing', value: settings.letterSpacing, min: -1.0, max: 5.0, onChanged: (v) => notifier.setLetterSpacing(v)), 
       _SliderRow(label: 'Word Spacing', value: settings.wordSpacing, min: 0, max: 20, onChanged: (v) => notifier.setWordSpacing(v)), 
       const SizedBox(height: 16), 
       Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ToolBtnIcon(icon: Icons.format_textdirection_l_to_r, tooltip: 'LTR', onTap: () => onDirection('ltr'), active: style.direction == 'ltr'), 
          const SizedBox(width: 20), 
          _ToolBtnIcon(icon: Icons.format_textdirection_r_to_l, tooltip: 'RTL', onTap: () => onDirection('rtl'), active: style.direction == 'rtl')
       ])
    ]);
  }
}

class _ToolBtn extends StatelessWidget {
  final String label, tooltip;
  final VoidCallback onTap;
  final Color? color;
  final bool bold, italic, underline, active;
  const _ToolBtn({required this.label, required this.tooltip, required this.onTap, this.color, this.bold = false, this.italic = false, this.underline = false, this.active = false});
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: active ? const Color(0xFFFFBF00) : (color ?? Colors.white70),
      fontSize: 14,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      decoration: underline ? TextDecoration.underline : TextDecoration.none,
    );
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF4A4A4A) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? const Color(0xFFFFBF00) : Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

class _ToolBtnIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  const _ToolBtnIcon({required this.icon, required this.tooltip, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => Tooltip(message: tooltip, child: GestureDetector(onTap: onTap, child: Container(width: 38, height: 34, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: active ? const Color(0xFF4A4A4A) : const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8), border: Border.all(color: active ? const Color(0xFFFFBF00) : Colors.white12)), alignment: Alignment.center, child: Icon(icon, color: active ? const Color(0xFFFFBF00) : Colors.white, size: 20))));
}

class _ColorMenu extends ConsumerStatefulWidget {
  final ValueChanged<String> onTextColor, onBgColor;
  final ValueChanged<int> onBgColorChange;
  final Color lastTextColor, lastHighlightColor;
  const _ColorMenu({required this.onTextColor, required this.onBgColor, required this.onBgColorChange, required this.lastTextColor, required this.lastHighlightColor});
  @override
  ConsumerState<_ColorMenu> createState() => _ColorMenuState();
}

class _ColorMenuState extends ConsumerState<_ColorMenu> {
  late Color _currentTextColor;
  late Color _currentHighlightColor;
  @override
  void initState() { super.initState(); _currentTextColor = widget.lastTextColor; _currentHighlightColor = widget.lastHighlightColor; }
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currentTextColor = _currentTextColor;
    final currentHighlightColor = _currentHighlightColor;

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('TEXT COLOR', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)), 
          GlobalColorButton(color: currentTextColor.value, title: 'TEXT COLOR PICKER', showNoneAsWhite: true, onColorChanged: (c) { 
             final hex = '#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(); 
             widget.onTextColor(hex); 
             if (mounted) setState(() { _currentTextColor = Color(c); });
             Navigator.pop(context);
          })
       ]), 
       const SizedBox(height: 16), 
       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('HIGHLIGHT COLOR', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)), 
          GlobalColorButton(color: currentHighlightColor.value, title: 'HIGHLIGHT PICKER', onColorChanged: (c) { 
             final hex = '#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(); 
             widget.onBgColor(hex); 
             if (mounted) setState(() { _currentHighlightColor = Color(c); });
             Navigator.pop(context);
          })
       ]), 
       const SizedBox(height: 16), 
       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('BACKGROUND COLOR', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)), 
          GlobalColorButton(color: settings.scriptBgColor, title: 'WINDOW BACKGROUND PICKER', onColorChanged: (c) {
             widget.onBgColorChange(c);
             if (mounted) setState(() {});
             Navigator.pop(context);
          })
       ])
    ]);
  }
}

class _EditorBlock extends StatelessWidget {
  final _MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final bool isGlobalSelected;
  final VoidCallback onSubmitted, onDelete, onTap, onSelectAll;
  const _EditorBlock({super.key, required this.controller, required this.focusNode, required this.settings, required this.isGlobalSelected, required this.onSubmitted, required this.onDelete, required this.onTap, required this.onSelectAll});
  @override
  Widget build(BuildContext context) {
    TextAlign align = TextAlign.left;
    if (controller.text.contains('[center]')) {
      align = TextAlign.center;
    } else if (controller.text.contains('[right]')) {
      align = TextAlign.right;
    } else if (controller.text.contains('[left]')) {
      align = TextAlign.left;
    }

    double maxFs = 18;
    for (final m in RegExp(r'\[size=(\d+)\]').allMatches(controller.text)) {
       final s = double.tryParse(m.group(1)!) ?? 18;
       if (s > maxFs) maxFs = s;
    }

    return Container(
      decoration: BoxDecoration(
        color: isGlobalSelected ? const Color(0x33FFBF00) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: EdgeInsets.symmetric(vertical: settings.lineSpacing * 2),
      child: TextField(
          controller: controller,
          focusNode: focusNode,
          selectionControls: _CleanSelectionControls(() {
            final sel = controller.selection;
            if (sel.isValid && !sel.isCollapsed) {
              final rawText = sel.textInside(controller.text);
              final tagsRegex = RegExp(r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
              final cleaned = rawText.replaceAll(tagsRegex, '');
              Clipboard.setData(ClipboardData(text: cleaned));
            }
          }),
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textAlign: align,
          strutStyle: StrutStyle(
            fontSize: maxFs,
            height: 1.25,
            forceStrutHeight: true,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          cursorColor: const Color(0xFFFFBF00),
          enableInteractiveSelection: true,
          enableSuggestions: false,
          autocorrect: false,
          onTap: onTap,
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontSize: 18,
            height: 1.25,
            letterSpacing: settings.letterSpacing,
            wordSpacing: settings.wordSpacing,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
          ),
          contextMenuBuilder: (context, editableTextState) {
            final List<ContextMenuButtonItem> buttonItems = editableTextState.contextMenuButtonItems;
            
            // v3.23.5: Ensure Select All triggers the global selection logic
            for (int i = 0; i < buttonItems.length; i++) {
              if (buttonItems[i].type == ContextMenuButtonType.selectAll) {
                final originalCallback = buttonItems[i].onPressed;
                buttonItems[i] = ContextMenuButtonItem(
                  label: buttonItems[i].label,
                  type: ContextMenuButtonType.selectAll,
                  onPressed: () {
                    if (originalCallback != null) originalCallback();
                    onSelectAll();
                  },
                );
              }
            }

            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: buttonItems,
            );
          },
        ),
      );
  }
}

class _SaveNameDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final List<String> usedNames;
  final String format;
  const _SaveNameDialog({required this.nameCtrl, required this.usedNames, required this.format});
  @override
  State<_SaveNameDialog> createState() => _SaveNameDialogState();
}

class _SaveNameDialogState extends State<_SaveNameDialog> {
  @override
  Widget build(BuildContext context) => AlertDialog(backgroundColor: const Color(0xFF131313), title: const Text('File Name'), content: TextField(controller: widget.nameCtrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(suffixText: '.${widget.format}')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, {'name': widget.nameCtrl.text.trim(), 'replace': widget.usedNames.contains(widget.nameCtrl.text.trim())}), child: const Text('Save'))]);
}

class LobbySettingsPanel extends ConsumerWidget {
  const LobbySettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Container(padding: const EdgeInsets.fromLTRB(24, 16, 24, 40), decoration: const BoxDecoration(color: Color(0xFF161616), borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)))), const SizedBox(height: 20), const Text('Video Quality', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 12), SegmentedButton<String>(segments: const [ButtonSegment(value: '480p', label: Text('480p'), icon: Icon(Icons.sd_outlined)), ButtonSegment(value: '720p', label: Text('720p'), icon: Icon(Icons.hd_outlined)), ButtonSegment(value: '1080p', label: Text('1080p'), icon: Icon(Icons.high_quality_outlined))], selected: {settings.videoResolution}, onSelectionChanged: (vals) => notifier.setVideoResolution(vals.first)), const SizedBox(height: 24), const Text('User Profile', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 12), TextField(style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Enter Display Name', hintStyle: const TextStyle(color: Colors.white24), prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFFFBF00)), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)), controller: TextEditingController(text: settings.displayName), onSubmitted: (val) => notifier.setDisplayName(val)), const SizedBox(height: 24)]));
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)), Text(value.toStringAsFixed(1), style: const TextStyle(color: Color(0xFFFFBF00), fontSize: 13, fontWeight: FontWeight.bold))]), Slider(value: value, min: min, max: max, activeColor: const Color(0xFFFFBF00), inactiveColor: Colors.white10, onChanged: onChanged)]);
}

class _CleanSelectionControls extends MaterialTextSelectionControls {
  final VoidCallback onCopy;
  _CleanSelectionControls(this.onCopy);
  @override
  void handleCopy(TextSelectionDelegate delegate) {
    onCopy();
    delegate.hideToolbar();
  }
}
