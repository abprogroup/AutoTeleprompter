part of 'script_provider.dart';

extension _ScriptProviderDocxParsing on ScriptNotifier {
  _ParsedFile _parseDocx(List<int> rawBytes) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    double? detectedFontSize;

    // Find document.xml â€” try common paths
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

    // Get bytes safely â€” archive 3.x content can be List<int> or InputStream
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

  /// Parses Apple Pages files (.pages) â€” a ZIP archive.
  /// Handles both the old XML-based format (index.xml) and the newer
  /// iWork format by extracting readable text from all XML entries.
}
