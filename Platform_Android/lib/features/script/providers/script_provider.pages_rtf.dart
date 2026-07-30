part of 'script_provider.dart';

mixin ScriptNotifierPagesRtfImport on Notifier<Script?> {
  /// Parses Apple Pages files (.pages) — a ZIP archive.
  /// Handles both the old XML-based format (index.xml) and the newer
  /// iWork format by extracting readable text from all XML entries.
  _ParsedFile _parsePages(List<int> rawBytes) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    final buf = StringBuffer();

    // Old Pages format: index.xml contains <sf:p> paragraph elements
    final indexFile = archive.findFile('index.xml');
    if (indexFile != null) {
      final xml =
          utf8.decode(indexFile.content as List<int>, allowMalformed: true);
      // Extract text from <sf:p> and <sf:s> (span) elements
      final paraMatches =
          RegExp(r'<sf:p\b[^>]*>(.*?)</sf:p>', dotAll: true).allMatches(xml);
      for (final m in paraMatches) {
        final inner = m.group(1) ?? '';
        // Strip any nested XML tags to get raw text
        final text = inner.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (text.isNotEmpty) buf.writeln(text);
      }
      if (buf.isNotEmpty) return _ParsedFile(buf.toString().trim());
    }

    // Newer Pages format: scan all XML files in the archive for text content
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.toLowerCase();
      if (!name.endsWith('.xml') && !name.endsWith('.iwa')) continue;
      try {
        final content =
            utf8.decode(file.content as List<int>, allowMalformed: true);
        // Extract anything that looks like readable paragraph text
        final matches =
            RegExp(r'<[^>]*p[^>]*>(.*?)</[^>]*p[^>]*>', dotAll: true)
                .allMatches(content);
        for (final m in matches) {
          final text =
              (m.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
          if (text.length > 2) buf.writeln(text);
        }
      } catch (_) {}
    }

    final result = buf.toString().trim();
    if (result.isEmpty) {
      return _ParsedFile('Could not extract text from this Pages file. '
          'Please open it in Pages and export as DOCX or TXT first.');
    }
    return _ParsedFile(result);
  }

  /// Parses RTF, extracts text with style markup (bold, color, size).
  _ParsedFile _parseRtf(String raw) {
    double? detectedFontSize;
    final codePage = _rtfAnsiCodePage(raw);
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
      // List metadata. Visible list labels live in listtext/pntext groups and
      // must stay readable so numbered paragraphs keep their source labels.
      'listtable', 'listoverridetable', 'pnseclvl',
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

      if (skipDepths.isNotEmpty) {
        i++;
        continue;
      }

      if (c == '\\') {
        i++;
        if (i >= raw.length) break;
        final next = raw[i];

        // Literal escapes
        if (next == '\\') {
          currentText.write('\\');
          i++;
          continue;
        }
        if (next == '{') {
          currentText.write('{');
          i++;
          continue;
        }
        if (next == '}') {
          currentText.write('}');
          i++;
          continue;
        }
        if (next == '\n' || next == '\r') {
          flushRun();
          currentText.write('\n');
          flushRun();
          i++;
          continue;
        }

        // Hex escape \' XX. Decode through the document ANSI code page.
        if (next == '\'') {
          i++;
          if (i + 1 < raw.length) {
            final code = int.tryParse(raw.substring(i, i + 2), radix: 16);
            if (code != null && code > 31) {
              currentText.writeCharCode(_rtfAnsiByteToUnicode(code, codePage));
            }
            i += 2;
          }
          continue;
        }

        // Unicode escape \uNNNN? — only if followed by a digit or minus sign.
        // Control words like \uc, \ul, \ulnone start with 'u' but are NOT unicode escapes.
        if (next == 'u' &&
            (i + 1) < raw.length &&
            (raw.codeUnitAt(i + 1) >= 0x30 && raw.codeUnitAt(i + 1) <= 0x39 ||
                raw[i + 1] == '-')) {
          i++;
          final nb = StringBuffer();
          if (i < raw.length && raw[i] == '-') {
            nb.write('-');
            i++;
          }
          while (i < raw.length &&
              raw.codeUnitAt(i) >= 0x30 &&
              raw.codeUnitAt(i) <= 0x39) {
            nb.write(raw[i]);
            i++;
          }
          final num = int.tryParse(nb.toString());
          if (num != null) {
            final code = num < 0 ? num + 65536 : num;
            if (code > 31) currentText.writeCharCode(code);
          }
          // Skip replacement char
          if (i < raw.length &&
              raw[i] != '\\' &&
              raw[i] != '{' &&
              raw[i] != '}') i++;
          continue;
        }

        // Control word
        if (_isAlpha(raw.codeUnitAt(i))) {
          final ws = i;
          while (i < raw.length && _isAlpha(raw.codeUnitAt(i))) i++;
          final word = raw.substring(ws, i);

          // Optional numeric parameter
          String param = '';
          if (i < raw.length &&
              (raw[i] == '-' ||
                  (raw.codeUnitAt(i) >= 0x30 && raw.codeUnitAt(i) <= 0x39))) {
            final ps = i;
            if (raw[i] == '-') i++;
            while (i < raw.length &&
                raw.codeUnitAt(i) >= 0x30 &&
                raw.codeUnitAt(i) <= 0x39) i++;
            param = raw.substring(ps, i);
          }
          if (i < raw.length && raw[i] == ' ') i++;

          // Handle formatting
          switch (word) {
            case 'b':
              final newBold = param != '0';
              if (newBold != bold) {
                flushRun();
                bold = newBold;
              }
              break;
            case 'fs':
              if (detectedFontSize == null) {
                final halfPoints = double.tryParse(param);
                if (halfPoints != null && halfPoints > 0)
                  detectedFontSize = halfPoints / 2.0;
              }
              break;
            case 'cf':
              final newCf = int.tryParse(param) ?? 0;
              if (newCf != cfIndex) {
                flushRun();
                cfIndex = newCf;
              }
              break;
            case 'par':
            case 'line':
              flushRun();
              currentText.write('\n');
              flushRun();
              break;
            case 'plain':
              flushRun();
              bold = false;
              cfIndex = 0;
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
      if (text == '\n') {
        buf.write('\n');
        continue;
      }

      if (run.cfIndex > 0 && run.cfIndex < colorTable.length) {
        text = '[color=#${colorTable[run.cfIndex]}]$text[/color]';
      }
      if (run.bold) {
        text = '**$text**';
      }
      buf.write(text);
    }

    final result = buf.toString();
    return _ParsedFile(result.trim(), fontSize: detectedFontSize);
  }

  static bool _isAlpha(int codeUnit) =>
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);

  static int _rtfAnsiCodePage(String raw) {
    final match = RegExp(r'\\ansicpg(\d+)').firstMatch(raw);
    return int.tryParse(match?.group(1) ?? '') ?? 1252;
  }

  static int _rtfAnsiByteToUnicode(int code, int codePage) {
    if (code < 0x80) return code;
    return switch (codePage) {
      1255 => _win1255ToUnicode(code),
      _ => _win1252ToUnicode(code),
    };
  }

  /// Maps Windows-1255 Hebrew RTF bytes to Unicode.
  static int _win1255ToUnicode(int code) {
    const map = {
      0x80: 0x20AC,
      0x82: 0x201A,
      0x83: 0x0192,
      0x84: 0x201E,
      0x85: 0x2026,
      0x86: 0x2020,
      0x87: 0x2021,
      0x88: 0x02C6,
      0x89: 0x2030,
      0x8B: 0x2039,
      0x91: 0x2018,
      0x92: 0x2019,
      0x93: 0x201C,
      0x94: 0x201D,
      0x95: 0x2022,
      0x96: 0x2013,
      0x97: 0x2014,
      0x99: 0x2122,
      0x9B: 0x203A,
      0xA4: 0x20AA,
      0xAA: 0x00D7,
      0xBA: 0x00F7,
      0xC0: 0x05B0,
      0xC1: 0x05B1,
      0xC2: 0x05B2,
      0xC3: 0x05B3,
      0xC4: 0x05B4,
      0xC5: 0x05B5,
      0xC6: 0x05B6,
      0xC7: 0x05B7,
      0xC8: 0x05B8,
      0xC9: 0x05B9,
      0xCB: 0x05BB,
      0xCC: 0x05BC,
      0xCD: 0x05BD,
      0xCE: 0x05BE,
      0xCF: 0x05BF,
      0xD0: 0x05C0,
      0xD1: 0x05C1,
      0xD2: 0x05C2,
      0xD3: 0x05C3,
      0xD4: 0x05F0,
      0xD5: 0x05F1,
      0xD6: 0x05F2,
      0xD7: 0x05F3,
      0xD8: 0x05F4,
      0xE0: 0x05D0,
      0xE1: 0x05D1,
      0xE2: 0x05D2,
      0xE3: 0x05D3,
      0xE4: 0x05D4,
      0xE5: 0x05D5,
      0xE6: 0x05D6,
      0xE7: 0x05D7,
      0xE8: 0x05D8,
      0xE9: 0x05D9,
      0xEA: 0x05DA,
      0xEB: 0x05DB,
      0xEC: 0x05DC,
      0xED: 0x05DD,
      0xEE: 0x05DE,
      0xEF: 0x05DF,
      0xF0: 0x05E0,
      0xF1: 0x05E1,
      0xF2: 0x05E2,
      0xF3: 0x05E3,
      0xF4: 0x05E4,
      0xF5: 0x05E5,
      0xF6: 0x05E6,
      0xF7: 0x05E7,
      0xF8: 0x05E8,
      0xF9: 0x05E9,
      0xFA: 0x05EA,
      0xFD: 0x200E,
      0xFE: 0x200F,
    };
    return map[code] ?? _win1252ToUnicode(code);
  }

  /// Maps Windows-1252 bytes 0x80-0x9F to their Unicode equivalents.
  static int _win1252ToUnicode(int code) {
    const map = {
      0x80: 0x20AC,
      0x82: 0x201A,
      0x83: 0x0192,
      0x84: 0x201E,
      0x85: 0x2026,
      0x86: 0x2020,
      0x87: 0x2021,
      0x88: 0x02C6,
      0x89: 0x2030,
      0x8A: 0x0160,
      0x8B: 0x2039,
      0x8C: 0x0152,
      0x8E: 0x017D,
      0x91: 0x2018,
      0x92: 0x2019,
      0x93: 0x201C,
      0x94: 0x201D,
      0x95: 0x2022,
      0x96: 0x2013,
      0x97: 0x2014,
      0x98: 0x02DC,
      0x99: 0x2122,
      0x9A: 0x0161,
      0x9B: 0x203A,
      0x9C: 0x0153,
      0x9E: 0x017E,
      0x9F: 0x0178,
    };
    return map[code] ?? code;
  }
}
