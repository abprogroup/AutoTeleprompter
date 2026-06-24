part of 'teleprompter_screen.dart';

extension _TeleprompterAlignmentHelperParts on _TeleprompterScreenState {
  WrapAlignment _toWrapAlignment(
      TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    final textAlign = _toTextAlign(paraAlign, settings, isRtl);
    if (textAlign == TextAlign.center) return WrapAlignment.center;

    if (isRtl) {
      // In RTL, Start is Right, End is Left.
      if (textAlign == TextAlign.left) return WrapAlignment.end;
      if (textAlign == TextAlign.right) return WrapAlignment.start;
    } else {
      // In LTR, Start is Left, End is Right.
      if (textAlign == TextAlign.left) return WrapAlignment.start;
      if (textAlign == TextAlign.right) return WrapAlignment.end;
    }

    return WrapAlignment.center;
  }

  TextAlign _toTextAlign(
      TextAlign? paraAlign, AppSettings settings, bool isRtl) {
    if (paraAlign != null) return paraAlign;
    // v3.8: Source of Truth - If no tag, Hebrew defaults to Right, English to Left
    return isRtl ? TextAlign.right : TextAlign.left;
  }

  bool _sameHighlightColor(Color? a, Color? b) {
    if (a == null || b == null) return false;
    return a == b;
  }

  TextDirection _wordDirectionForDisplay(
    String text, {
    required TextDirection paragraphDirection,
  }) {
    final clean = _stripBidiIsolation(text);
    if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) return TextDirection.rtl;
    if (RegExp(r'[A-Za-z]').hasMatch(clean)) return TextDirection.ltr;
    return paragraphDirection;
  }

  String _bidiIsolatedDisplayText(
    String text, {
    required TextDirection paragraphDirection,
  }) {
    // Each presenter word is already wrapped in a Directionality widget.
    // Adding Unicode isolates inside every word over-constrains mixed
    // Hebrew/English/neutral punctuation and can flip brackets/numbers.
    return text;
  }

  String _stripBidiIsolation(String text) =>
      text.replaceAll(RegExp('[\u200E\u200F\u2066\u2067\u2068\u2069]'), '');

  bool _paragraphIsRtl(List<ScriptWord> words) {
    var hasLatin = false;
    for (final word in words) {
      final clean = word.raw.replaceAll(_tagStripRe, '').trim();
      if (clean.isEmpty) continue;
      if (RegExp(r'[\u0590-\u08FF]').hasMatch(clean)) return true;
      if (RegExp(r'[A-Za-z]').hasMatch(clean)) hasLatin = true;
    }
    if (hasLatin) return false;
    return words.isNotEmpty && words.first.effectiveRtl;
  }

  double _presenterWordGap(double fontSize, AppSettings settings) {
    final defaultSpace = fontSize * 0.33;
    final editorFontSize =
        settings.fontSize <= 0 ? fontSize : settings.fontSize;
    final presentationScale = (fontSize / editorFontSize).clamp(1.0, 2.5);
    final scaledWordSpacing = settings.wordSpacing * presentationScale;
    final minimumReadableGap = fontSize * 0.18;
    return (defaultSpace + scaledWordSpacing)
        .clamp(minimumReadableGap, 96.0)
        .toDouble();
  }

  double _decorationGapTolerance(double wordGap) {
    final dynamicTolerance = wordGap + 8.0;
    return dynamicTolerance < 18.0 ? 18.0 : dynamicTolerance;
  }
}
