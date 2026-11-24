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

  double _presenterWordGap(double fontSize, AppSettings settings) {
    return ScriptTypographyService.presenterWordGap(
      fontSize,
      settings.wordSpacing,
    );
  }

  double _decorationGapTolerance(double wordGap) {
    final dynamicTolerance = wordGap + 8.0;
    return dynamicTolerance < 18.0 ? 18.0 : dynamicTolerance;
  }
}
