import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/script.dart';
import '../models/script_word.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../features/teleprompter/services/word_aligner.dart';

class ScriptNotifier extends Notifier<Script?> {
  @override
  Script? build() {
    // Load last saved script on startup
    final settings = ref.read(settingsProvider);
    final lastText = settings.lastScript;
    final lastTitle = settings.lastScriptTitle;
    
    String sourceType = 'TEMP';
    String? sessionId;
    int? historyIndex;
    double? fontSize, lineSpacing, letterSpacing, wordSpacing;
    String? fontFamily, textAlign;
    int? scriptBgColor, currentWordColor, futureWordColor;

    for (final json in settings.recentScripts) {
      try {
        final meta = jsonDecode(json);
        if (meta['fullText'] == lastText || meta['sessionId'] == sessionId || meta['title'] == lastTitle) {
          sourceType = meta['type'] ?? 'TEMP';
          sessionId = meta['sessionId'];
          final metaIdx = meta['historyIndex'];
          if (metaIdx != null) historyIndex = metaIdx;

          // v3.9.5.70: Extract styling metadata (Nested for Gallery Compatibility)
          final style = meta['style'] as Map<String, dynamic>?;
          if (style != null) {
            if (style['fontSize'] != null) fontSize = (style['fontSize'] as num).toDouble();
            if (style['fontFamily'] != null) fontFamily = style['fontFamily'];
            if (style['lineSpacing'] != null) lineSpacing = (style['lineSpacing'] as num).toDouble();
            if (style['letterSpacing'] != null) letterSpacing = (style['letterSpacing'] as num).toDouble();
            if (style['wordSpacing'] != null) wordSpacing = (style['wordSpacing'] as num).toDouble();
            if (style['textAlign'] != null) textAlign = style['textAlign'];
            if (style['scriptBgColor'] != null) scriptBgColor = style['scriptBgColor'];
            if (style['currentWordColor'] != null) currentWordColor = style['currentWordColor'];
            if (style['futureWordColor'] != null) futureWordColor = style['futureWordColor'];
          }
          
          break;
        }
      } catch (_) {}
    }

    if (lastText.isNotEmpty) {
      return _buildScript(lastText, 
        title: lastTitle.isNotEmpty ? lastTitle : null, 
        sourceType: sourceType, 
        sessionId: sessionId,
        historyIndex: historyIndex ?? settings.lastHistoryIndex,
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textAlign: textAlign,
        scriptBgColor: scriptBgColor,
        currentWordColor: currentWordColor,
        futureWordColor: futureWordColor,
      );
    }
    return null;
  }

  Script _buildScript(String text, {
    String? title, 
    String? sourceType, 
    String? sessionId, 
    String? historyJson, 
    int? historyIndex,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
  }) {
    final words = WordAligner.tokenize(text);
    final isRtl = text.isHebrew;
    
    // v3.9.5.46: Pull baseline from settings if not provided by import
    final settings = ref.read(settingsProvider);

    return Script(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ?? (text.split('\n').first.trim().isNotEmpty
          ? text.split('\n').first.trim().substring(0, text.split('\n').first.trim().length.clamp(0, 40))
          : 'Script'),
      rawText: text,
      words: words,
      isRtl: isRtl,
      sourceType: sourceType ?? 'TEMP',
      sessionId: sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      historyJson: historyJson,
      historyIndex: historyIndex ?? -1,
      fontSize: fontSize ?? 18.0,
      fontFamily: fontFamily ?? 'Inter',
      lineSpacing: lineSpacing ?? settings.lineSpacing,
      letterSpacing: letterSpacing ?? settings.letterSpacing,
      wordSpacing: wordSpacing ?? settings.wordSpacing,
      textAlign: textAlign ?? settings.textAlign,
      scriptBgColor: scriptBgColor ?? settings.scriptBgColor,
      currentWordColor: currentWordColor ?? settings.currentWordColor,
      futureWordColor: futureWordColor ?? settings.futureWordColor,
    );
  }

  void loadText(String text, {
    String? title, 
    String? sourceType, 
    String? sessionId, 
    String? historyJson, 
    int? historyIndex,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
  }) {
    state = _buildScript(text, 
      title: title, 
      sourceType: sourceType, 
      sessionId: sessionId, 
      historyJson: historyJson, 
      historyIndex: historyIndex,
      fontSize: fontSize,
      fontFamily: fontFamily,
      lineSpacing: lineSpacing,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textAlign: textAlign,
      scriptBgColor: scriptBgColor,
      currentWordColor: currentWordColor,
      futureWordColor: futureWordColor,
    );
    ref.read(settingsProvider.notifier).saveScript(
      text, 
      title: title, 
      historyIndex: historyIndex,
      fontSize: fontSize,
      fontFamily: fontFamily,
      lineSpacing: lineSpacing,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textAlign: textAlign,
      scriptBgColor: scriptBgColor,
      currentWordColor: currentWordColor,
      futureWordColor: futureWordColor,
      historyJson: historyJson,
    );
  }

  Future<_ParsedFile> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    final rawBytes = await file.readAsBytes();
    _ParsedFile result = _ParsedFile('');

    try {
      if (lower.endsWith('.docx')) {
        result = _parseDocx(rawBytes);
      } else if (lower.endsWith('.rtf') || lower.endsWith('.doc')) {
        final raw = utf8.decode(rawBytes, allowMalformed: true);
        if (raw.trimLeft().startsWith('{\\rtf')) {
          result = _parseRtf(raw);
        } else {
          final content = String.fromCharCodes(
            rawBytes.where((b) => (b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D),
          ).replaceAll(RegExp(r'[ \t]{3,}'), '  ')
           .replaceAll(RegExp(r'\n{3,}'), '\n\n')
           .trim();
          result = _ParsedFile(content);
        }
      } else {
        result = _ParsedFile(utf8.decode(rawBytes, allowMalformed: true));
      }
    } catch (e) {
      final errStr = e.toString();
      String errContent = '';
      if (errStr.contains('Central Directory') || errStr.contains('Format')) {
        errContent = 'This file appears to be corrupted or is not a valid ${file.path.split('.').last.toUpperCase()} file.';
      } else {
        errContent = 'Error loading file: $errStr';
      }
      result = _ParsedFile(errContent);
    }
    return result;
  }

  Future<void> importFile(File file) async {
    final result = await parseFile(file);
    if (result.text.isNotEmpty) {
      final title = file.path.split('/').last;
      final extension = title.contains('.') ? title.split('.').last.toUpperCase() : 'FILE';
      loadText(result.text, title: title, sourceType: extension, fontSize: result.fontSize);
    }
  }

  _ParsedFile _parseDocx(List<int> rawBytes) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    double? detectedFontSize;

    // Find document.xml — try common paths
    ArchiveFile? docEntry;
    for (final candidate in ['word/document.xml', 'word/Document.xml']) {
      docEntry = archive.findFile(candidate);
      if (docEntry != null) break;
    }
    if (docEntry == null) {
      for (final f in archive.files) {
        if (f.name.toLowerCase().endsWith('document.xml')) {
          docEntry = f;
          break;
        }
      }
    }
    if (docEntry == null) throw Exception('No document.xml in DOCX');

    // Get bytes safely — archive 3.x content can be List<int> or InputStream
    final dynamic rawContent = docEntry.content;
    final List<int> bytes;
    if (rawContent is List<int>) {
      bytes = rawContent;
    } else {
      bytes = List<int>.from(rawContent);
    }

    final xmlStr = utf8.decode(bytes, allowMalformed: true);
    final document = XmlDocument.parse(xmlStr);
    final paragraphs = document.findAllElements('w:p').toList();
    final buf = StringBuffer();

    for (final p in paragraphs) {
      for (final r in p.findAllElements('w:r')) {
        final rPr = r.getElement('w:rPr');
        final textNode = r.getElement('w:t');
        if (textNode == null) continue;

        String text = textNode.innerText;
        if (text.isEmpty) continue;

        if (rPr != null) {
          final isBold = rPr.getElement('w:b') != null;
          final color = rPr.getElement('w:color')?.getAttribute('w:val');
          
          if (detectedFontSize == null) {
            final sz = rPr.getElement('w:sz')?.getAttribute('w:val') ?? 
                       rPr.getElement('w:szCs')?.getAttribute('w:val');
            if (sz != null) {
              final halfPoints = double.tryParse(sz);
              if (halfPoints != null) detectedFontSize = halfPoints / 2.0;
            }
          }

          if (color != null && color != 'auto') {
            text = '[color=#$color]$text[/color]';
          }
          if (isBold) {
            text = '**$text**';
          }
        }
        buf.write(text);
      }
      buf.write('\n');
    }

    // Background color detection
    try {
      final background = document.rootElement.getElement('w:background');
      final bgColorVal = background?.getAttribute('w:color');
      if (bgColorVal != null && bgColorVal != 'auto') {
        final colorInt = int.parse('FF$bgColorVal', radix: 16);
        ref.read(settingsProvider.notifier).setScriptBgColor(colorInt);
      } else if (paragraphs.isNotEmpty) {
        final shd = paragraphs.first.getElement('w:pPr')?.getElement('w:shd')?.getAttribute('w:fill');
        if (shd != null && shd != 'auto' && shd != 'clear') {
          final colorInt = int.parse('FF$shd', radix: 16);
          ref.read(settingsProvider.notifier).setScriptBgColor(colorInt);
        }
      }
    } catch (_) {}

    return _ParsedFile(buf.toString().trim(), fontSize: detectedFontSize);
  }

  /// Parses RTF, extracts text with style markup (bold, color, size).
  _ParsedFile _parseRtf(String raw) {
    double? detectedFontSize;
    // ── Step 1: Extract color table ──
    final colorTable = <String>['000000']; // index 0 = auto/default
    final ctMatch = RegExp(r'\{\\colortbl\s*;?([^}]*)\}').firstMatch(raw);
    if (ctMatch != null) {
      final parts = ctMatch.group(1)!.split(';');
      for (final part in parts) {
        if (part.trim().isEmpty) continue;
        final r = RegExp(r'\\red(\d+)').firstMatch(part);
        final g = RegExp(r'\\green(\d+)').firstMatch(part);
        final b = RegExp(r'\\blue(\d+)').firstMatch(part);
        if (r != null && g != null && b != null) {
          colorTable.add(
            '${int.parse(r.group(1)!).toRadixString(16).padLeft(2, '0')}'
            '${int.parse(g.group(1)!).toRadixString(16).padLeft(2, '0')}'
            '${int.parse(b.group(1)!).toRadixString(16).padLeft(2, '0')}',
          );
        }
      }
    }

    // ── Step 2: Walk the document ──
    const skipGroupWords = {
      // Header / metadata
      'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object',
      // Page headers / footers
      'header', 'footer', 'headerl', 'headerr', 'headerf',
      'footerl', 'footerr', 'footerf',
      // Footnotes
      'footnote', 'ftnsep', 'ftnsepc', 'ftncn',
      // Fields
      'field', 'fldinst', 'datafield',
      // List / numbering (produces stray "0", "1.", etc.)
      'listtable', 'listoverridetable', 'listtext',
      'pn', 'pntext', 'pntxta', 'pntxtb', 'pnseclvl',
      // Revision / metadata tables
      'revtbl', 'rsidtbl',
      // Theme / XML
      'themedata', 'colorschememapping', 'mmathPr', 'xmlnstbl',
      'latentstyles', 'datastore', 'defchp', 'defpap',
      'pgdsctbl', 'wgrffmtfilter', 'filetbl', 'upr',
    };

    // Formatting state (no size — teleprompter controls its own font size)
    bool bold = false;
    int cfIndex = 0;

    // Collect styled runs
    final runs = <_RtfRun>[];
    var currentText = StringBuffer();

    void flushRun() {
      if (currentText.isEmpty) return;
      runs.add(_RtfRun(currentText.toString(), bold, cfIndex));
      currentText = StringBuffer();
    }

    int i = 0;
    int depth = 0;
    final skipDepths = <int>[];

    while (i < raw.length) {
      final c = raw[i];

      if (c == '{') {
        depth++;
        if (skipDepths.isEmpty) {
          // Ignorable destination {\*...}
          if (i + 2 < raw.length && raw[i + 1] == '\\' && raw[i + 2] == '*') {
            skipDepths.add(depth);
          } else if (i + 1 < raw.length && raw[i + 1] == '\\') {
            // Peek at control word to check for header groups
            int j = i + 2;
            final wb = StringBuffer();
            while (j < raw.length && _isAlpha(raw.codeUnitAt(j))) {
              wb.writeCharCode(raw.codeUnitAt(j));
              j++;
            }
            if (skipGroupWords.contains(wb.toString())) {
              skipDepths.add(depth);
            }
          }
        }
        i++;
        continue;
      }

      if (c == '}') {
        if (skipDepths.isNotEmpty && skipDepths.last == depth) {
          skipDepths.removeLast();
        }
        depth--;
        i++;
        continue;
      }

      if (skipDepths.isNotEmpty) { i++; continue; }

      if (c == '\\') {
        i++;
        if (i >= raw.length) break;
        final next = raw[i];

        // Literal escapes
        if (next == '\\') { currentText.write('\\'); i++; continue; }
        if (next == '{')  { currentText.write('{');  i++; continue; }
        if (next == '}')  { currentText.write('}');  i++; continue; }
        if (next == '\n' || next == '\r') { flushRun(); currentText.write('\n'); flushRun(); i++; continue; }

        // Hex escape \' XX (Windows-1252 codepage for bytes 0x80-0x9F)
        if (next == '\'') {
          i++;
          if (i + 1 < raw.length) {
            final code = int.tryParse(raw.substring(i, i + 2), radix: 16);
            if (code != null && code > 31) {
              currentText.writeCharCode(_win1252ToUnicode(code));
            }
            i += 2;
          }
          continue;
        }

        // Unicode escape \uNNNN? — only if followed by a digit or minus sign.
        // Control words like \uc, \ul, \ulnone start with 'u' but are NOT unicode escapes.
        if (next == 'u' && (i + 1) < raw.length &&
            (raw.codeUnitAt(i + 1) >= 0x30 && raw.codeUnitAt(i + 1) <= 0x39 || raw[i + 1] == '-')) {
          i++;
          final nb = StringBuffer();
          if (i < raw.length && raw[i] == '-') { nb.write('-'); i++; }
          while (i < raw.length && raw.codeUnitAt(i) >= 0x30 && raw.codeUnitAt(i) <= 0x39) {
            nb.write(raw[i]); i++;
          }
          final num = int.tryParse(nb.toString());
          if (num != null) {
            final code = num < 0 ? num + 65536 : num;
            if (code > 31) currentText.writeCharCode(code);
          }
          // Skip replacement char
          if (i < raw.length && raw[i] != '\\' && raw[i] != '{' && raw[i] != '}') i++;
          continue;
        }

        // Control word
        if (_isAlpha(raw.codeUnitAt(i))) {
          final ws = i;
          while (i < raw.length && _isAlpha(raw.codeUnitAt(i))) i++;
          final word = raw.substring(ws, i);

          // Optional numeric parameter
          String param = '';
          if (i < raw.length && (raw[i] == '-' || (raw.codeUnitAt(i) >= 0x30 && raw.codeUnitAt(i) <= 0x39))) {
            final ps = i;
            if (raw[i] == '-') i++;
            while (i < raw.length && raw.codeUnitAt(i) >= 0x30 && raw.codeUnitAt(i) <= 0x39) i++;
            param = raw.substring(ps, i);
          }
          if (i < raw.length && raw[i] == ' ') i++;

          // Handle formatting
          switch (word) {
            case 'b':
              final newBold = param != '0';
              if (newBold != bold) { flushRun(); bold = newBold; }
              break;
            case 'fs':
              if (detectedFontSize == null) {
                final halfPoints = double.tryParse(param);
                if (halfPoints != null && halfPoints > 0) detectedFontSize = halfPoints / 2.0;
              }
              break;
            case 'cf':
              final newCf = int.tryParse(param) ?? 0;
              if (newCf != cfIndex) { flushRun(); cfIndex = newCf; }
              break;
            case 'par':
            case 'line':
              flushRun();
              currentText.write('\n');
              flushRun();
              break;
            case 'plain':
              flushRun();
              bold = false; cfIndex = 0;
              break;
          }
          continue;
        }

        i++; // Skip unknown control symbol
        continue;
      }

      // Regular text character (skip bare CR/LF — RTF uses \par)
      if (c != '\r' && c != '\n') {
        currentText.write(c);
      }
      i++;
    }
    flushRun();

    // ── Step 3: Convert runs to internal markup ──
    final buf = StringBuffer();
    for (final run in runs) {
      String text = run.text;
      if (text.isEmpty) continue;

      // Don't wrap newlines in style tags
      if (text == '\n') { buf.write('\n'); continue; }

      if (run.cfIndex > 0 && run.cfIndex < colorTable.length) {
        text = '[color=#${colorTable[run.cfIndex]}]$text[/color]';
      }
      if (run.bold) {
        text = '**$text**';
      }
      buf.write(text);
    }

    String result = buf.toString();
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return _ParsedFile(result.trim(), fontSize: detectedFontSize);
  }

  static bool _isAlpha(int codeUnit) =>
      (codeUnit >= 0x41 && codeUnit <= 0x5A) || (codeUnit >= 0x61 && codeUnit <= 0x7A);

  /// Maps Windows-1252 bytes 0x80-0x9F to their Unicode equivalents.
  static int _win1252ToUnicode(int code) {
    const map = {
      0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
      0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
      0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
      0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
      0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
      0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
      0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    };
    return map[code] ?? code;
  }

  void clear() {
    state = null;
    ref.read(settingsProvider.notifier).saveScript('', title: '');
  }
}

final scriptProvider = NotifierProvider<ScriptNotifier, Script?>(ScriptNotifier.new);

extension ScriptUtils on Script {
  Script copyWith({
    String? title, 
    String? rawText, 
    List<ScriptWord>? words, 
    bool? isRtl, 
    String? sourceType, 
    String? sessionId,
    String? historyJson,
  }) {
    return Script(
      id: id,
      title: title ?? this.title,
      rawText: rawText ?? this.rawText,
      words: words ?? this.words,
      isRtl: isRtl ?? this.isRtl,
      sourceType: sourceType ?? this.sourceType,
      sessionId: sessionId ?? this.sessionId,
      historyJson: historyJson ?? this.historyJson,
    );
  }
}

class _ParsedFile {
  final String text;
  final double? fontSize;
  _ParsedFile(this.text, {this.fontSize});
}

class _RtfRun {
  final String text;
  final bool bold;
  final int cfIndex;
  _RtfRun(this.text, this.bold, this.cfIndex);
}
