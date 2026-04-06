import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../script/models/script_word.dart';
import '../providers/script_provider.dart';
import '../../teleprompter/widgets/teleprompter_screen.dart';
import '../../teleprompter/providers/teleprompter_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/widgets/global_color_picker.dart';

// ── Markup-rendering TextEditingController ────────────────────────────────────
// The raw text is preserved (markup tags stay in place for editing),
// but the tags are rendered dim and the content is rendered with the
// corresponding color/style. This gives a live WYSIWYG effect.

class _MarkupController extends TextEditingController {
  _MarkupController({String? text}) : super(text: text);

  static const _tagStyle = TextStyle(
    color: Colors.transparent,
    fontSize: 0.1,
    letterSpacing: -1.0,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final fullText = value.text;
    final composing = value.composing;
    final hasComposing =
        composing.isValid && withComposing && value.isComposingRangeValid;

    if (!hasComposing) {
      return _buildMarkup(fullText, style);
    }

    // Handle IME composing region (underline while typing CJK / Hebrew)
    final underline = (style ?? const TextStyle())
        .merge(const TextStyle(decoration: TextDecoration.underline));
    return TextSpan(style: style, children: [
      _buildMarkup(fullText.substring(0, composing.start), style),
      TextSpan(
          text: fullText.substring(composing.start, composing.end),
          style: underline),
      _buildMarkup(fullText.substring(composing.end), style),
    ]);
  }

  TextSpan _buildMarkup(String text, TextStyle? base) {
    if (text.isEmpty) return TextSpan(text: '', style: base);

    final spans = <InlineSpan>[];
      final pattern = RegExp(
      // Matches pairs OR standalone tags (to ensure they stay hidden while typing)
      r'\*\*(.*?)\*\*'
      r'|\[y\](.*?)\[\/y\]'
      r'|\[r\](.*?)\[\/r\]'
      r'|\[g\](.*?)\[\/g\]'
      r'|\[b\](.*?)\[\/b\]'
      r'|\[o\](.*?)\[\/o\]'
      r'|\[p\](.*?)\[\/p\]'
      r'|\[c\](.*?)\[\/c\]'
      r'|\[pk\](.*?)\[\/pk\]'
      r'|\[yc\](.*?)\[\/yc\]'
      r'|\[rc\](.*?)\[\/rc\]'
      r'|\[gc\](.*?)\[\/gc\]'
      r'|\[bc\](.*?)\[\/bc\]'
      r'|\[oc\](.*?)\[\/oc\]'
      r'|\[pc\](.*?)\[\/pc\]'
      r'|\[cc\](.*?)\[\/cc\]'
      r'|\[pkc\](.*?)\[\/pkc\]'
      r'|\[u\](.*?)\[\/u\]'
      r'|\[size=(\d+)\](.*?)\[\/size\]'
      r'|\[(center|left|right)\](.*?)\[\/\2\]'
      r'|\[i\](.*?)\[\/i\]'
      r'|\[(rtl|ltr)\](.*?)\[\/\3\]'
      r'|\[color=([^\]]+)\](.*?)\[\/color\]'
      r'|\[bg=([^\]]+)\](.*?)\[\/bg\]'
      r'|(\[(?:\/?(?:y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)|size=\d+)\])',
      dotAll: true,
    );

    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }

      if (m.group(1) != null) {
        // **bold**
        final s = (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold);
        spans.add(TextSpan(text: '**', style: _tagStyle));
        spans.add(_buildMarkup(m.group(1)!, s));
        spans.add(TextSpan(text: '**', style: _tagStyle));
      } else if (m.group(2) != null) {
        // [y] yellow background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.yellow.withOpacity(0.4));
        spans.add(TextSpan(text: '[y]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(2)!, s));
        spans.add(TextSpan(text: '[/y]', style: _tagStyle));
      } else if (m.group(3) != null) {
        // [r] red background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.red.withOpacity(0.4));
        spans.add(TextSpan(text: '[r]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(3)!, s));
        spans.add(TextSpan(text: '[/r]', style: _tagStyle));
      } else if (m.group(4) != null) {
        // [g] green background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.green.withOpacity(0.4));
        spans.add(TextSpan(text: '[g]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(4)!, s));
        spans.add(TextSpan(text: '[/g]', style: _tagStyle));
      } else if (m.group(5) != null) {
        // [b] blue background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.blue.withOpacity(0.4));
        spans.add(TextSpan(text: '[b]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(5)!, s));
        spans.add(TextSpan(text: '[/b]', style: _tagStyle));
      } else if (m.group(6) != null) {
        // [o] orange background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.orange.withOpacity(0.4));
        spans.add(TextSpan(text: '[o]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(6)!, s));
        spans.add(TextSpan(text: '[/o]', style: _tagStyle));
      } else if (m.group(7) != null) {
        // [p] purple background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.purple.withOpacity(0.4));
        spans.add(TextSpan(text: '[p]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(7)!, s));
        spans.add(TextSpan(text: '[/p]', style: _tagStyle));
      } else if (m.group(8) != null) {
        // [c] cyan background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.cyan.withOpacity(0.4));
        spans.add(TextSpan(text: '[c]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(8)!, s));
        spans.add(TextSpan(text: '[/c]', style: _tagStyle));
      } else if (m.group(9) != null) {
        // [pk] pink background
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: Colors.pink.withOpacity(0.4));
        spans.add(TextSpan(text: '[pk]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(9)!, s));
        spans.add(TextSpan(text: '[/pk]', style: _tagStyle));
      } else if (m.group(10) != null) {
        // [yc] yellow text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.yellow.shade300);
        spans.add(TextSpan(text: '[yc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(10)!, s));
        spans.add(TextSpan(text: '[/yc]', style: _tagStyle));
      } else if (m.group(11) != null) {
        // [rc] red text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.red.shade300);
        spans.add(TextSpan(text: '[rc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(11)!, s));
        spans.add(TextSpan(text: '[/rc]', style: _tagStyle));
      } else if (m.group(12) != null) {
        // [gc] green text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.greenAccent.shade200);
        spans.add(TextSpan(text: '[gc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(12)!, s));
        spans.add(TextSpan(text: '[/gc]', style: _tagStyle));
      } else if (m.group(13) != null) {
        // [bc] blue text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.blue.shade300);
        spans.add(TextSpan(text: '[bc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(13)!, s));
        spans.add(TextSpan(text: '[/bc]', style: _tagStyle));
      } else if (m.group(14) != null) {
        // [oc] orange text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.orange.shade300);
        spans.add(TextSpan(text: '[oc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(14)!, s));
        spans.add(TextSpan(text: '[/oc]', style: _tagStyle));
      } else if (m.group(15) != null) {
        // [pc] purple text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.purple.shade200);
        spans.add(TextSpan(text: '[pc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(15)!, s));
        spans.add(TextSpan(text: '[/pc]', style: _tagStyle));
      } else if (m.group(16) != null) {
        // [cc] cyan text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.cyan.shade300);
        spans.add(TextSpan(text: '[cc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(16)!, s));
        spans.add(TextSpan(text: '[/cc]', style: _tagStyle));
      } else if (m.group(17) != null) {
        // [pkc] pink text
        final s = (base ?? const TextStyle()).copyWith(color: Colors.pink.shade300);
        spans.add(TextSpan(text: '[pkc]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(17)!, s));
        spans.add(TextSpan(text: '[/pkc]', style: _tagStyle));
      } else if (m.group(18) != null) {
        // [u] underline
        final s = (base ?? const TextStyle()).copyWith(decoration: TextDecoration.underline);
        spans.add(TextSpan(text: '[u]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(18)!, s));
        spans.add(TextSpan(text: '[/u]', style: _tagStyle));
      } else if (m.group(19) != null && m.group(20) != null) {
        // [size=N] font size
        final originalSize = double.tryParse(m.group(19)!) ?? 17;
        // Scale the visual size in the editor to show the difference but stay manageable
        final editorSize = 17 + (originalSize - 17) * 0.55;
        final sSize = (base ?? const TextStyle()).copyWith(fontSize: editorSize);
        spans.add(TextSpan(text: '[size=${m.group(19)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(20)!, sSize));
        spans.add(TextSpan(text: '[/size]', style: _tagStyle));
      } else if (m.group(21) != null && m.group(22) != null) {
        // [center|left|right]
        spans.add(TextSpan(text: '[${m.group(21)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(22)!, base));
        spans.add(TextSpan(text: '[/${m.group(21)}]', style: _tagStyle));
      } else if (m.group(23) != null) {
        // [i] italics
        final s = (base ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic);
        spans.add(TextSpan(text: '[i]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(23)!, s));
        spans.add(TextSpan(text: '[/i]', style: _tagStyle));
      } else if (m.group(24) != null && m.group(25) != null) {
        // [rtl|ltr]
        spans.add(TextSpan(text: '[${m.group(24)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(25)!, base));
        spans.add(TextSpan(text: '[/${m.group(24)}]', style: _tagStyle));
      } else if (m.group(26) != null && m.group(27) != null) {
        // [color=#HEX]
        final color = Color(int.tryParse(m.group(26)!.replaceFirst('#', '0xFF')) ?? 0xFFFFFFFF);
        final s = (base ?? const TextStyle()).copyWith(color: color);
        spans.add(TextSpan(text: '[color=${m.group(26)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(27)!, s));
        spans.add(TextSpan(text: '[/color]', style: _tagStyle));
      } else if (m.group(28) != null && m.group(29) != null) {
        // [bg=#HEX]
        final color = Color(int.tryParse(m.group(28)!.replaceFirst('#', '0xFF')) ?? 0x00000000);
        final s = (base ?? const TextStyle()).copyWith(backgroundColor: color);
        spans.add(TextSpan(text: '[bg=${m.group(28)}]', style: _tagStyle));
        spans.add(_buildMarkup(m.group(29)!, s));
        spans.add(TextSpan(text: '[/bg]', style: _tagStyle));
      } else if (m.group(30) != null) {
        // Standalone or malformed tag — render invisible
        spans.add(TextSpan(text: m.group(30)!, style: _tagStyle));
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

class _EditorBlock {
  final FocusNode focusNode;
  final _MarkupController controller;
  TextAlign textAlign;

  _EditorBlock({
    required this.focusNode,
    required this.controller,
    this.textAlign = TextAlign.left,
  });

  void dispose() {
    focusNode.dispose();
    controller.dispose();
  }
}

class _EditorState {
  final List<String> blockTexts;
  final List<TextAlign> blockAligns;
  _EditorState(this.blockTexts, this.blockAligns);
}

// ── Main screen ───────────────────────────────────────────────────────────────

class ScriptEditorScreen extends ConsumerStatefulWidget {
  const ScriptEditorScreen({super.key});

  @override
  ConsumerState<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends ConsumerState<ScriptEditorScreen> {
  final List<_EditorBlock> _blocks = [];
  final List<_EditorState> _history = [];
  int _historyIndex = -1;
  static const int _maxHistory = 10;

  bool _colorAsText = true;
  DateTime? _lastTap;
  int _titleTaps = 0;
  bool _isInit = false;
  _EditorBlock? _lastFocusedBlock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final script = ref.read(scriptProvider);
      if (script != null && !script.isEmpty) {
        _loadFromRawText(script.rawText); 
      } else if (ref.read(settingsProvider).lastScript.isNotEmpty) {
        _loadFromRawText(ref.read(settingsProvider).lastScript);
      } else {
        _addBlock(0);
      }
      _isInit = true;
      _saveHistory();
    }
  }

  void _loadFromRawText(String raw) {
    _disposeAllBlocks();
    final paragraphs = raw.split('\n');
    for (int i = 0; i < paragraphs.length; i++) {
        _blocks.add(_createBlock(paragraphs[i]));
    }
    if (_blocks.isEmpty) _addBlock(0);
  }

  _EditorBlock _createBlock(String text) {
    final textAlign = _detectAlignment(text);
    final focus = FocusNode();
    final ctrl = _MarkupController(text: text);
    final block = _EditorBlock(focusNode: focus, controller: ctrl, textAlign: textAlign);
    focus.addListener(() {
      if (focus.hasFocus) {
        _lastFocusedBlock = block;
        setState(() {});
      }
    });
    return block;
  }

  TextAlign _detectAlignment(String text) {
    if (text.contains('[center]')) return TextAlign.center;
    if (text.contains('[right]')) return TextAlign.right;
    return TextAlign.left;
  }

  void _disposeAllBlocks() {
    for (final b in _blocks) b.dispose();
    _blocks.clear();
  }

  @override
  void dispose() {
    _disposeAllBlocks();
    super.dispose();
  }

  void _addBlock(int index, {String text = ''}) {
    final block = _createBlock(text);
    setState(() => _blocks.insert(index, block));
    Future.microtask(() => block.focusNode.requestFocus());
  }

  // ── Formatting & History helpers ───────────────────────────────────────────

  _EditorBlock? get _currentBlock {
    for (final b in _blocks) if (b.focusNode.hasFocus) return b;
    if (_lastFocusedBlock != null && _blocks.contains(_lastFocusedBlock)) {
      return _lastFocusedBlock;
    }
    return _blocks.isNotEmpty ? _blocks.last : null;
  }

  void _saveHistory() {
      final state = _EditorState(
          _blocks.map((b) => b.controller.text).toList(),
          _blocks.map((b) => b.textAlign).toList(),
      );
      if (_historyIndex < _history.length - 1) {
          _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(state);
      if (_history.length > _maxHistory) _history.removeAt(0);
      _historyIndex = _history.length - 1;
      setState(() {});
  }

  void _undo() {
      if (_historyIndex > 0) {
          _historyIndex--;
          _applyState(_history[_historyIndex]);
          setState(() {});
      }
  }

  void _redo() {
      if (_historyIndex < _history.length - 1) {
          _historyIndex++;
          _applyState(_history[_historyIndex]);
          setState(() {});
      }
  }

  void _applyState(_EditorState state) {
      _disposeAllBlocks();
      for (int i = 0; i < state.blockTexts.length; i++) {
          final block = _createBlock(state.blockTexts[i]);
          block.textAlign = state.blockAligns[i];
          _blocks.add(block);
      }
  }

  void _wrapSelection(String open, String close) {
    final block = _currentBlock;
    if (block == null) return;
    final ctrl = block.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;

    final before = text.substring(0, sel.start);
    final selected = text.substring(sel.start, sel.end);
    final after = text.substring(sel.end);

    ctrl.value = ctrl.value.copyWith(
      text: '$before$open$selected$close$after',
      selection: TextSelection.collapsed(offset: before.length + open.length + selected.length + close.length),
    );
    _saveHistory();
  }

  void _applyColor(String tagOrHex) {
    if (tagOrHex.startsWith('#')) {
      if (_colorAsText) {
        _wrapSelection('[color=$tagOrHex]', '[/color]');
      } else {
        _wrapSelection('[bg=$tagOrHex]', '[/bg]');
      }
    } else {
      if (_colorAsText) {
        _wrapSelection('[${tagOrHex}c]', '[/${tagOrHex}c]');
      } else {
        _wrapSelection('[$tagOrHex]', '[/$tagOrHex]');
      }
    }
  }

  void _applyAlign(String align) {
    final block = _currentBlock;
    if (block == null) return;

    setState(() {
        if (align == 'center') {
            block.textAlign = TextAlign.center;
            _ensureTag(block, '[center]', '[/center]');
        } else if (align == 'right') {
            block.textAlign = TextAlign.right;
            _ensureTag(block, '[right]', '[/right]');
        } else {
            block.textAlign = TextAlign.left;
            _removeAlignTags(block);
        }
    });
    _saveHistory();
  }

  void _ensureTag(_EditorBlock block, String startTag, String endTag) {
      _removeAlignTags(block);
      block.controller.text = '$startTag${block.controller.text}$endTag';
  }

  void _removeAlignTags(_EditorBlock block) {
      String t = block.controller.text;
      t = t.replaceAll('[center]', '').replaceAll('[/center]', '');
      t = t.replaceAll('[right]', '').replaceAll('[/right]', '');
      t = t.replaceAll('[left]', '').replaceAll('[/left]', '');
      block.controller.text = t;
  }

  // ── File operations ────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    FilePickerResult? result;
    try {
      // Use FileType.any so OS doesn't grey out .rtf/others. We validate after.
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Choose a script file',
      );
    } catch (_) {
      return;
    }
    if (result == null) return;

    final path = result.files.single.path;
    if (path == null) return;

    // Flexible validation: looks for the extension even if suffixes like (1) are present
    final lower = path.toLowerCase();
    final isSupported = RegExp(r'\.(txt|rtf|doc|docx|pdf|odt)(\(\d+\))?$').hasMatch(lower);
    
    if (!isSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unsupported file type. Please use .txt, .rtf, .pdf or .doc files.')));
      }
      return;
    }

    final rawBytes = await File(path).readAsBytes();
    String content;

    // Detect if it's a binary format we need to extract from
    if (lower.contains('.pdf')) {
       // Placeholder for PDF extraction — for now we try to read strings
       content = utf8.decode(rawBytes, allowMalformed: true).replaceAll(RegExp(r'[^\x20-\x7E\s\u05D0-\u05EA]'), ' ');
    } else if (lower.contains('.rtf')) {
      content = _stripRtf(utf8.decode(rawBytes, allowMalformed: true));
    } else {
      content = utf8.decode(rawBytes, allowMalformed: true);
    }

    if (content.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('File appears empty or could not be read.')));
      }
      return;
    }

    _loadFromRawText(content);
    ref.read(scriptProvider.notifier).loadText(content);
    setState(() {});
  }

  Future<void> _saveScript() async {
    final text = _blocks.map((b) => b.controller.text).join('\n');
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to save — script is empty.')));
      }
      return;
    }

    // Step 1: Choose format
    final format = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Save Format', style: TextStyle(color: Colors.white)),
        content: const Text('Choose the file format:',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'txt'),
            child: const Text('Plain Text (.txt)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'rtf'),
            child: const Text('Rich Text (.rtf)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    // Step 2: Choose filename
    final nameCtrl = TextEditingController(text: 'my_script');
    
    // Auto-suggest next number if we have a registry (simplified for now via Prefs)
    final prefs = await SharedPreferences.getInstance();
    final usedNames = prefs.getStringList('used_script_names') ?? [];
    
    String suggested = 'my_script';
    int bestNum = 0;
    for (final un in usedNames) {
      if (un == suggested) {
        if (bestNum == 0) bestNum = 1;
      } else if (un.startsWith('$suggested(')) {
        final match = RegExp(r'\((\d+)\)').firstMatch(un);
        if (match != null) {
          final n = int.parse(match.group(1)!);
          if (n >= bestNum) bestNum = n + 1;
        }
      }
    }
    if (bestNum > 0) suggested = '$suggested($bestNum)';
    nameCtrl.text = suggested;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SaveNameDialog(nameCtrl: nameCtrl, usedNames: usedNames, format: format!),
    );
    if (result == null || !mounted) return;

    final chosenName = result['name'] as String;
    final isOverwrite = result['replace'] == true;

    // Step 3: Encode
    final List<int> bytes =
        format == 'rtf' ? utf8.encode(_toRtf(text)) : utf8.encode(text);

    // Step 4: Save via file picker
    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save script',
        fileName: '$chosenName.$format',
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      if (savedPath != null) {
        // Record this name
        if (!usedNames.contains(chosenName)) {
           usedNames.add(chosenName);
           await prefs.setStringList('used_script_names', usedNames);
        }
        
        await ref.read(settingsProvider.notifier).saveScript(text);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isOverwrite ? 'Replaced: $chosenName.$format' : 'Saved: $chosenName.$format'),
          backgroundColor: const Color(0xFF2A6B2A),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        backgroundColor: Colors.red.shade800,
      ));
    }
  }

  void _clearScript() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Clear script?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This will remove the current text.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _disposeAllBlocks();
                _addBlock(0);
                ref.read(scriptProvider.notifier).loadText('');
              });
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _startPresenting() {
    final text = _blocks.map((b) => b.controller.text).join('\n').trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please enter or import a script first.')));
      return;
    }
    ref.read(scriptProvider.notifier).loadText(text);
    ref.read(teleprompterProvider.notifier).resetPosition();
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const TeleprompterScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  // ── RTF parser ─────────────────────────────────────────────────────────────

  String _stripRtf(String rtf) {
    String text = rtf;

    text = text.replaceAll(
        RegExp(r'\{\\fonttbl(?:[^{}]|\{[^{}]*\})*\}'), '');
    text = text.replaceAll(
        RegExp(r'\{\\colortbl(?:[^{}]|\{[^{}]*\})*\}'), '');
    text = text.replaceAll(
        RegExp(r'\{\\\*\\expandedcolortbl(?:[^{}]|\{[^{}]*\})*\}'), '');
    text = text.replaceAll(
        RegExp(r'\{\\info(?:[^{}]|\{[^{}]*\})*\}', dotAll: true), '');
    text = text.replaceAll(RegExp(r'\{\\\*[^}]*\}'), '');

    text = text.replaceAll(RegExp(r'\\pard\b[^\\{}\n]*'), '\n');
    text = text.replaceAll(RegExp(r'\\par\b'), '\n');
    text = text.replaceAll(RegExp(r'\\line\b'), '\n');
    text = text.replaceAll(RegExp(r'\\page\b'), '\n\n');
    text = text.replaceAll(RegExp(r'\\uc\d+\s?'), '');

    // Hebrew/Unicode: \uN? — consume the RTF delimiter space that follows
    text = text.replaceAllMapped(RegExp(r'\\u(-?\d+)\??\s?'), (m) {
      final code = int.tryParse(m.group(1)!) ?? 0;
      final charCode = code < 0 ? code + 65536 : code;
      return String.fromCharCode(charCode);
    });

    // Aggressive space-collapsing removed as it was destroying legitimate word boundaries.

    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+[-]?\d*[ \t]?'), '');
    text = text.replaceAll('{', '').replaceAll('}', '');
    text = text.replaceAll(RegExp(r'\\[^a-zA-Z\s]'), '');

    text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text;
  }

  String _toRtf(String text) {
    final buf = StringBuffer();
    buf.write(r'{\rtf1\ansi\ansicpg65001\uc0' '\n');
    buf.write(r'{\fonttbl\f0\froman\fcharset0 TimesNewRomanPSMT;}' '\n');
    buf.write(r'\f0\fs28' '\n');

    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        buf.write(r'\par' '\n');
        continue;
      }
      for (final char in line.runes) {
        if (char > 127) {
          final code = char > 32767 ? char - 65536 : char;
          buf.write('\\u$code?');
        } else {
          buf.write(String.fromCharCode(char));
        }
      }
      buf.write(r'\par' '\n');
    }
    buf.write('}');
    return buf.toString();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: GestureDetector(
          onTap: () {
            final now = DateTime.now();
            if (_lastTap == null || now.difference(_lastTap!) > const Duration(milliseconds: 1000)) {
              _titleTaps = 1;
            } else {
              _titleTaps++;
            }
            _lastTap = now;
            if (_titleTaps >= 5) {
              _titleTaps = 0;
              ref.read(settingsProvider.notifier).toggleDebugMode();
              final isDebug = ref.read(settingsProvider).debugMode;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Technical Debug Mode: ${isDebug ? "ENABLED" : "DISABLED"}'),
                backgroundColor: isDebug ? Colors.orange.shade800 : Colors.blue.shade800,
                duration: const Duration(seconds: 1),
              ));
            }
          },
          child: const Text('AutoTeleprompt',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'Settings',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const LobbySettingsPanel(),
              );
            },
          ),
          if (_blocks.any((b) => b.controller.text.isNotEmpty))
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              tooltip: 'Clear script',
              onPressed: _clearScript,
            ),
          IconButton(
            icon: const Icon(Icons.save_alt, color: Colors.white70),
            tooltip: 'Save script',
            onPressed: _saveScript,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white70),
            tooltip: 'Import .txt or .rtf',
            onPressed: _pickFile,
          ),
        ],
      ),
      body: Column(
        children: [
          _FormattingToolbar(
            colorAsText: _colorAsText,
            onToggleColorMode: () => setState(() => _colorAsText = !_colorAsText),
            onBold: () => _wrapSelection('**', '**'),
            onUnderline: () => _wrapSelection('[u]', '[/u]'),
            onItalic: () => _wrapSelection('[i]', '[/i]'),
            onClear: () {
              final block = _currentBlock;
              if (block == null) return;
              block.controller.text = block.controller.text.replaceAll(RegExp(r'\[.*?\]|\*\*'), '');
              _saveHistory();
            },
            onFontSize: (size) => _wrapSelection('[size=$size]', '[/size]'),
            onAlign: _applyAlign,
            onDirection: (dir) => _wrapSelection('[$dir]', '[/$dir]'),
            onColorSelected: _applyColor,
            onUndo: _undo,
            onRedo: _redo,
            canUndo: _historyIndex > 0,
            canRedo: _historyIndex < _history.length - 1,
          ),
          Expanded(
            child: Container(
              color: Color(settings.scriptBgColor),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                itemCount: _blocks.length,
                itemBuilder: (context, index) {
                  final block = _blocks[index];
                  // Only show placeholder on the very last block if it is empty
                  final showHint = index == _blocks.length - 1 && block.controller.text.isEmpty;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2.0), // Tightened spacing
                    child: TextField(
                      controller: block.controller,
                      focusNode: block.focusNode,
                      textAlign: block.textAlign,
                      maxLines: null,
                      minLines: 1,
                      cursorColor: const Color(0xFFFFBF00),
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 17, 
                        height: 1.4, // Slightly tighter line height
                        letterSpacing: settings.letterSpacing,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        hintText: showHint ? 'Type paragraph here...' : null,
                        hintStyle: const TextStyle(color: Colors.white10),
                      ),
                      onChanged: (text) {
                          if (text.contains('\n')) {
                              final parts = text.split('\n');
                              block.controller.text = parts[0];
                              for (int i = 1; i < parts.length; i++) {
                                  _addBlock(index + i, text: parts[i]);
                              }
                              _saveHistory();
                          } else {
                              _saveHistory();
                          }
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _startPresenting,
                icon: const Icon(Icons.play_arrow_rounded, size: 26),
                label: const Text('Start Presenting',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formatting toolbar ─────────────────────────────────────────────────────

class _FormattingToolbar extends StatelessWidget {
  final bool colorAsText;
  final VoidCallback onToggleColorMode;
  final VoidCallback onBold;
  final VoidCallback onUnderline;
  final VoidCallback onItalic;
  final VoidCallback onClear;
  final ValueChanged<int> onFontSize;
  final ValueChanged<String> onAlign;
  final ValueChanged<String> onDirection;
  final ValueChanged<String> onColorSelected;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;

  const _FormattingToolbar({
    required this.colorAsText,
    required this.onToggleColorMode,
    required this.onBold,
    required this.onUnderline,
    required this.onItalic,
    required this.onClear,
    required this.onFontSize,
    required this.onAlign,
    required this.onDirection,
    required this.onColorSelected,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ToolBtn(label: '⎌', bold: false, tooltip: 'Undo', onTap: onUndo, color: canUndo ? Colors.white : Colors.white10),
              const SizedBox(width: 8),
              _ToolBtn(label: '↻', bold: false, tooltip: 'Redo', onTap: onRedo, color: canRedo ? Colors.white : Colors.white10),
              const SizedBox(width: 8),
              const VerticalDivider(color: Colors.white10),
              _ToolBtn(label: 'B', bold: true, tooltip: 'Bold', onTap: onBold),
              const SizedBox(width: 8),
              _ToolBtn(label: 'I', bold: false, italic: true, tooltip: 'Italic', onTap: onItalic),
              const SizedBox(width: 8),
              _ToolBtn(label: 'U', bold: false, underline: true, tooltip: 'Underline', onTap: onUnderline),
              const SizedBox(width: 8),
              _ToolBtn(label: '⌫', bold: false, tooltip: 'Clear', onTap: onClear, color: Colors.redAccent.withOpacity(0.8)),
              const Spacer(),
              _FontSizePicker(onFontSize: onFontSize),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _AlignPicker(onAlign: onAlign),
              const SizedBox(width: 8),
              _DirectionPicker(onDirection: onDirection),
              const Spacer(),
              _ColorPicker(colorAsText: colorAsText, onColorSelected: onColorSelected),
              const SizedBox(width: 8),
              _ColorModeToggle(isActive: colorAsText, onTap: onToggleColorMode),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const _HistoryBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      color: enabled ? Colors.amber : Colors.white24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _ColorModeToggle extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  const _ColorModeToggle({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2A2A5A) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFFFFBF00) : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          isActive ? 'TEXT' : 'BG',
          style: TextStyle(
            color: isActive ? const Color(0xFFFFBF00) : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final String label;
  final bool bold;
  final bool italic;
  final String tooltip;
  final VoidCallback onTap;
  final bool underline;
  final Color? color;

  const _ToolBtn({
    required this.label,
    required this.bold,
    required this.tooltip,
    required this.onTap,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: color ?? Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _FontSizePicker extends StatelessWidget {
  final ValueChanged<int> onFontSize;
  const _FontSizePicker({required this.onFontSize});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Font Size',
      onSelected: onFontSize,
      padding: EdgeInsets.zero,
      color: const Color(0xFF1F1F1F),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_size, color: Colors.white70, size: 16),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => [
        14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96
      ].map((size) => PopupMenuItem(
        value: size,
        child: Text('${size}pt', style: const TextStyle(color: Colors.white)),
      )).toList(),
    );
  }
}

class _AlignPicker extends StatelessWidget {
  final ValueChanged<String> onAlign;
  const _AlignPicker({required this.onAlign});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Alignment',
      onSelected: onAlign,
      padding: EdgeInsets.zero,
      color: const Color(0xFF1F1F1F),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_align_center, color: Colors.white70, size: 16),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'left', child: Text('Left', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'center', child: Text('Center', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'right', child: Text('Right', style: TextStyle(color: Colors.white))),
      ],
    );
  }
}

class _DirectionPicker extends StatelessWidget {
  final ValueChanged<String> onDirection;
  const _DirectionPicker({required this.onDirection});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Text Direction',
      onSelected: onDirection,
      padding: EdgeInsets.zero,
      color: const Color(0xFF1F1F1F),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_textdirection_l_to_r, color: Colors.white70, size: 16),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'ltr', child: Text('LTR (English)', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'rtl', child: Text('RTL (Hebrew)', style: TextStyle(color: Colors.white))),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final bool colorAsText;
  final ValueChanged<String> onColorSelected;

  const _ColorPicker({
    required this.colorAsText,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GlobalColorButton(
      color: 0xFFFFBF00, // Dummy base
      title: colorAsText ? 'Text Color' : 'Highlight',
      onColorChanged: (c) {
        final hex = '#' + c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
        onColorSelected(hex);
      },
    );
  }
}

// ── Lobby Settings Panel ───────────────────────────────────────────────────

class LobbySettingsPanel extends ConsumerWidget {
  const LobbySettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    const labelStyle = TextStyle(color: Colors.white70, fontSize: 13);
    const sectionStyle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.60,
      maxChildSize: 0.85,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          const Text('Styling Options', style: sectionStyle),
          const SizedBox(height: 24),

          // Word Spacing
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Word Spacing', style: labelStyle)),
              Expanded(
                flex: 5,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: settings.wordSpacing,
                    min: 0, max: 40, divisions: 8,
                    activeColor: Colors.amber, inactiveColor: Colors.white24,
                    onChanged: notifier.setWordSpacing,
                  ),
                ),
              ),
              SizedBox(width: 40, child: Text('${settings.wordSpacing.toStringAsFixed(1)}px', style: labelStyle)),
            ],
          ),
          const SizedBox(height: 12),

          // Letter Spacing
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Letter Spacing', style: labelStyle)),
              Expanded(
                flex: 5,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: settings.letterSpacing,
                    min: 0, max: 4, divisions: 8,
                    activeColor: Colors.amber, inactiveColor: Colors.white24,
                    onChanged: notifier.setLetterSpacing,
                  ),
                ),
              ),
              SizedBox(width: 40, child: Text('${settings.letterSpacing.toStringAsFixed(1)}px', style: labelStyle)),
            ],
          ),
          const SizedBox(height: 12),

          // Line Spacing
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Line Spacing', style: labelStyle)),
              Expanded(
                flex: 5,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: settings.lineSpacing,
                    min: 1.0, max: 3.0, divisions: 20,
                    activeColor: Colors.amber, inactiveColor: Colors.white24,
                    onChanged: notifier.setLineSpacing,
                  ),
                ),
              ),
              SizedBox(width: 40, child: Text(settings.lineSpacing.toStringAsFixed(1), style: labelStyle)),
            ],
          ),
          const SizedBox(height: 12),

          // Background Color
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Script Background', style: labelStyle)),
              Expanded(
                flex: 5,
                child: GlobalColorButton(
                  color: settings.scriptBgColor,
                  onColorChanged: notifier.setScriptBgColor,
                  title: 'Script Background',
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          const Text('Scroll Settings', style: sectionStyle),
          const SizedBox(height: 24),

          // Manual Speed
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Starting Speed', style: labelStyle)),
              Expanded(
                flex: 5,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: settings.scrollSpeed,
                    min: -400, max: 400, divisions: 160,
                    activeColor: Colors.amber, inactiveColor: Colors.white24,
                    onChanged: notifier.setScrollSpeed,
                  ),
                ),
              ),
              SizedBox(width: 40, child: Text('${settings.scrollSpeed.round()}', style: labelStyle)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Aligner Unspeakable Helper ───────────────────────────────────────────

bool _isUnspeakable(ScriptWord word) {
  final norm = word.normalized;
  if (norm.isEmpty) return true;
  // If it's just numbers, dots, and colons (dates, times, counts)
  if (RegExp(r'^[0-9\.:\-\/]+$').hasMatch(norm)) return true;
  return false;
}

// ── Smart Save Dialog ──────────────────────────────────────────────────────

class _SaveNameDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final List<String> usedNames;
  final String format;

  const _SaveNameDialog({
    required this.nameCtrl,
    required this.usedNames,
    required this.format,
  });

  @override
  State<_SaveNameDialog> createState() => _SaveNameDialogState();
}

class _SaveNameDialogState extends State<_SaveNameDialog> {
  bool get _exists => widget.usedNames.contains(widget.nameCtrl.text.trim());

  @override
  void initState() {
    super.initState();
    widget.nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    widget.nameCtrl.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  void _autoNumber() {
    final base = widget.nameCtrl.text.trim().replaceAll(RegExp(r'\(\d+\)$'), '');
    int num = 1;
    while (widget.usedNames.contains('$base($num)')) {
      num++;
    }
    widget.nameCtrl.text = '$base($num)';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF131313),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('File Name', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.nameCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'my_script',
              hintStyle: const TextStyle(color: Colors.white24),
              suffixText: '.${widget.format}',
              suffixStyle: const TextStyle(color: Colors.white38),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFBF00))),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFCC33))),
            ),
          ),
          if (_exists)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  const Text('File already exists', style: TextStyle(color: Colors.orange, fontSize: 12)),
                  const Spacer(),
                  TextButton(
                    onPressed: _autoNumber,
                    child: const Text('Use Number (1)', style: TextStyle(color: Color(0xFFFFBF00), fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _exists ? Colors.blueGrey.shade800 : const Color(0xFFFFBF00),
            foregroundColor: _exists ? Colors.white70 : Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () {
            final name = widget.nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {'name': name, 'replace': _exists});
          },
          child: Text(_exists ? 'Replace Existing' : 'Save'),
        ),
      ],
    );
  }
}

