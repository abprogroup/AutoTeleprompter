import 'package:flutter/material.dart';

import '../models/script_word.dart';
import '../../settings/models/app_settings.dart';

class ScriptColorInversionService {
  const ScriptColorInversionService._();

  static bool highlightsMoveToText(AppSettings settings) {
    return settings.showUpcomingWordColor &&
        Color(settings.scriptBgColor).computeLuminance() > 0.5;
  }

  static int nextBackgroundColor(AppSettings settings) {
    final isDark = Color(settings.scriptBgColor).computeLuminance() < 0.5;
    return isDark ? 0xFFFFFFFF : 0xFF000000;
  }

  static int futureTextColorForBackground(int backgroundColor) {
    final isDark = Color(backgroundColor).computeLuminance() < 0.5;
    return isDark ? 0xFFFFFFFF : 0xFF000000;
  }

  static Color presenterTextColor({
    required ScriptWord word,
    required AppSettings settings,
    required Color fallback,
  }) {
    final highlight = word.highlight;
    if (highlight != null && highlightsMoveToText(settings)) {
      return highlight.withValues(alpha: fallback.a);
    }
    return fallback;
  }
}
