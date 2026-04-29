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

  WrapAlignment _parseWrapAlignment(String align, bool isRtl) {
    if (isRtl) {
      switch (align) {
        case 'right':
          return WrapAlignment.start;
        case 'left':
          return WrapAlignment.end;
        default:
          return WrapAlignment.center;
      }
    }
    switch (align) {
      case 'left':
        return WrapAlignment.start;
      case 'right':
        return WrapAlignment.end;
      default:
        return WrapAlignment.center;
    }
  }
}
