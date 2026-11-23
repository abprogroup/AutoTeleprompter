/// Encodes and parses AutoTeleprompter appearance color metadata inside
/// exported RTF and DOCX documents without affecting external editors.
class DocumentColorMetadata {
  const DocumentColorMetadata({
    this.scriptBgColor,
    this.futureWordColor,
    this.currentWordColor,
    this.hasAppMetadata = false,
  });

  final int? scriptBgColor;
  final int? futureWordColor;
  final int? currentWordColor;
  final bool hasAppMetadata;

  bool get isEmpty =>
      scriptBgColor == null &&
      futureWordColor == null &&
      currentWordColor == null;

  static final RegExp _rtfAppMetaRe = RegExp(
    r'\{\\\*\\atpmeta\s+([^}]+)\}',
    caseSensitive: false,
  );

  static final RegExp _docxAppMetaRe = RegExp(
    r'<!--\s*atpmeta:([^>]+?)\s*-->',
    caseSensitive: false,
  );

  static final RegExp _rtfBgFillColorRe = RegExp(
    r'\{\\\*\\background\b[\s\S]*?\{\\sn\s+fillColor\}\s*\{\\sv\s+(-?\d+)\}',
    caseSensitive: false,
  );

  static String? encodePayload({
    int? scriptBgColor,
    int? futureWordColor,
    int? currentWordColor,
  }) {
    final parts = <String>[];
    if (scriptBgColor != null) parts.add('bg=${_rgbHex(scriptBgColor)}');
    if (futureWordColor != null) parts.add('fg=${_rgbHex(futureWordColor)}');
    if (currentWordColor != null) parts.add('cur=${_rgbHex(currentWordColor)}');
    return parts.isEmpty ? null : parts.join(';');
  }

  /// Standard RTF 1.9 ignorable destination (`{\*\...}`), ignored by Word,
  /// WordPad, LibreOffice, and TextEdit.
  static String encodeRtf({
    int? scriptBgColor,
    int? futureWordColor,
    int? currentWordColor,
  }) {
    final payload = encodePayload(
      scriptBgColor: scriptBgColor,
      futureWordColor: futureWordColor,
      currentWordColor: currentWordColor,
    );
    return payload == null ? '' : '{\\*\\atpmeta $payload}\n';
  }

  /// Standard XML comment inside `word/document.xml`, ignored by external
  /// DOCX processors.
  static String encodeDocx({
    int? scriptBgColor,
    int? futureWordColor,
    int? currentWordColor,
  }) {
    final payload = encodePayload(
      scriptBgColor: scriptBgColor,
      futureWordColor: futureWordColor,
      currentWordColor: currentWordColor,
    );
    return payload == null ? '' : '<!--atpmeta:$payload-->';
  }

  static DocumentColorMetadata parseRtf(String raw) {
    final appMatch = _rtfAppMetaRe.firstMatch(raw);
    if (appMatch != null) {
      return _parsePayload(appMatch.group(1) ?? '');
    }
    final bgMatch = _rtfBgFillColorRe.firstMatch(raw);
    if (bgMatch != null) {
      final bgr = int.tryParse(bgMatch.group(1) ?? '');
      if (bgr != null) {
        final r = bgr & 0xFF;
        final g = (bgr >> 8) & 0xFF;
        final b = (bgr >> 16) & 0xFF;
        final argb = 0xFF000000 | (r << 16) | (g << 8) | b;
        return DocumentColorMetadata(scriptBgColor: argb);
      }
    }
    return const DocumentColorMetadata();
  }

  static DocumentColorMetadata parseDocx(String xml) {
    final appMatch = _docxAppMetaRe.firstMatch(xml);
    if (appMatch == null) return const DocumentColorMetadata();
    return _parsePayload(appMatch.group(1) ?? '');
  }

  /// Returns true when [argb] is visually dark, so default text on top of it
  /// should be white rather than black.
  static bool isDarkRgb(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    return luminance < 0.5;
  }

  static DocumentColorMetadata _parsePayload(String payload) {
    int? bg;
    int? fg;
    int? cur;
    for (final rawPair in payload.split(';')) {
      final pair = rawPair.trim();
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq).trim().toLowerCase();
      final val = _parseHexColor(pair.substring(eq + 1));
      if (val == null) continue;
      switch (key) {
        case 'bg':
          bg = val;
          break;
        case 'fg':
          fg = val;
          break;
        case 'cur':
          cur = val;
          break;
      }
    }
    return DocumentColorMetadata(
      scriptBgColor: bg,
      futureWordColor: fg,
      currentWordColor: cur,
      hasAppMetadata: bg != null || fg != null || cur != null,
    );
  }

  static String _rgbHex(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static int? _parseHexColor(String raw) {
    final clean = raw.trim().replaceFirst('#', '').toUpperCase();
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) {
      return int.tryParse('FF$clean', radix: 16);
    }
    if (RegExp(r'^[0-9A-F]{8}$').hasMatch(clean)) {
      return int.tryParse(clean, radix: 16);
    }
    return null;
  }
}
