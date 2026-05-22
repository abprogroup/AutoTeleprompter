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

part 'script_provider.import_parsers.dart';
part 'script_provider.models.dart';

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
    String? historyJson;
    double? fontSize, lineSpacing, letterSpacing, wordSpacing;
    String? fontFamily, textAlign;
    int? scriptBgColor, currentWordColor, futureWordColor;

    for (final json in settings.recentScripts) {
      try {
        final meta = jsonDecode(json);
        if (meta['fullText'] == lastText ||
            meta['sessionId'] == sessionId ||
            meta['title'] == lastTitle) {
          sourceType = meta['type'] ?? 'TEMP';
          sessionId = meta['sessionId'];
          final metaIdx = meta['historyIndex'];
          if (metaIdx != null) historyIndex = metaIdx;
          final metaHistJson = meta['historyJson'];
          if (metaHistJson is String) historyJson = metaHistJson;

          // v3.9.5.70: Extract styling metadata (Nested for Gallery Compatibility)
          final style = meta['style'] as Map<String, dynamic>?;
          if (style != null) {
            if (style['fontSize'] != null)
              fontSize = (style['fontSize'] as num).toDouble();
            if (style['fontFamily'] != null) fontFamily = style['fontFamily'];
            if (style['lineSpacing'] != null)
              lineSpacing = (style['lineSpacing'] as num).toDouble();
            if (style['letterSpacing'] != null)
              letterSpacing = (style['letterSpacing'] as num).toDouble();
            if (style['wordSpacing'] != null)
              wordSpacing = (style['wordSpacing'] as num).toDouble();
            if (style['textAlign'] != null) textAlign = style['textAlign'];
            if (style['scriptBgColor'] != null)
              scriptBgColor = style['scriptBgColor'];
            if (style['currentWordColor'] != null)
              currentWordColor = style['currentWordColor'];
            if (style['futureWordColor'] != null)
              futureWordColor = style['futureWordColor'];
          }

          break;
        }
      } catch (_) {}
    }

    if (lastText.isNotEmpty) {
      return _buildScript(
        lastText,
        title: lastTitle.isNotEmpty ? lastTitle : null,
        sourceType: sourceType,
        sessionId: sessionId,
        historyIndex: historyIndex ?? settings.lastHistoryIndex,
        historyJson: historyJson,
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

  Script _buildScript(
    String text, {
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
      title: title ??
          (text.split('\n').first.trim().isNotEmpty
              ? text.split('\n').first.trim().substring(
                  0, text.split('\n').first.trim().length.clamp(0, 40))
              : 'Script'),
      rawText: text,
      words: words,
      isRtl: isRtl,
      sourceType: sourceType ?? 'TEMP',
      sessionId: sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      historyJson: historyJson,
      historyIndex: historyIndex ?? -1,
      fontSize: fontSize ?? settings.fontSize,
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

  void loadText(
    String text, {
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
    state = _buildScript(
      text,
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

  Future<void> updateStyleMetadata({
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
  }) async {
    final current = state;
    if (current == null) return;
    final next = current.copyWith(
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
    state = next;
    await ref.read(settingsProvider.notifier).saveScript(
          next.rawText,
          title: next.title,
          type: next.sourceType,
          historyIndex: next.historyIndex,
          sessionId: next.sessionId,
          fontSize: next.fontSize,
          fontFamily: next.fontFamily,
          lineSpacing: next.lineSpacing,
          letterSpacing: next.letterSpacing,
          wordSpacing: next.wordSpacing,
          textAlign: next.textAlign,
          scriptBgColor: next.scriptBgColor,
          currentWordColor: next.currentWordColor,
          futureWordColor: next.futureWordColor,
          historyJson: next.historyJson,
        );
  }

  Future<_ParsedFile> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    _ParsedFile result = _ParsedFile('');

    try {
      if (lower.endsWith('.pages') && await Directory(file.path).exists()) {
        result = await _parsePagesPackage(Directory(file.path));
      } else {
        final rawBytes = await file.readAsBytes();
        if (lower.endsWith('.docx')) {
          result = _parseDocx(rawBytes);
        } else if (lower.endsWith('.pages')) {
          result = _parsePages(rawBytes);
        } else if (lower.endsWith('.rtf') || lower.endsWith('.doc')) {
          final raw = utf8.decode(rawBytes, allowMalformed: true);
          if (raw.trimLeft().startsWith('{\\rtf')) {
            result = _parseRtf(raw);
          } else if (lower.endsWith('.rtf')) {
            // Non-RTF content in a .rtf file (e.g. saved before the fix) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â treat as UTF-8
            result = _ParsedFile(raw.trim());
          } else {
            // Legacy .doc binary files ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â strip non-printable bytes
            final content = String.fromCharCodes(
              rawBytes.where(
                  (b) => (b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D),
            ).replaceAll(RegExp(r'[ \t]{3,}'), '  ').trim();
            result = _ParsedFile(content);
          }
        } else {
          result = _ParsedFile(utf8.decode(rawBytes, allowMalformed: true));
        }
      }
    } catch (e) {
      final errStr = e.toString();
      String errContent = '';
      if (errStr.contains('Central Directory') || errStr.contains('Format')) {
        errContent =
            'This file appears to be corrupted or is not a valid ${file.path.split('.').last.toUpperCase()} file.';
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
      final extension =
          title.contains('.') ? title.split('.').last.toUpperCase() : 'FILE';
      loadText(result.text,
          title: title, sourceType: extension, fontSize: result.fontSize);
    }
  }

  _ParsedFile _parseDocx(List<int> rawBytes) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    double? detectedFontSize;

    // Find document.xml ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â try common paths
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

    // Get bytes safely ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â archive 3.x content can be List<int> or InputStream
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
    final parsedParagraphs = <String>[];
    final numbering = _DocxNumberingResolver.fromArchive(archive);

    for (final p in paragraphs) {
      final paragraph = StringBuffer();
      final segments = <_DocxRunSegment>[];
      final paragraphAlign = _docxParagraphAlign(p);
      final paragraphRunDefaults = _docxParagraphRunDefaults(p);

      for (final r in p.findAllElements('w:r')) {
        final rPr = r.getElement('w:rPr');
        final text = _docxRunText(r);
        if (text.isEmpty) continue;

        bool isBold = paragraphRunDefaults.isBold;
        bool isItalic = paragraphRunDefaults.isItalic;
        bool isUnderline = paragraphRunDefaults.isUnderline;
        String? color = paragraphRunDefaults.color;
        String? highlightColor = paragraphRunDefaults.highlightColor;

        if (rPr != null) {
          final bold = rPr.getElement('w:b');
          if (bold != null) {
            isBold = _docxBoolOn(bold);
          }
          final italic = rPr.getElement('w:i');
          if (italic != null) {
            isItalic = _docxBoolOn(italic);
          }
          final underline = rPr.getElement('w:u');
          if (underline != null) {
            isUnderline = _docxUnderlineOn(underline);
          }
          final colorElement = rPr.getElement('w:color');
          if (colorElement != null) {
            color = _docxAttr(colorElement, 'val');
          }
          if (_docxRunHasHighlightProperty(rPr)) {
            highlightColor = _docxRunHighlightColor(rPr);
          }

          if (detectedFontSize == null) {
            final sizeElement = rPr.getElement('w:sz');
            final complexSizeElement = rPr.getElement('w:szCs');
            final sz =
                (sizeElement == null ? null : _docxAttr(sizeElement, 'val')) ??
                    (complexSizeElement == null
                        ? null
                        : _docxAttr(complexSizeElement, 'val'));
            if (sz != null) {
              final halfPoints = double.tryParse(sz);
              if (halfPoints != null) detectedFontSize = halfPoints / 2.0;
            }
          }
        }

        if (_docxIsDecorationWhitespace(text)) {
          isUnderline = false;
          highlightColor = null;
        }

        _addDocxRunSegment(
            segments,
            _DocxRunSegment(
              text,
              isBold: isBold,
              isItalic: isItalic,
              isUnderline: isUnderline,
              color: _docxNormalizeTextColor(color),
              highlightColor: _docxNormalizeColor(highlightColor),
            ));
      }

      _mergeDocxNeutralPunctuationSegments(segments);
      final numberingPrefix = numbering.prefixForParagraph(p);
      if (numberingPrefix != null) {
        segments.insert(
          0,
          _DocxRunSegment(
            '$numberingPrefix ',
            isBold: paragraphRunDefaults.isBold,
            isItalic: paragraphRunDefaults.isItalic,
            isUnderline: paragraphRunDefaults.isUnderline,
            color: paragraphRunDefaults.color,
            highlightColor: paragraphRunDefaults.highlightColor,
          ),
        );
      }
      for (final segment in segments) {
        paragraph.write(_docxWrapRun(
          segment.text,
          isBold: segment.isBold,
          isItalic: segment.isItalic,
          isUnderline: segment.isUnderline,
          color: segment.color,
          highlightColor: segment.highlightColor,
        ));
      }

      parsedParagraphs.add(_docxWrapParagraph(
        paragraph.toString(),
        paragraphAlign,
      ));
    }

    // Background color detection
    try {
      final background = document.rootElement.getElement('w:background');
      final bgColorVal =
          background == null ? null : _docxAttr(background, 'color');
      if (bgColorVal != null && bgColorVal != 'auto') {
        final colorInt = int.parse('FF$bgColorVal', radix: 16);
        ref.read(settingsProvider.notifier).setScriptBgColor(colorInt);
      } else if (paragraphs.isNotEmpty) {
        final shading =
            paragraphs.first.getElement('w:pPr')?.getElement('w:shd');
        final shd = shading == null ? null : _docxAttr(shading, 'fill');
        if (shd != null && shd != 'auto' && shd != 'clear') {
          final colorInt = int.parse('FF$shd', radix: 16);
          ref.read(settingsProvider.notifier).setScriptBgColor(colorInt);
        }
      }
    } catch (_) {}

    return _ParsedFile(
      _normalizeImportedDocxText(parsedParagraphs.join('\n')),
      fontSize: detectedFontSize,
    );
  }

  static void _addDocxRunSegment(
      List<_DocxRunSegment> segments, _DocxRunSegment next) {
    if (next.text.isEmpty) return;
    if (segments.isNotEmpty && segments.last.sameStyle(next)) {
      final previous = segments.removeLast();
      segments.add(previous.copyWith(text: previous.text + next.text));
      return;
    }
    segments.add(next);
  }

  static void _mergeDocxNeutralPunctuationSegments(
      List<_DocxRunSegment> segments) {
    var i = 0;
    while (i < segments.length) {
      final segment = segments[i];
      if (_docxIsStandaloneOpeningNeutral(segment.text) &&
          i + 1 < segments.length) {
        final next = segments[i + 1];
        segments[i + 1] = next.copyWith(text: segment.text + next.text);
        segments.removeAt(i);
        continue;
      }
      if (_docxIsStandaloneClosingNeutral(segment.text) && i > 0) {
        final previous = segments[i - 1];
        segments[i - 1] = previous.copyWith(text: previous.text + segment.text);
        segments.removeAt(i);
        continue;
      }
      i++;
    }
  }

  static bool _docxIsDecorationWhitespace(String text) =>
      text.isNotEmpty && text.trim().isEmpty;

  static bool _docxIsStandaloneOpeningNeutral(String text) {
    if (text.contains('\n')) return false;
    final trimmed = text.trim();
    return trimmed.isNotEmpty && RegExp(r'^[\[\(\{]+$').hasMatch(trimmed);
  }

  static bool _docxIsStandaloneClosingNeutral(String text) {
    if (text.contains('\n')) return false;
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[\]\)\}\.,:;!?]+$').hasMatch(trimmed);
  }

  static String _docxRunText(XmlElement run) {
    final buf = StringBuffer();
    for (final child in run.children.whereType<XmlElement>()) {
      final name = child.name.qualified;
      switch (name) {
        case 'w:t':
          buf.write(child.innerText);
          break;
        case 'w:tab':
          buf.write('\t');
          break;
        case 'w:br':
        case 'w:cr':
          buf.write('\n');
          break;
      }
    }
    return buf.toString();
  }

  static String _docxWrapRun(
    String text, {
    required bool isBold,
    required bool isItalic,
    required bool isUnderline,
    required String? color,
    required String? highlightColor,
  }) {
    if (text.isEmpty) return '';
    return text.split('\n').map((line) {
      if (line.isEmpty) return '';
      var wrapped = line;
      final normalizedColor = _docxNormalizeTextColor(color);
      if (normalizedColor != null) {
        wrapped = '[color=#$normalizedColor]$wrapped[/color]';
      }
      final normalizedHighlight = _docxNormalizeColor(highlightColor);
      if (normalizedHighlight != null) {
        wrapped = '[bg=#$normalizedHighlight]$wrapped[/bg]';
      }
      if (isUnderline) wrapped = '[u]$wrapped[/u]';
      if (isItalic) wrapped = '[i]$wrapped[/i]';
      if (isBold) wrapped = '**$wrapped**';
      return wrapped;
    }).join('\n');
  }

  static String? _docxRunHighlightColor(XmlElement runProperties) {
    final shading = runProperties.getElement('w:shd');
    final shadingFill = shading == null ? null : _docxAttr(shading, 'fill');
    final normalizedShading = _docxNormalizeColor(shadingFill);
    if (normalizedShading != null) return normalizedShading;

    final highlightElement = runProperties.getElement('w:highlight');
    final highlight =
        highlightElement == null ? null : _docxAttr(highlightElement, 'val');
    if (highlight == null || highlight == 'none') return null;
    return _docxHighlightNameToHex(highlight);
  }

  static _DocxRunStyle _docxParagraphRunDefaults(XmlElement paragraph) {
    final rPr = paragraph.getElement('w:pPr')?.getElement('w:rPr');
    if (rPr == null) return const _DocxRunStyle();
    final bold = rPr.getElement('w:b');
    final italic = rPr.getElement('w:i');
    final underline = rPr.getElement('w:u');
    final color = rPr.getElement('w:color');
    return _DocxRunStyle(
      isBold: bold != null && _docxBoolOn(bold),
      isItalic: italic != null && _docxBoolOn(italic),
      isUnderline: underline != null && _docxUnderlineOn(underline),
      color: color == null
          ? null
          : _docxNormalizeTextColor(_docxAttr(color, 'val')),
      highlightColor: _docxRunHasHighlightProperty(rPr)
          ? _docxNormalizeColor(_docxRunHighlightColor(rPr))
          : null,
    );
  }

  static bool _docxRunHasHighlightProperty(XmlElement runProperties) =>
      runProperties.getElement('w:shd') != null ||
      runProperties.getElement('w:highlight') != null;

  static bool _docxBoolOn(XmlElement element) {
    final val = _docxAttr(element, 'val');
    return val != '0' && val != 'false' && val != 'off';
  }

  static bool _docxUnderlineOn(XmlElement element) {
    final val = _docxAttr(element, 'val');
    return val != 'none' && val != '0' && val != 'false' && val != 'off';
  }

  static String? _docxNormalizeTextColor(String? color) {
    final normalized = _docxNormalizeColor(color);
    if (normalized == null) return null;

    // Word often serializes normal black document text as near-black colors
    // such as #252525. On the teleprompter's black background those become
    // nearly invisible, so treat very dark DOCX text colors as "default text".
    final red = int.parse(normalized.substring(0, 2), radix: 16);
    final green = int.parse(normalized.substring(2, 4), radix: 16);
    final blue = int.parse(normalized.substring(4, 6), radix: 16);
    if (red < 80 && green < 80 && blue < 80) return null;
    return normalized;
  }

  static String? _docxNormalizeColor(String? color) {
    if (color == null || color == 'auto') return null;
    final hex = color.trim().replaceFirst('#', '').toUpperCase();
    return RegExp(r'^[0-9A-F]{6}$').hasMatch(hex) ? hex : null;
  }

  static const String _docxNamespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  static String? _docxAttr(XmlElement element, String name) =>
      element.getAttribute('w:$name') ??
      element.getAttribute(name) ??
      element.getAttribute(name, namespace: _docxNamespace);

  static String? _docxHighlightNameToHex(String name) {
    switch (name) {
      case 'black':
        return '000000';
      case 'blue':
        return '0000FF';
      case 'cyan':
        return '00FFFF';
      case 'green':
        return '00FF00';
      case 'magenta':
        return 'FF00FF';
      case 'red':
        return 'FF0000';
      case 'yellow':
        return 'FFFF00';
      case 'white':
        return 'FFFFFF';
      case 'darkBlue':
        return '000080';
      case 'darkCyan':
        return '008080';
      case 'darkGreen':
        return '008000';
      case 'darkMagenta':
        return '800080';
      case 'darkRed':
        return '800000';
      case 'darkYellow':
        return '808000';
      case 'darkGray':
        return '808080';
      case 'lightGray':
        return 'C0C0C0';
      default:
        return _docxNormalizeColor(name);
    }
  }

  static String _docxWrapParagraph(String paragraph, String? align) {
    if (align == null || paragraph.isEmpty) return paragraph;
    return paragraph.split('\n').map((line) {
      if (line.isEmpty) return '';
      return '[align=$align]$line[/align=$align]';
    }).join('\n');
  }

  static String? _docxParagraphAlign(XmlElement paragraph) {
    final pPr = paragraph.getElement('w:pPr');
    if (pPr == null) return null;

    final alignment = pPr.getElement('w:jc');
    final jc = alignment == null ? null : _docxAttr(alignment, 'val');
    if (jc == 'center' || jc == 'left' || jc == 'right') return jc;

    // Word often stores Hebrew/RTL paragraph direction with w:bidi instead of
    // an explicit right alignment. Preserve that as app-level right alignment.
    if (pPr.getElement('w:bidi') != null) return 'right';
    return null;
  }

  static String _normalizeImportedDocxText(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();

  /// Keeps scriptProvider.state in sync with the editor's live history so
  /// that a new ScriptEditorScreen (created on re-entry) reads the correct
  /// historyIndex and historyJson from scriptProvider instead of stale startup
  /// values.  Called from _forceRecentUpdate() after each save.
  void updateHistory(int historyIndex, String historyJson) {
    if (state == null) return;
    state = state!.copyWith(
      historyIndex: historyIndex,
      historyJson: historyJson,
    );
  }

  void clear() {
    state = null;
    ref.read(settingsProvider.notifier).saveScript('', title: '');
  }
}

final scriptProvider =
    NotifierProvider<ScriptNotifier, Script?>(ScriptNotifier.new);

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
