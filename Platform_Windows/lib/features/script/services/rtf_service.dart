import 'dart:convert';

import 'markup_export_service.dart';

/// Generates minimal but valid RTF files from the app's internal markup.
///
/// Exported RTF must never expose bracket markup such as `[color=#ffffff]`.
/// Internal tags are converted into RTF controls, while teleprompter-default
/// white text is treated as display metadata and omitted so documents remain
/// readable on normal white paper.
class RtfService {
  RtfService._();

  /// Converts internal-markup text to RTF bytes.
  static List<int> generate(String text, {bool? defaultRtl}) {
    final paragraphs = MarkupExportService.parse(text, defaultRtl: defaultRtl);
    final colorTable = <String>[];
    final fontTable = <String>['Arial'];

    void addColor(String? hex) {
      if (hex == null || _isDefaultDisplayWhite(hex)) return;
      if (!colorTable.contains(hex)) colorTable.add(hex);
    }

    void addFont(String? font) {
      final clean = _rtfFontName(font);
      if (clean == null || fontTable.contains(clean)) return;
      fontTable.add(clean);
    }

    for (final paragraph in paragraphs) {
      for (final run in paragraph.runs) {
        addColor(run.color);
        addColor(run.backgroundColor);
        addFont(run.fontFamily);
      }
    }

    final buf = StringBuffer();
    final documentRtl = paragraphs.where((p) => p.isRtl).length >=
        paragraphs.where((p) => !p.isRtl).length;
    buf.write('{\\rtf1\\ansi\\ansicpg1255\\deff0');
    if (documentRtl) buf.write(r'\rtldoc\rtlsect');
    buf.write('{\\fonttbl');
    for (var i = 0; i < fontTable.length; i++) {
      buf.write('{\\f$i ${fontTable[i]};}');
    }
    buf.write('}');
    buf.write('\n');

    if (colorTable.isNotEmpty) {
      buf.write('{\\colortbl ;');
      for (final hex in colorTable) {
        final r = int.parse(hex.substring(0, 2), radix: 16);
        final g = int.parse(hex.substring(2, 4), radix: 16);
        final b = int.parse(hex.substring(4, 6), radix: 16);
        buf.write('\\red$r\\green$g\\blue$b;');
      }
      buf.write('}\n');
    }

    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        buf.write('\\par\n');
        continue;
      }
      final direction = paragraph.isRtl ? r'\rtlpar\rtlch' : r'\ltrpar\ltrch';
      buf.write(
        '\\pard ${_rtfAlign(paragraph.align, paragraph)}$direction ',
      );
      for (final directionalRun in MarkupExportService.documentRuns(
        paragraph,
      )) {
        _writeRun(
          directionalRun.run,
          directionalRun.text,
          colorTable,
          fontTable,
          directionalRun.isRtl,
          buf,
        );
      }
      buf.write('\\par\n');
    }

    buf.write('}');
    return utf8.encode(buf.toString());
  }

  static void _writeRun(
    ExportTextRun run,
    String text,
    List<String> colorTable,
    List<String> fontTable,
    bool rtl,
    StringBuffer buf,
  ) {
    if (text.isEmpty) return;
    final controls = <String>[];
    controls.add(rtl ? r'\rtlch' : r'\ltrch');
    final fontName = _rtfFontName(run.fontFamily);
    if (fontName != null) {
      final fontIndex = fontTable.indexOf(fontName);
      if (fontIndex >= 0) controls.add('\\f$fontIndex');
    }
    if (run.isBold) controls.add(r'\b');
    if (run.isItalic) controls.add(r'\i');
    if (run.isUnderline) controls.add(r'\ul');
    controls.add('\\fs${((run.fontSize ?? 18) * 2).round()}');
    if (run.color != null && !_isDefaultDisplayWhite(run.color)) {
      final colorIndex = colorTable.indexOf(run.color!) + 1;
      if (colorIndex > 0) controls.add('\\cf$colorIndex');
    }
    if (run.backgroundColor != null) {
      final highlightIndex = colorTable.indexOf(run.backgroundColor!) + 1;
      if (highlightIndex > 0) controls.add('\\highlight$highlightIndex');
    }

    if (controls.isEmpty) {
      _writeChars(text, buf);
      return;
    }

    buf.write('{${controls.join()} ');
    _writeChars(text, buf);
    buf.write('}');
  }

  static String _rtfAlign(String align, ExportParagraph paragraph) {
    if (paragraph.isRtl && !paragraph.hasExplicitAlign) return r'\qr';
    switch (align) {
      case 'center':
        return r'\qc';
      case 'right':
        return r'\qr';
      default:
        return r'\ql';
    }
  }

  static bool _isDefaultDisplayWhite(String? hex) =>
      hex != null && hex.toUpperCase() == 'FFFFFF';

  static String? _rtfFontName(String? value) {
    final clean = value
        ?.replaceAll(RegExp(r'[{}\\;\r\n\t]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  static void _writeChars(String s, StringBuffer buf) {
    for (int i = 0; i < s.length; i++) {
      _writeChar(s.codeUnitAt(i), buf);
    }
  }

  static void _writeChar(int ch, StringBuffer buf) {
    if (ch == 0x7B) {
      buf.write(r'\{');
    } else if (ch == 0x7D) {
      buf.write(r'\}');
    } else if (ch == 0x5C) {
      buf.write(r'\\');
    } else if (ch < 128) {
      buf.writeCharCode(ch);
    } else {
      final code = ch > 32767 ? ch - 65536 : ch;
      buf.write('\\u$code?');
    }
  }
}
