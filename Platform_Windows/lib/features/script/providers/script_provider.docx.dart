part of 'script_provider.dart';

extension _ScriptProviderDocxParsing on ScriptNotifier {
  ParsedFile _parseDocx(List<int> rawBytes) {
    final archive = _decodeCheckedArchive(rawBytes, 'DOCX');

    // Find document.xml through common paths.
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

    // Get bytes safely; archive 3.x content can be List<int> or InputStream.
    final bytes = _archiveFileBytes(docEntry, format: 'DOCX', isXml: true);

    final xmlStr = utf8.decode(bytes, allowMalformed: true);
    final document = XmlDocument.parse(xmlStr);
    final paragraphs = document.findAllElements('w:p').toList();
    final numbering = _docxNumberingFromArchive(archive);
    final styles = _docxStylesFromArchive(archive);
    final parsedParagraphs = <String>[];
    double? uniformDocumentFontSize;
    var uniformDocumentFontSizeValid = true;
    var sawVisibleDocumentText = false;

    void recordFontSize(double? size) {
      sawVisibleDocumentText = true;
      if (size == null) {
        uniformDocumentFontSizeValid = false;
      } else if (uniformDocumentFontSize == null) {
        uniformDocumentFontSize = size;
      } else if ((uniformDocumentFontSize! - size).abs() > 0.001) {
        uniformDocumentFontSizeValid = false;
      }
    }

    for (final p in paragraphs) {
      final paragraph = StringBuffer();
      final segments = <_DocxRunSegment>[];
      final paragraphProperties = styles.paragraphProperties(p);
      final paragraphAlign = _docxParagraphAlign(paragraphProperties);
      final bidi = paragraphProperties.getElement('w:bidi');
      final paragraphRtl = bidi == null ? null : _docxBoolOn(bidi);

      for (final r in p.findAllElements('w:r')) {
        final rPr = styles.runProperties(p, r);
        final text = _docxRunText(r);
        if (text.isEmpty) continue;
        final complex = RegExp(r'[\u0590-\u08FF]').hasMatch(text) &&
            !RegExp(r'[A-Za-z]').hasMatch(text);
        final bold = (complex ? rPr.getElement('w:bCs') : null) ??
            rPr.getElement('w:b');
        final italic = (complex ? rPr.getElement('w:iCs') : null) ??
            rPr.getElement('w:i');
        final underline = rPr.getElement('w:u');
        final isBold = bold != null && _docxBoolOn(bold);
        final isItalic = italic != null && _docxBoolOn(italic);
        var isUnderline = underline != null && _docxUnderlineOn(underline);
        final colorElement = rPr.getElement('w:color');
        final color = colorElement == null ? null : _docxAttr(colorElement, 'val');
        var highlightColor = _docxRunHighlightColor(rPr);
        final runFontSize = _docxRunFontSize(rPr, complex: complex);
        final runFontFamily = _docxRunFontFamily(rPr, complex: complex);
        if (text.trim().isNotEmpty) {
          recordFontSize(runFontSize);
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
              fontSize: runFontSize,
              fontFamily: runFontFamily,
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
          fontSize: segment.fontSize,
          fontFamily: segment.fontFamily,
        ));
      }

      var paragraphText = paragraph.toString();
      final listLabel = numbering.labelForParagraph(p);
      if (listLabel != null && paragraphText.trim().isNotEmpty) {
        final labelProperties = styles.numberingRunProperties(
          p,
          listLabel.runProperties,
        );
        final complex = ['cs', 'rtl'].any((name) {
              final property = labelProperties.getElement('w:$name');
              return property != null && _docxBoolOn(property);
            }) ||
            RegExp(r'[\u0590-\u08FF]').hasMatch(listLabel.text);
        final labelFontSize = _docxRunFontSize(
          labelProperties,
          complex: complex,
        );
        recordFontSize(labelFontSize);
        final styledLabel = _docxWrapRun(
          '${listLabel.text} ',
          // This repair adds label typography only. Do not copy text-run
          // highlight/underline onto the generated number or its following run.
          isBold: false,
          isItalic: false,
          isUnderline: false,
          color: null,
          highlightColor: null,
          fontSize: labelFontSize,
          fontFamily: _docxRunFontFamily(labelProperties, complex: complex),
        );
        paragraphText = '$styledLabel$paragraphText';
      }

      parsedParagraphs.add(_docxWrapParagraph(
        paragraphText,
        paragraphAlign,
        rtl: paragraphRtl,
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
    } catch (e, stack) {
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'import.docxBackground',
      );
    }

    final baseFontSize = sawVisibleDocumentText &&
            uniformDocumentFontSizeValid &&
            uniformDocumentFontSize != null
        ? uniformDocumentFontSize
        : null;
    final importedText =
        _normalizeImportedDocxText(parsedParagraphs.join('\n'));
    // Inline metadata must survive both file-open paths. The editor can ignore
    // baseFontSize, so stripping uniform tags makes imports preference-dependent.
    return ParsedFile(importedText, fontSize: baseFontSize);
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
    required double? fontSize,
    required String? fontFamily,
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
      if (fontSize != null) {
        wrapped = '[size=${_docxFormatFontSize(fontSize)}]$wrapped[/size]';
      }
      final normalizedFont = _docxNormalizeFontFamily(fontFamily);
      if (normalizedFont != null) {
        wrapped = '[font=$normalizedFont]$wrapped[/font]';
      }
      if (isUnderline) wrapped = '[u]$wrapped[/u]';
      if (isItalic) wrapped = '[i]$wrapped[/i]';
      if (isBold) wrapped = '**$wrapped**';
      return wrapped;
    }).join('\n');
  }

  static String? _docxRunHighlightColor(XmlElement runProperties) {
    final highlightElement = runProperties.getElement('w:highlight');
    final highlight =
        highlightElement == null ? null : _docxAttr(highlightElement, 'val');
    if (highlight != null && highlight != 'none') {
      final color = _docxHighlightNameToHex(highlight);
      if (color != null) return color;
    }
    // Word highlight takes precedence over run shading. Explicit highlight
    // 'none' clears highlight only; a separate shading fill can still apply.
    final shading = runProperties.getElement('w:shd');
    final shadingFill = shading == null ? null : _docxAttr(shading, 'fill');
    return _docxNormalizeColor(shadingFill);
  }

  static double? _docxRunFontSize(XmlElement runProperties, {bool complex = false}) {
    final sizeElement = (complex ? runProperties.getElement('w:szCs') : null) ??
        runProperties.getElement('w:sz');
    final complexSizeElement = runProperties.getElement('w:szCs');
    final sz = (sizeElement == null ? null : _docxAttr(sizeElement, 'val')) ??
        (complexSizeElement == null
            ? null
            : _docxAttr(complexSizeElement, 'val'));
    final halfPoints = sz == null ? null : double.tryParse(sz);
    if (halfPoints == null || !halfPoints.isFinite || halfPoints <= 0) return null;
    return halfPoints / 2.0;
  }

  static String? _docxRunFontFamily(XmlElement runProperties, {bool complex = false}) {
    final fonts = runProperties.getElement('w:rFonts');
    if (fonts == null) return null;
    return _docxNormalizeFontFamily(
      (complex ? _docxAttr(fonts, 'cs') : null) ??
          _docxAttr(fonts, 'ascii') ??
          _docxAttr(fonts, 'hAnsi') ??
          _docxAttr(fonts, 'cs') ??
          _docxAttr(fonts, 'eastAsia'),
    );
  }

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

  static String _docxFormatFontSize(double size) {
    if ((size - size.roundToDouble()).abs() < 0.001) {
      return size.round().toString();
    }
    return size.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String? _docxNormalizeFontFamily(String? family) {
    final trimmed = family?.trim().replaceAll(']', '');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

  static String _docxWrapParagraph(String paragraph, String? align, {bool? rtl}) {
    if (paragraph.isEmpty) return paragraph;
    return paragraph.split('\n').map((line) {
      if (line.isEmpty) return '';
      var wrapped = align == null ? line : '[align=$align]$line[/align=$align]';
      if (rtl != null) {
        final direction = rtl ? 'rtl' : 'ltr';
        wrapped = '[$direction]$wrapped[/$direction]';
      }
      return wrapped;
    }).join('\n');
  }

  static String? _docxParagraphAlign(XmlElement pPr) {
    final alignment = pPr.getElement('w:jc');
    final jc = alignment == null ? null : _docxAttr(alignment, 'val');
    if (jc == 'center' || jc == 'left' || jc == 'right') return jc;

    // Word often stores Hebrew/RTL paragraph direction with w:bidi instead of
    // an explicit right alignment. Preserve that as app-level right alignment.
    final bidi = pPr.getElement('w:bidi');
    if (bidi != null && _docxBoolOn(bidi)) return 'right';
    return null;
  }

  static String _normalizeImportedDocxText(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();

  _DocxNumberingResolver _docxNumberingFromArchive(Archive archive) {
    final entry = archive.findFile('word/numbering.xml') ??
        archive.findFile('word/Numbering.xml');
    if (entry == null) return _DocxNumberingResolver.empty();
    try {
      return _DocxNumberingResolver.fromXmlBytes(
        _archiveFileBytes(entry, format: 'DOCX', isXml: true),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'import.docxNumbering',
      );
      return _DocxNumberingResolver.empty();
    }
  }

  /// Parses Apple Pages files (.pages) as a ZIP archive.
  /// Handles both the old XML-based format (index.xml) and the newer
  /// iWork format by extracting readable text from all XML entries.
}
