import 'dart:math' as math;

import '../../settings/models/app_settings.dart';

/// Visual movement toward an already-authorized target, once per 16ms tick.
/// Never chooses words, changes recognition policy, or extends that target.
class PresenterScrollMotion {
  static double step(
    double remainingDistance, {
    double smoothness = AppSettings.defaultSpeechScrollSmoothness,
    double speed = AppSettings.defaultSpeechScrollSpeed,
  }) {
    if (!remainingDistance.isFinite) return 0.0;
    final distance = remainingDistance.abs();
    if (distance < 0.2) return remainingDistance;

    final easing = AppSettings.normalizeSpeechScrollSmoothness(smoothness);
    final speedLimit = AppSettings.normalizeSpeechScrollSpeed(speed);
    // Default 50% / 1x preserves the existing 0.035 easing and 7px cap.
    // More smoothing softens the approach. Speed is only a ceiling: raising
    // it must not accelerate small movements that are already below the cap.
    final response = 0.035 * math.pow(4.0, 1.0 - 2.0 * easing);
    final magnitude =
        (distance * response)
            .clamp(0.25, 7.0 * speedLimit)
            .clamp(0.0, distance)
            .toDouble();
    // Even the minimum step may not overshoot a nearly reached target.
    return remainingDistance.isNegative ? -magnitude : magnitude;
  }
}
