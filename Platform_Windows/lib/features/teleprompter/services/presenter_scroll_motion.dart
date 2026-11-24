import 'dart:math' as math;

import '../../settings/models/app_settings.dart';

/// Visual movement toward an already-authorized target, synchronized to
/// display VSync via [deltaSeconds] (defaults to 60 fps = 1/60 s).
/// Never chooses words, changes recognition policy, or extends that target.
class PresenterScrollMotion {
  static const double _referenceFps = 60.0;

  static double step(
    double remainingDistance, {
    double smoothness = AppSettings.defaultSpeechScrollSmoothness,
    double speed = AppSettings.defaultSpeechScrollSpeed,
    double deltaSeconds = 1.0 / _referenceFps,
  }) {
    if (!remainingDistance.isFinite) return 0.0;
    final distance = remainingDistance.abs();
    if (distance < 0.2) return remainingDistance;

    final easing = AppSettings.normalizeSpeechScrollSmoothness(smoothness);
    final speedLimit = AppSettings.normalizeSpeechScrollSpeed(speed);
    final safeDt =
        deltaSeconds.isFinite && deltaSeconds > 0
            ? deltaSeconds.clamp(1.0 / 300.0, 1.0 / 15.0)
            : 1.0 / _referenceFps;
    final frameScale = safeDt * _referenceFps;

    // Default 50% / 1x at 60 fps preserves the exact 0.035 easing and 7px cap.
    // At higher refresh rates (120/144/240 Hz), exponential damping scales
    // smoothly with frame delta so visual velocity stays identical and fluid.
    final baseResponse = (0.035 * math.pow(4.0, 1.0 - 2.0 * easing))
        .clamp(0.001, 0.95)
        .toDouble();
    final response =
        (frameScale - 1.0).abs() < 1e-6
            ? baseResponse
            : 1.0 - math.pow(1.0 - baseResponse, frameScale).toDouble();
    final minStep = 0.25 * frameScale;
    final maxStep = 7.0 * speedLimit * frameScale;
    final magnitude =
        (distance * response)
            .clamp(minStep, maxStep)
            .clamp(0.0, distance)
            .toDouble();
    // Even the minimum step may not overshoot a nearly reached target.
    return remainingDistance.isNegative ? -magnitude : magnitude;
  }
}
