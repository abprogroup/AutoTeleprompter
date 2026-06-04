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
  static List<int> generate(String text) {
    final paragraphs = MarkupExportService.parse(text);
    final colorTable = <String>[];

    void addColor(String? hex) {
      if (hex == null || _isDefaultDisplayWhite(hex)) return;
      if (!colorTable.contains(hex)) colorTable.add(hex);
    }

    for (final paragraph in paragraphs) {
      for (final run in paragraph.runs) {
        addColor(run.color);
        addColor(run.backgroundColor);
      }
    }

    final buf = StringBuffer();
    buf.write('{\\rtf1\\ansi\\deff0\n');

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
      buf.write('\\pard ${_rtfAlign(paragraph.align)} ');
      for (final run in paragraph.runs) {
        _writeRun(run, colorTable, buf);
      }
      buf.write('\\par\n');
    }

    buf.write('}');
    return utf8.encode(buf.toString());
  }

  static void _writeRun(
    ExportTextRun run,
    List<String> colorTable,
    StringBuffer buf,
  ) {
    if (run.text.isEmpty) return;
    final controls = <String>[];
    if (run.isBold) controls.add(r'\b');
    if (run.isItalic) controls.add(r'\i');
    if (run.isUnderline) controls.add(r'\ul');
    if (run.fontSize != null) {
      controls.add('\\fs${(run.fontSize! * 2).round()}');
    }
    if (run.color != null && !_isDefaultDisplayWhite(run.color)) {
      final colorIndex = colorTable.indexOf(run.color!) + 1;
      if (colorIndex > 0) controls.add('\\cf$colorIndex');
    }
    if (run.backgroundColor != null) {
      final highlightIndex = colorTable.indexOf(run.backgroundColor!) + 1;
      if (highlightIndex > 0) controls.add('\\highlight$highlightIndex');
    }

    if (controls.isEmpty) {
      _writeChars(run.text, buf);
      return;
    }

    buf.write('{${controls.join()} ');
    _writeChars(run.text, buf);
    buf.write('}');
  }

  static String _rtfAlign(String align) {
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
