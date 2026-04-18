import 'dart:convert';

/// Generates minimal but valid RTF files from the app's internal markup.
///
/// Output is compatible with [ScriptProvider._parseRtf] so files can
/// round-trip: save as RTF → import RTF → same text + formatting.
///
/// Handles: plain text, Unicode (Hebrew/Arabic), bold (**...**),
/// custom hex colors ([color=#HEX]...[/color]), and named color shorthands
/// ([yc], [rc], [gc], [bc], [oc], [pc], [cc], [pkc]).
class RtfService {
  RtfService._();

  // Shorthand color tags → hex values (must match word_aligner.dart)
  static const _shorthands = <String, String>{
    'yc':  'FFD700',
    'rc':  'FF4444',
    'gc':  '44DD44',
    'bc':  '4488FF',
    'oc':  'FFA500',
    'pc':  'AA44FF',
    'cc':  '44DDDD',
    'pkc': 'FF44AA',
  };

  /// Converts internal-markup text to RTF bytes.
  static List<int> generate(String text) {
    // ── Pass 1: collect unique colors needed for the color table ──────────
    final colorTable = <String>[]; // hex strings, 1-indexed in RTF

    void _addHex(String hex) {
      final h = hex.toUpperCase();
      if (!colorTable.contains(h)) colorTable.add(h);
    }

    final hexTagRe = RegExp(r'\[color=#([0-9A-Fa-f]{6})\]');
    for (final m in hexTagRe.allMatches(text)) {
      _addHex(m.group(1)!);
    }
    for (final entry in _shorthands.entries) {
      if (text.contains('[${entry.key}]')) _addHex(entry.value);
    }

    // ── Build RTF document ─────────────────────────────────────────────────
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

    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        buf.write('\\par\n');
        continue;
      }
      buf.write('\\pard ');
      _writeLine(line, colorTable, buf);
      buf.write('\\par\n');
    }

    buf.write('}');
    return utf8.encode(buf.toString());
  }

  static void _writeLine(String line, List<String> colorTable, StringBuffer buf) {
    // Strip alignment / direction wrapper tags (not needed for round-trip)
    final stripped = line.replaceAll(
      RegExp(r'\[\/?(center|left|right|rtl|ltr|align=[^\]]+)\]'), '');

    int i = 0;
    final len = stripped.length;

    while (i < len) {
      // ── Bold ──────────────────────────────────────────────────────────
      if (stripped.startsWith('**', i)) {
        // We don't track bold state — just emit \b … \b0 pairs from the
        // parser's perspective: every ** toggles bold, so opening = \b ,
        // closing = \b0 . Use a simple odd/even scan to decide which.
        buf.write('{\\b ');
        i += 2;
        // Find matching **
        final close = stripped.indexOf('**', i);
        if (close != -1) {
          _writeChars(stripped.substring(i, close), buf);
          buf.write('}');
          i = close + 2;
        } else {
          // No closing ** — write rest as bold
          _writeChars(stripped.substring(i), buf);
          buf.write('}');
          i = len;
        }
        continue;
      }

      // ── [color=#HEX] ─────────────────────────────────────────────────
      final hexM = RegExp(r'^\[color=#([0-9A-Fa-f]{6})\]')
          .firstMatch(stripped.substring(i));
      if (hexM != null) {
        final hex = hexM.group(1)!.toUpperCase();
        final cfIdx = colorTable.indexOf(hex) + 1;
        buf.write('{\\cf$cfIdx ');
        i += hexM.group(0)!.length;
        final close = stripped.indexOf('[/color]', i);
        if (close != -1) {
          _writeChars(stripped.substring(i, close), buf);
          buf.write('}');
          i = close + 8;
        } else {
          _writeChars(stripped.substring(i), buf);
          buf.write('}');
          i = len;
        }
        continue;
      }

      // ── Named color shorthands [yc], [rc], etc. ───────────────────────
      bool matched = false;
      for (final entry in _shorthands.entries) {
        final openTag  = '[${entry.key}]';
        final closeTag = '[/${entry.key}]';
        if (stripped.startsWith(openTag, i)) {
          final hex = entry.value.toUpperCase();
          final cfIdx = colorTable.indexOf(hex) + 1;
          buf.write('{\\cf$cfIdx ');
          i += openTag.length;
          final close = stripped.indexOf(closeTag, i);
          if (close != -1) {
            _writeChars(stripped.substring(i, close), buf);
            buf.write('}');
            i = close + closeTag.length;
          } else {
            _writeChars(stripped.substring(i), buf);
            buf.write('}');
            i = len;
          }
          matched = true;
          break;
        }
      }
      if (matched) continue;

      // ── Skip any other unrecognised [tag] ─────────────────────────────
      if (stripped[i] == '[') {
        final close = stripped.indexOf(']', i);
        if (close != -1) { i = close + 1; continue; }
      }

      // ── Regular character ─────────────────────────────────────────────
      _writeChar(stripped.codeUnitAt(i), buf);
      i++;
    }
  }

  static void _writeChars(String s, StringBuffer buf) {
    for (int i = 0; i < s.length; i++) {
      _writeChar(s.codeUnitAt(i), buf);
    }
  }

  static void _writeChar(int ch, StringBuffer buf) {
    if (ch == 0x7B)      buf.write(r'\{');
    else if (ch == 0x7D) buf.write(r'\}');
    else if (ch == 0x5C) buf.write(r'\\');
    else if (ch < 128)   buf.writeCharCode(ch);
    else {
      // Non-ASCII (Hebrew, Arabic, accented chars…) → RTF Unicode escape
      // RTF uses signed 16-bit; values > 32767 become negative
      final code = ch > 32767 ? ch - 65536 : ch;
      buf.write('\\u$code?');
    }
  }
}
