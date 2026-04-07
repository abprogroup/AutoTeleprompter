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
import 'package:google_fonts/google_fonts.dart';
import 'teleprompt_selector_sheet.dart';

// ── Markup-rendering TextEditingController ────────────────────────────────────

class _MarkupController extends TextEditingController {
  _MarkupController({String? text}) : super(text: text);

  static const _tagStyle = TextStyle(
    color: Colors.transparent,
    backgroundColor: Colors.transparent,
    fontSize: 0,
    letterSpacing: 0,
    wordSpacing: 0,
    height: 0,
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
    final pattern = RegExp(
      r'\[color=([^\]]+)\](.*?)\[\/color\]'
      r'|\[bg=([^\]]+)\](.*?)\[\/bg\]'
      r'|\*\*(.*?)\*\*'
      r'|\[u\](.*?)\[\/u\]'
      r'|\[i\](.*?)\[\/i\]'
      r'|\[size=(\d+)\](.*?)\[\/size\]'
      r'|\[(center|left|right)\](.*?)\[\/\10\]'
      r'|\[(rtl|ltr)\](.*?)\[\/\12\]'
      r'|\[font=([^\]]+)\](.*?)\[\/font\]'
      r'|(\[(?:\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font)(?:=[^\]]+)?|size=\d+)\])',
      dotAll: true,
    );

    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }

      if (m.group(1) != null && m.group(2) != null) {
        final color = Color(int.tryParse(m.group(1)!.replaceFirst('#', '0xFF'), radix: 16) ?? 0xFFFFFFFF);
        final s = (base ?? const TextStyle()).merge(TextStyle(color: color));
        spans.add(TextSpan(text: '[color=${m.group(1)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(2)!, s));
        spans.add(TextSpan(text: '[/color]', style: _tagStyle));
      } else if (m.group(3) != null && m.group(4) != null) {
        final color = Color(int.tryParse(m.group(3)!.replaceFirst('#', '0xFF'), radix: 16) ?? 0x00000000);
        final s = (base ?? const TextStyle()).merge(TextStyle(backgroundColor: color.withOpacity(0.5)));
        spans.add(TextSpan(text: '[bg=${m.group(3)}]', style: _tagStyle));
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
        spans.add(TextSpan(text: '[${m.group(10)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(11)!, base));
        spans.add(TextSpan(text: '[/${m.group(10)}]', style: _tagStyle));
      } else if (m.group(12) != null && m.group(13) != null) {
        spans.add(TextSpan(text: '[${m.group(12)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(13)!, base));
        spans.add(TextSpan(text: '[/${m.group(12)}]', style: _tagStyle));
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
  );
}

// ── Main Screen ──────────────────────────────────────────────────────────────

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
  
  // Selection Keeper State
  _MarkupController? _lastFocusedController;
  TextSelection? _lastSelection;
  
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
  bool _isCleaning = false; // v3.9: Atomic suppression
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
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        // Capture all necessary state synchronously before any async gap
        final text = _getRefinedFullText();
        final currentTitle = _currentTitle;
        
        // Double-check mounted immediately before accessing ref
        if (!mounted) return;
        final notifier = ref.read(settingsProvider.notifier);
        
        debugPrint('V3 Auto-Save Triggered');
        if (text.isEmpty && currentTitle == 'New Project') return;

        await notifier.saveScript(text, title: currentTitle, historyIndex: _historyIndex);
        debugPrint('Auto-Save Completed at index: $_historyIndex');
      } catch (e) {
        // Suppress "ref after disposed" or "defunct element" errors 
        // as they are expected during asynchronous app teardown.
        final err = e.toString().toLowerCase();
        if (!err.contains('disposed') && !err.contains('defunct')) {
           debugPrint('Auto-Save Error: $e');
        }
      }
    });
  }

  String? _currentSessionId; // Identity key for Deep Memory

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
        // Check if provider already has a session (restored from recent activity)
        _currentSessionId = script.sessionId;
      }
      
      // If no session ID yet, generate one for this new/fresh production
      _currentSessionId ??= DateTime.now().millisecondsSinceEpoch.toString();

      final settings = ref.read(settingsProvider);
      _lastChosenTextColor = Color(settings.lastTextColor);
      _lastChosenHighlightColor = Color(settings.lastHighlightColor);

      _loadText(initialText);
      _currentTitle = initialTitle;

      // Restore History if available (v3.5.4)
      if (script?.historyJson != null) {
        try {
          final List<dynamic> historyData = jsonDecode(script!.historyJson!);
          _history.clear();
          _history.addAll(historyData.map((d) => _EditorState.fromJson(d)));
          _historyIndex = _history.length - 1;
          debugPrint('Restored ${_history.length} history states');
        } catch (e) {
          debugPrint('History Restore Error: $e');
        }
      }

      _isInit = true;
      
      // V3.8: Automatic History Index Restoration
      if (script != null && script.historyIndex >= 0 && script.historyIndex < _history.length) {
        _historyIndex = script.historyIndex;
        _applyState(_history[_historyIndex]);
        debugPrint('Jumped to history index: $_historyIndex');
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
    _clearControllers();
    final paragraphs = text.split('\n');
    for (int i = 0; i < paragraphs.length; i++) {
      _addBlock(i, text: paragraphs[i]);
    }
    if (_controllers.isEmpty) _addBlock(0);
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
    final node = FocusNode();
    
    // Track selection memory for each block
    node.addListener(() {
      if (node.hasFocus) {
        _lastFocusedController = controller;
      }
    });

    controller.addListener(() {
      if (node.hasFocus) {
        _lastSelection = controller.selection;
      }
      _onBlockChanged();
    });

    setState(() {
      _controllers.insert(index, controller);
      _focusNodes.insert(index, node);
    });
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
    if (_isCleaning) return; // v3.9: Atomic suppression
    _saveHistory(description: 'Edit Text', debounce: true);
    _scheduleRecentUpdate();
  }

  @override
  void dispose() {
    final text = _getRefinedFullText();
    _triggerRecentUpdate(_currentTitle, text);
    // v4.0: Sync lastScript + lastHistoryIndex so script_provider.build()
    // finds matching text and restores the correct history position on re-entry.
    ref.read(settingsProvider.notifier).saveScript(text, title: _currentTitle, historyIndex: _historyIndex);
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
    
    // Double-check mounted immediately before ref access
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final meta = jsonEncode({
      'sessionId': _currentSessionId,
      'title': title,
      'historyIndex': forcedIndex ?? _historyIndex, // v4.0: Per-script persistence
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'type': _sourceType,
      'snippet': content.length > 50 ? content.substring(0, 50) : content,
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
    if (debounce) {
      _historyTimer?.cancel();
      _historyTimer = Timer(const Duration(milliseconds: 1000), () => _saveHistory(description: description, debounce: false));
      return;
    }

    final settings = ref.read(settingsProvider);
    final state = _EditorState(
      text: _getRefinedFullText(),
      timestamp: DateTime.now(),
      description: description,
      lineSpacing: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
      scriptBgColor: settings.scriptBgColor,
      currentWordColor: settings.currentWordColor,
      futureWordColor: settings.futureWordColor,
    );

    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(state);
    if (_history.length > _maxHistory) _history.removeAt(0);
    _historyIndex = _history.length - 1;
    if (mounted) setState(() {});
  }

  void _undo() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _applyState(_history[_historyIndex]);
      if (mounted) setState(() {});
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _applyState(_history[_historyIndex]);
      if (mounted) setState(() {});
    }
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
    if (mounted) setState(() {});
  }

  _MarkupController? get _activeController {
    for (var i=0; i<_focusNodes.length; i++) {
        if (_focusNodes[i].hasFocus) return _controllers[i];
    }
    return _lastFocusedController ?? (_controllers.isNotEmpty ? _controllers.last : null);
  }

  void _wrapSelection(String open, String close) {
    final controller = _activeController;
    if (controller == null) return;
    
    // Use last selection memory if current is lost due to menu interaction
    TextSelection selection = controller.selection;
    if ((!selection.isValid || selection.isCollapsed) && _lastSelection != null && controller == _lastFocusedController) {
       selection = _lastSelection!;
    }

    if (!selection.isValid || selection.isCollapsed) return;
    
    final text = controller.text;
    final selectedText = text.substring(selection.start, selection.end);
    
    // Check if toggling
    bool isToggling = false;
    if (open.isNotEmpty && close.isNotEmpty) {
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
       }
    }

    if (!isToggling) {
      final replacement = '$open$selectedText$close';
      final newText = text.replaceRange(selection.start, selection.end, replacement);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: selection.start, extentOffset: selection.start + replacement.length),
      );
    }
    _saveHistory(description: 'Format Text');
  }

  void _handleBgColorChange(int color) {
    ref.read(settingsProvider.notifier).setScriptBgColor(color);
    _saveHistory(description: 'Change Background', debounce: true);
    if (mounted) setState(() {});
  }

  void _applyStyle(String style) {
    if (style.contains('=')) {
      final parts = style.split('=');
      final type = parts[0]; // color or bg
      final val = parts[1];
      _wrapSelection('[$type=$val]', '[/$type]');
    } else {
      _wrapSelection(style, style);
    }
  }

  void _onBold() => _wrapSelection('**', '**');
  void _onUnderline() => _wrapSelection('[u]', '[/u]');
  void _onItalic() => _wrapSelection('[i]', '[/i]');
  void _onDirection(String dir) => _wrapSelection('[$dir]', '[/$dir]');
  void _onAlign(String align) {
    final controller = _activeController;
    if (controller == null) return;

    // v4.0: Alignment is a PARAGRAPH-level property — apply to the entire block,
    // not just the selection. First strip any existing alignment tags.
    String text = controller.text;
    text = text.replaceAll(RegExp(r'\[(center|left|right)\]'), '');
    text = text.replaceAll(RegExp(r'\[\/(center|left|right)\]'), '');
    text = text.trim();

    // Suppress duplicate history from controller listener
    _isCleaning = true;
    if (text.isNotEmpty) {
      controller.value = TextEditingValue(
        text: '[$align]$text[/$align]',
        selection: TextSelection.collapsed(offset: '[$align]$text[/$align]'.length),
      );
    }
    _isCleaning = false;
    _saveHistory(description: 'Align $align');
  }
  void _onFontSize(int size) => _wrapSelection('[size=$size]', '[/size]');
  void _onFontFamily(String family) => _wrapSelection('[font=$family]', '[/font]');

  void _onLineSpacingChanged(double val) {
    ref.read(settingsProvider.notifier).setLineSpacing(val);
    _saveHistory(description: 'Line Spacing');
  }

  void _onLetterSpacingChanged(double val) {
    ref.read(settingsProvider.notifier).setLetterSpacing(val);
    _saveHistory(description: 'Letter Spacing');
  }

  void _onWordSpacingChanged(double val) {
    ref.read(settingsProvider.notifier).setWordSpacing(val);
    _saveHistory(description: 'Word Spacing');
  }

  void _onTextColorSelected(String hex) {
     final color = Color(int.tryParse(hex.replaceFirst('#', '0xFF'), radix: 16) ?? 0xFFFFBF00);
     setState(() => _lastChosenTextColor = color);
     ref.read(settingsProvider.notifier).setLastChosenTextColor(color.value);
     _wrapSelection('[color=$hex]', '[/color]');
  }

  void _onBgColorSelected(String hex) {
     final color = Color(int.tryParse(hex.replaceFirst('#', '0xFF'), radix: 16) ?? 0x4DFFFFFF);
     setState(() => _lastChosenHighlightColor = color);
     ref.read(settingsProvider.notifier).setLastChosenHighlightColor(color.value);
     _wrapSelection('[bg=$hex]', '[/bg]');
  }

  // ── File Operations ────────────────────────────────────────────────────────

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

    if (!mounted) return;

    // Phase 4: Conflict Resolution Logic
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
          if (!contentMatch) {
             conflictMeta = meta;
          }
          break;
        }
      } catch (_) {}
    }

    if (conflictMeta != null) {
      final choice = await _showConflictDialog(title, conflictMeta);
      if (!mounted || choice == null) return;
      
      if (choice == 'history') {
        _loadText(conflictMeta['fullText']);
        _currentTitle = title;
        _sourceType = conflictMeta['type'] ?? 'FILE';
        _currentSessionId = conflictMeta['sessionId'];
        if (conflictMeta.containsKey('style')) {
           ref.read(settingsProvider.notifier).applySessionStyles(conflictMeta['style']);
        }
        _saveHistory(description: 'Restore History');
        _scheduleRecentUpdate();
        setState(() {});
        return;
      }
    }

    // New Import or Reload & Discard flow
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

  // ── RTF Parser (Simplified) ────────────────────────────────────────────────

  String _stripRtf(String rtf) {
    String text = rtf;
    // V3 Polish: Aggressive stripping of RTF commands that bleed through
    text = text.replaceAll(RegExp(r'\{\\fonttbl.*?\}'), '');
    text = text.replaceAll(RegExp(r'\{\\colortbl.*?\}'), '');
    text = text.replaceAll(RegExp(r'\\pard\b.*?'), '\n');
    text = text.replaceAll(RegExp(r'\\par\b'), '\n');
    text = text.replaceAllMapped(RegExp(r'\\u(-?\d+)\??\s?'), (m) {
      final code = int.tryParse(m.group(1)!) ?? 0;
      return String.fromCharCode(code < 0 ? code + 65536 : code);
    });
    // V3 Professional: Refined RTF command stripping
    // We remove tags but preserve a single space if it followed a command not already ending with space
    text = text.replaceAllMapped(RegExp(r'\\[a-zA-Z]+(-?\d+)?([ \t]?)'), (match) {
      // If the command naturally had a space/tab (group 2), we keep it as a single space
      // unless it was a 'formatting' command that usually doesn't precede text characters.
      return match.group(2) ?? '';
    });
    text = text.replaceAll(RegExp(r'[\\{}]'), '');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _toRtf(String text) {
    // Phase 3: Styled RTF Export
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Color(0xFFFFBF00)),
                  tooltip: 'Content Creator Mode',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContentCreatorScreen())),
                ),
                IconButton(
                  icon: const Icon(Icons.settings), 
                  onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const LobbySettingsPanel())
                ),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearScript),
                IconButton(icon: const Icon(Icons.save_alt), onPressed: _saveScript),
                IconButton(icon: const Icon(Icons.folder_open), onPressed: _importFile),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(_currentTitle.trim(), 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20), 
                    overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFFFBF00)),
                  onPressed: _showRenameDialog,
                ),
              ],
            ),
          ],
        ),
      ),
      // Drawer removed as history is now in toolbar
      body: Column(
        children: [
          _FormattingToolbar(
            onBold: _onBold,
            onUnderline: _onUnderline,
            onItalic: _onItalic,
            onClear: () {
              final controller = _activeController;
              final selection = controller?.selection;
              
              if (selection == null || !selection.isValid || selection.isCollapsed) {
                // HARD RESET: If no selection, clear all blocks and reset background to black
                setState(() => _isCleaning = true);
                try {
                  for (final c in _controllers) {
                    c.text = c.text.replaceAll(RegExp(r'\[.*?\]|\*\*'), '');
                  }
                  ref.read(settingsProvider.notifier).setScriptBgColor(0xFF000000);
                  _saveHistory(description: 'Hard Reset Styles & Background', debounce: false);
                  _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), 0); // v4.0: Force index 0
                } finally {
                  setState(() => _isCleaning = false);
                }
              } else {
                // SURGICAL CLEAR: Clear only the current selection
                final text = controller!.text;
                final selectedText = text.substring(selection.start, selection.end);
                final cleaned = selectedText.replaceAll(RegExp(r'\[.*?\]|\*\*'), '');
                controller.value = TextEditingValue(
                  text: text.replaceRange(selection.start, selection.end, cleaned),
                  selection: TextSelection.collapsed(offset: selection.start),
                );
                _saveHistory(description: 'Clear Selected Styles');
              }
            },
            onFontSize: _onFontSize,
            onAlign: _onAlign,
            onDirection: _onDirection,
            onTextColor: _onTextColorSelected,
            onBgColor: _onBgColorSelected,
            onFontFamily: _onFontFamily,
            lastTextColor: _lastChosenTextColor,
            lastHighlightColor: _lastChosenHighlightColor,
            onBgColorChange: _handleBgColorChange,
            onUndo: () { _undo(); _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), _historyIndex); },
            onRedo: () { _redo(); _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), _historyIndex); },
            history: _history,
            historyIndex: _historyIndex,
            onHistorySelected: (idx) {
               setState(() {
                  _historyIndex = idx;
                  _applyState(_history[idx]);
               });
               // v3.6 Deep Fix: Force immediate sync of the manual history selection to metadata
               _triggerRecentUpdate(_currentTitle, _getRefinedFullText(), idx);
            },
            canUndo: _historyIndex > 0,
            canRedo: _historyIndex < _history.length - 1,
          ),
          Expanded(
            child: Container(
              color: Color(settings.scriptBgColor),
              child: ListView.builder(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
                itemCount: _controllers.length,
                itemBuilder: (context, index) => _EditorBlock(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  settings: settings,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorStatusBar extends StatelessWidget {
  final int wordCount;
  final double scrollSpeed;
  const _EditorStatusBar({required this.wordCount, required this.scrollSpeed});

  String _formatDuration(int words, double speed) {
    if (words == 0) return "0:00";
    // Crude estimate: At speed 100, we aim for ~160 words per minute.
    final baseWpm = 160.0;
    final normalizedSpeed = speed / 100.0;
    final durationMinutes = words / (baseWpm * (normalizedSpeed > 0 ? normalizedSpeed : 1.0));
    final seconds = (durationMinutes * 60).round();
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
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
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFFFBF00)),
              const SizedBox(width: 4),
              Text(
                "Est. Duration: ${_formatDuration(wordCount, scrollSpeed)}",
                style: const TextStyle(color: Color(0xFFFFBF00), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Secondary Widgets ────────────────────────────────────────────────────────

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

  const _FormattingToolbar({
    required this.onBold, required this.onUnderline, 
    required this.onItalic, required this.onClear,
    required this.onFontSize,
    required this.onAlign, required this.onDirection, 
    required this.onTextColor, required this.onBgColor,
    required this.onFontFamily,
    required this.onBgColorChange,
    required this.lastTextColor, required this.lastHighlightColor,
    required this.onUndo, required this.onRedo, 
    required this.canUndo, required this.canRedo,
    required this.history, required this.historyIndex, required this.onHistorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolBtn(label: '⎌', tooltip: 'Undo', onTap: onUndo, color: canUndo ? Colors.white : Colors.white10),
          _ToolBtn(label: '↻', tooltip: 'Redo', onTap: onRedo, color: canRedo ? Colors.white : Colors.white10),
          _HistoryMenu(history: history, historyIndex: historyIndex, onHistorySelected: onHistorySelected),
          const VerticalDivider(color: Colors.white12, width: 12),
          _ToolBtn(label: 'C', tooltip: 'Clear All Formatting', onTap: onClear, color: Colors.redAccent),
          _FormatPopup(
            label: 'TEXT',
            icon: Icons.text_fields_rounded,
            child: _TextMenu(
              onBold: onBold, 
              onItalic: onItalic, 
              onUnderline: onUnderline, 
              onClear: onClear, 
              onFontSize: onFontSize,
              onFontFamily: onFontFamily,
            ),
          ),
          _FormatPopup(
            label: 'LAYOUT',
            icon: Icons.format_align_center_rounded,
            child: _LayoutMenu(onAlign: onAlign, onDirection: onDirection),
          ),
          _FormatPopup(
            label: 'COLOR',
            icon: Icons.palette_rounded,
            child: _ColorMenu(
              onTextColor: onTextColor, 
              onBgColor: onBgColor,
              lastTextColor: lastTextColor,
              lastHighlightColor: lastHighlightColor,
              onBgColorChange: onBgColorChange,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatPopup extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;
  const _FormatPopup({required this.label, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF1A1A1A),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, color: const Color(0xFFFFBF00), size: 20),
                    const SizedBox(width: 8),
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 20),
                child,
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
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
    tooltip: 'Activity History',
    color: const Color(0xFF1F1F1F),
    onSelected: onHistorySelected,
    itemBuilder: (_) => history.asMap().entries.toList().reversed.map((e) {
        final idx = e.key;
        final s = e.value;
        final isSelected = idx == historyIndex;
        final timeStr = "${s.timestamp.hour}:${s.timestamp.minute.toString().padLeft(2,'0')}";
        return PopupMenuItem(
          value: idx,
          child: Text('${s.description} ($timeStr)', style: TextStyle(color: isSelected ? const Color(0xFFFFBF00) : Colors.white70, fontSize: 13)),
        );
    }).toList(),
  );
}

class _TextMenu extends StatelessWidget {
  final VoidCallback onBold, onItalic, onUnderline, onClear;
  final ValueChanged<int> onFontSize;
  final ValueChanged<String> onFontFamily;
  const _TextMenu({required this.onBold, required this.onItalic, required this.onUnderline, required this.onClear, required this.onFontSize, required this.onFontFamily});

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(color: Colors.white70, fontSize: 13);
    
    return Row(
      children: [
        _ToolBtn(label: 'B', tooltip: 'Bold', onTap: onBold, bold: true),
        _ToolBtn(label: 'I', tooltip: 'Italic', onTap: onItalic, italic: true),
        _ToolBtn(label: 'U', tooltip: 'Underline', onTap: onUnderline, underline: true),
        const SizedBox(width: 8),
        // Size Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: 18,
              dropdownColor: const Color(0xFF1F1F1F),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
              style: const TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold, fontSize: 12),
              onChanged: (v) { if (v != null) onFontSize(v); },
              items: [14, 18, 24, 28, 32, 40, 48, 56, 64, 72, 80, 96, 120]
                .map((s) => DropdownMenuItem(value: s, child: Text('${s}px'))).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: 'Inter',
              dropdownColor: const Color(0xFF1F1F1F),
              icon: const Icon(Icons.font_download_rounded, color: Colors.white54, size: 14),
              style: const TextStyle(color: Colors.white, fontSize: 11),
              onChanged: (v) { if (v != null) onFontFamily(v); },
              items: ['Inter', 'Roboto', 'Montserrat', 'Oswald', 'EB Garamond']
                .map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _LayoutMenu extends ConsumerWidget {
  final ValueChanged<String> onAlign, onDirection;
  const _LayoutMenu({required this.onAlign, required this.onDirection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToolBtnIcon(icon: Icons.format_align_left, tooltip: 'Align Left', onTap: () => onAlign('left')),
            _ToolBtnIcon(icon: Icons.format_align_center, tooltip: 'Align Center', onTap: () => onAlign('center')),
            _ToolBtnIcon(icon: Icons.format_align_right, tooltip: 'Align Right', onTap: () => onAlign('right')),
          ],
        ),
        const SizedBox(height: 16),
        _SliderRow(label: 'Line Spacing', value: settings.lineSpacing, min: 1.0, max: 3.0, onChanged: (v) => notifier.setLineSpacing(v)),
        _SliderRow(label: 'Letter Spacing', value: settings.letterSpacing, min: -1.0, max: 5.0, onChanged: (v) => notifier.setLetterSpacing(v)),
        _SliderRow(label: 'Word Spacing', value: settings.wordSpacing, min: 0, max: 20, onChanged: (v) => notifier.setWordSpacing(v)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToolBtnIcon(icon: Icons.format_textdirection_l_to_r, tooltip: 'LTR', onTap: () => onDirection('ltr')),
            const SizedBox(width: 20),
            _ToolBtnIcon(icon: Icons.format_textdirection_r_to_l, tooltip: 'RTL', onTap: () => onDirection('rtl')),
          ],
        ),
      ],
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final String label, tooltip;
  final bool bold, italic, underline;
  final VoidCallback onTap;
  final Color? color;
  const _ToolBtn({required this.label, required this.tooltip, required this.onTap, this.bold=false, this.italic=false, this.underline=false, this.color});
  @override
  Widget build(BuildContext context) => Tooltip(message: tooltip, child: GestureDetector(onTap: onTap, child: Container(
    width: 38, height: 34, margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
    alignment: Alignment.center,
    child: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 15, fontWeight: bold?FontWeight.bold:null, fontStyle: italic?FontStyle.italic:null, decoration: underline?TextDecoration.underline:null)),
  )));
}

class _ToolBtnIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolBtnIcon({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(message: tooltip, child: GestureDetector(onTap: onTap, child: Container(
    width: 38, height: 34, margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
    alignment: Alignment.center,
    child: Icon(icon, color: Colors.white, size: 20),
  )));
}

class _ColorMenu extends ConsumerStatefulWidget {
  final ValueChanged<String> onTextColor, onBgColor;
  final ValueChanged<int> onBgColorChange;
  final Color lastTextColor, lastHighlightColor;
  const _ColorMenu({
    required this.onTextColor, 
    required this.onBgColor, 
    required this.onBgColorChange,
    required this.lastTextColor,
    required this.lastHighlightColor,
  });

  @override
  ConsumerState<_ColorMenu> createState() => _ColorMenuState();
}

class _ColorMenuState extends ConsumerState<_ColorMenu> {
  late Color _currentTextColor;
  late Color _currentHighlightColor;

  @override
  void initState() {
    super.initState();
    _currentTextColor = widget.lastTextColor;
    _currentHighlightColor = widget.lastHighlightColor;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    _currentTextColor = Color(settings.lastTextColor);
    _currentHighlightColor = Color(settings.lastHighlightColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TEXT COLOR
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TEXT COLOR', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            GlobalColorButton(
              color: _currentTextColor.value,
              title: 'TEXT COLOR PICKER',
              onColorChanged: (c) {
                setState(() => _currentTextColor = Color(c));
                final hex = '#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
                widget.onTextColor(hex);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // HIGHLIGHT COLOR
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('HIGHLIGHT COLOR', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            GlobalColorButton(
              color: _currentHighlightColor.value,
              title: 'HIGHLIGHT PICKER',
              onColorChanged: (c) {
                setState(() => _currentHighlightColor = Color(c));
                final hex = '#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
                widget.onBgColor(hex);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // BACKGROUND COLOR
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('BACKGROUND COLOR', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            GlobalColorButton(
              color: settings.scriptBgColor,
              title: 'WINDOW BACKGROUND PICKER',
              onColorChanged: (c) => widget.onBgColorChange(c),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final bool colorAsText;
  final int currentColor;
  final ValueChanged<String> onColorSelected;
  const _ColorPicker({required this.colorAsText, required this.currentColor, required this.onColorSelected});
  @override
  Widget build(BuildContext context) => GlobalColorButton(color: currentColor, title: colorAsText?'Text':'BG', onColorChanged: (c) => onColorSelected('#'+c.toRadixString(16).padLeft(8,'0').substring(2).toUpperCase()));
}

class _ColorModeToggle extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  const _ColorModeToggle({required this.isActive, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: isActive?const Color(0xFF2A2A5A):const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(6), border: Border.all(color: isActive?const Color(0xFFFFBF00):Colors.white24)), child: Text(isActive?'TEXT':'BG', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))));
}

class _EditorBlock extends StatelessWidget {
  final _MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final VoidCallback onSubmitted, onDelete;

  const _EditorBlock({
    required this.controller,
    required this.focusNode,
    required this.settings,
    required this.onSubmitted,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    TextAlign align = TextAlign.left;
    final txt = controller.text;
    if (txt.startsWith('[center]')) align = TextAlign.center;
    else if (txt.startsWith('[right]')) align = TextAlign.right;

    return Focus(
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.enter && event is KeyDownEvent) {
          onSubmitted();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace && event is KeyDownEvent && controller.text.isEmpty) {
          onDelete();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: null,
        textAlign: align,
        cursorColor: const Color(0xFFFFBF00),
        style: TextStyle(
          color: Colors.white.withOpacity(0.95), // Slight transparent to allow spans to shine
          fontSize: 18,
          height: 1.5 + (settings.lineSpacing - 1.0),
          letterSpacing: settings.letterSpacing,
          wordSpacing: settings.wordSpacing,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
        ),
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
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF131313),
    title: const Text('File Name'),
    content: TextField(controller: widget.nameCtrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(suffixText: '.${widget.format}')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ElevatedButton(onPressed: () => Navigator.pop(context, {'name': widget.nameCtrl.text.trim(), 'replace': widget.usedNames.contains(widget.nameCtrl.text.trim())}), child: const Text('Save')),
    ],
  );
}

class LobbySettingsPanel extends ConsumerWidget {
  const LobbySettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    const sectionStyle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 13);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 20),
          const Text('Video Quality (Labeled Excellence)', style: sectionStyle),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '480p', label: Text('480p'), icon: Icon(Icons.sd_outlined)),
              ButtonSegment(value: '720p', label: Text('720p (HD)'), icon: Icon(Icons.hd_outlined)),
              ButtonSegment(value: '1080p', label: Text('1080p (FHD)'), icon: Icon(Icons.high_quality_outlined)),
            ],
            selected: {settings.videoResolution},
            onSelectionChanged: (vals) => notifier.setVideoResolution(vals.first),
          ),
          const SizedBox(height: 24),
          const Text('User Profile', style: sectionStyle),
          const SizedBox(height: 12),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter Display Name',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFFFBF00)),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            controller: TextEditingController(text: settings.displayName),
            onSubmitted: (val) => notifier.setDisplayName(val),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(value.toStringAsFixed(1), style: const TextStyle(color: Color(0xFFFFBF00), fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(value: value, min: min, max: max, activeColor: const Color(0xFFFFBF00), inactiveColor: Colors.white10, onChanged: onChanged),
      ],
    );
  }
}
