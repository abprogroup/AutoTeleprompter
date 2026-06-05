part of 'local_backup_service.dart';

String _applyExportDefaults(
  String text, {
  double? fontSize,
  String? fontFamily,
  String? textAlign,
  int? futureWordColor,
  bool? isRtl,
}) {
  if (text.trim().isEmpty) return text;
  final resolvedRtl = isRtl ?? _looksRtl(text);
  final resolvedAlign =
      _normalizeTextAlign(textAlign) ?? (resolvedRtl ? 'right' : null);
  final resolvedColor = _metadataTextColor(futureWordColor);
  final resolvedFont = _safeFontFamily(fontFamily);
  final resolvedSize =
      fontSize != null && fontSize > 0 ? fontSize.toStringAsFixed(1) : null;

  final addDirection = resolvedRtl && !_hasDirectionMarkup(text);
  final addAlign = resolvedAlign != null && !_hasAlignMarkup(text);
  final addColor = resolvedColor != null &&
      !_isDefaultReadableTextColor(resolvedColor) &&
      !_hasColorMarkup(text);
  final addFont = resolvedFont != null && !_hasFontMarkup(text);
  final addSize = resolvedSize != null && !_hasSizeMarkup(text);

  if (!addDirection && !addAlign && !addColor && !addFont && !addSize) {
    return text;
  }

  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').map(
    (line) {
      if (line.trim().isEmpty) return line;
      var out = line;
      if (addColor) out = '[color=#$resolvedColor]$out[/color]';
      if (addSize) out = '[size=$resolvedSize]$out[/size]';
      if (addFont) out = '[font=$resolvedFont]$out[/font]';
      if (addAlign) out = '[align=$resolvedAlign]$out[/align=$resolvedAlign]';
      if (addDirection) out = '[rtl]$out[/rtl]';
      return out;
    },
  ).join('\n');
}

bool _hasDirectionMarkup(String text) =>
    RegExp(r'\[(?:rtl|ltr)\]', caseSensitive: false).hasMatch(text);

bool _hasAlignMarkup(String text) => RegExp(
      r'\[(?:align=(?:left|right|center)|left|right|center)\]',
      caseSensitive: false,
    ).hasMatch(text);

bool _hasColorMarkup(String text) =>
    RegExp(r'\[(?:color=|yc|rc|gc|bc|oc|pc|cc|pkc)\b', caseSensitive: false)
        .hasMatch(text);

bool _hasFontMarkup(String text) =>
    RegExp(r'\[font=', caseSensitive: false).hasMatch(text);

bool _hasSizeMarkup(String text) =>
    RegExp(r'\[size=', caseSensitive: false).hasMatch(text);

String? _normalizeTextAlign(String? value) {
  final align = value?.trim().toLowerCase();
  if (align == 'left' || align == 'right' || align == 'center') {
    return align;
  }
  return null;
}

String? _metadataTextColor(int? color) {
  if (color == null) return null;
  return (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
}

bool _isDefaultReadableTextColor(String hex) {
  final normalized = hex.toUpperCase();
  return normalized == 'FFFFFF' || normalized == '000000';
}

String? _safeFontFamily(String? value) {
  final font = value?.trim();
  if (font == null || font.isEmpty) return null;
  if (font.contains('[') || font.contains(']') || font.contains('\n')) {
    return null;
  }
  return font;
}

bool _looksRtl(String text) {
  var rtl = 0;
  var ltr = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x05FF) ||
        (rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0x0750 && rune <= 0x077F)) {
      rtl++;
    } else if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A)) {
      ltr++;
    }
  }
  return rtl > 0 && rtl >= ltr;
}
