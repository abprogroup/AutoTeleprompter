import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic color tokens for the AutoTeleprompter dark studio UI.
abstract final class AppColors {
  static const Color amber = Color(0xFFFFBF00);
  static const Color canvas = Color(0xFF0A0A0A);
  static const Color surfaceSheet = Color(0xFF101010);
  static const Color surfaceElevated = Color(0xFF181818);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textMuted = Colors.white54;
  static const Color textSubtle = Colors.white38;
  static const Color danger = Colors.redAccent;
  static const Color warning = Colors.orangeAccent;
  static const Color success = Colors.greenAccent;
}

/// Shared dark studio theme and accessibility scaling helpers.
abstract final class AppTheme {
  static const double minUiScale = 0.90;
  static const double maxUiScale = 1.25;

  static double clampUiScale(double scale) {
    if (!scale.isFinite) return 1.0;
    return scale.clamp(minUiScale, maxUiScale).toDouble();
  }

  /// Keep global ThemeData strictly aligned with the verified baseline theme.
  /// Do NOT set global `inputDecorationTheme.filled = true` (it paints an
  /// opaque fill over the editor's custom selection, highlight, and underline
  /// CustomPaint layer) or global button/snackbar overrides that alter wired
  /// editor suites.
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.amber,
        surface: AppColors.surface,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    );
  }
}
