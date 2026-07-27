part of 'settings_provider.dart';

String _normalizeSttEngine(String? engine) {
  return AppSettings.normalizeSttEngine(engine);
}

String _normalizeLanguageMode(String? mode) {
  return AppSettings.normalizeLanguageMode(mode);
}

String _normalizeSttReliabilityMode(String? mode) {
  return AppSettings.normalizeSttReliabilityMode(mode);
}

String _normalizeScrollMode(String? mode) {
  switch (mode) {
    case 'auto':
    case 'manual':
      return mode!;
    default:
      return 'auto';
  }
}

String _normalizeTextAlign(String? align) {
  switch (align) {
    case 'left':
    case 'center':
    case 'right':
      return align!;
    default:
      return 'center';
  }
}

double _normalizeScrollLead(double? value) {
  return (value ?? 0.32).clamp(0.15, 0.60).toDouble();
}

double _normalizeScrollSpeed(double? value) {
  return (value ?? 100.0).clamp(-300.0, 300.0).toDouble();
}

double _normalizeLineSpacing(double? value) {
  return (value ?? 1.2).clamp(0.5, 3.0).toDouble();
}

double _normalizeWordSpacing(double? value) {
  return (value ?? 0.0).clamp(-5.0, 20.0).toDouble();
}

double _normalizeLetterSpacing(double? value) {
  return (value ?? 0.0).clamp(-2.0, 5.0).toDouble();
}

double _normalizePastWordOpacity(double? value) {
  return (value ?? 0.3).clamp(0.05, 1.0).toDouble();
}

int _normalizeColor(int? value, int fallback) {
  if (value == null || value < 0 || value > 0xFFFFFFFF) return fallback;
  return value;
}

String _normalizeLocalPath(String? value) {
  return (value ?? '').replaceAll(RegExp(r'[\r\n]'), '').trim();
}

int _normalizeFlipRotation(int? value) {
  switch (value) {
    case 0:
    case 90:
    case 180:
    case 270:
      return value!;
    default:
      return 0;
  }
}

String _normalizeVideoResolution(String? value) {
  switch (value) {
    case '480p':
    case '720p':
    case '1080p':
      return value!;
    default:
      return '720p';
  }
}

String _normalizeContentCreatorCameraSource(String? value) {
  switch (value) {
    case AppSettings.contentCreatorSourceNative:
    case AppSettings.contentCreatorSourceUsb:
    case AppSettings.contentCreatorSourceVirtual:
    case AppSettings.contentCreatorSourceAll:
      return value!;
    default:
      return AppSettings.contentCreatorSourceNative;
  }
}

String _normalizeContentCreatorLayout(String? value) {
  switch (value) {
    case AppSettings.contentCreatorLayoutReading:
    case AppSettings.contentCreatorLayoutBalanced:
    case AppSettings.contentCreatorLayoutCamera:
      return value!;
    default:
      return AppSettings.contentCreatorLayoutReading;
  }
}

String _normalizeContentCreatorFeedMode(String? value) {
  switch (value) {
    case AppSettings.contentCreatorFeedBubble:
    case AppSettings.contentCreatorFeedFull:
      return value!;
    default:
      return AppSettings.contentCreatorFeedBubble;
  }
}

String _normalizeContentCreatorBubblePosition(String? value) {
  switch (value) {
    case AppSettings.contentCreatorBubbleBottomRight:
    case AppSettings.contentCreatorBubbleBottomLeft:
    case AppSettings.contentCreatorBubbleTopRight:
    case AppSettings.contentCreatorBubbleTopLeft:
      return value!;
    default:
      return AppSettings.contentCreatorBubbleBottomRight;
  }
}

String _normalizeContentCreatorBubbleShape(String? value) {
  switch (value) {
    case AppSettings.contentCreatorBubbleShapeRectangle:
    case AppSettings.contentCreatorBubbleShapeRounded:
    case AppSettings.contentCreatorBubbleShapeCircle:
    case AppSettings.contentCreatorBubbleShapeTriangle:
      return value!;
    default:
      return AppSettings.contentCreatorBubbleShapeRounded;
  }
}

String _normalizeContentCreatorRecordingFormat(String? value) {
  switch (value) {
    case AppSettings.contentCreatorRecordingFormatMp4:
    case AppSettings.contentCreatorRecordingFormatWav:
      return value!;
    default:
      return AppSettings.contentCreatorRecordingFormatMp4;
  }
}

String _normalizeContentCreatorRecordingAudioMode(String? value) {
  switch (value) {
    case AppSettings.contentCreatorRecordingAudioCamera:
      return value!;
    case AppSettings.contentCreatorRecordingAudioSilent:
      return AppSettings.contentCreatorRecordingAudioCamera;
    default:
      return AppSettings.contentCreatorRecordingAudioCamera;
  }
}

String _normalizeManualScrollBarPlacement(String? value) {
  switch (value) {
    case AppSettings.manualScrollBarBottom:
    case AppSettings.manualScrollBarTop:
    case AppSettings.manualScrollBarLeft:
    case AppSettings.manualScrollBarRight:
      return value!;
    default:
      return AppSettings.manualScrollBarBottom;
  }
}

String _normalizeImportColorMode(String? value) {
  switch (value) {
    case AppSettings.importColorModePrompter:
    case AppSettings.importColorModeDocument:
      return value!;
    default:
      return AppSettings.importColorModePrompter;
  }
}

double _normalizeUiScale(double? value) {
  return (value ?? 1.0).clamp(0.90, 1.25).toDouble();
}

String _normalizeUpdateChannel(String? value, {bool allowInternal = false}) {
  switch (value) {
    case AppSettings.updateChannelStable:
    case AppSettings.updateChannelBeta:
      return value!;
    case AppSettings.updateChannelInternal:
      return allowInternal
          ? AppSettings.updateChannelInternal
          : AppSettings.updateChannelStable;
    default:
      return AppSettings.updateChannelStable;
  }
}
