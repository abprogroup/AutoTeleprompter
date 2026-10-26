import 'package:autoteleprompter/features/teleprompter/services/presenter_scroll_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults reproduce the existing 16ms easing and speed cap', () {
    for (final distance in [
      -1000.0,
      -200.0,
      -100.0,
      -1.0,
      1.0,
      100.0,
      200.0,
      1000.0,
    ]) {
      var legacy = (distance * 0.035).clamp(-7.0, 7.0);
      if (legacy.abs() < 0.25) legacy = distance.isNegative ? -0.25 : 0.25;
      expect(PresenterScrollMotion.step(distance), closeTo(legacy, 1e-12));
    }
  });

  test('more smoothing softens the approach without changing the target', () {
    final responsive = PresenterScrollMotion.step(40, smoothness: 0);
    final normal = PresenterScrollMotion.step(40, smoothness: 0.5);
    final smooth = PresenterScrollMotion.step(40, smoothness: 1);
    expect(responsive, greaterThan(normal));
    expect(normal, greaterThan(smooth));
    expect(smooth, greaterThan(0));
  });

  test('speed is only a ceiling; sub-limit easing is unchanged', () {
    for (final distance in [4.0, 40.0]) {
      final normal = PresenterScrollMotion.step(distance);
      expect(
        PresenterScrollMotion.step(distance, speed: 0.5),
        closeTo(normal, 1e-12),
      );
      expect(
        PresenterScrollMotion.step(distance, speed: 2),
        closeTo(normal, 1e-12),
      );
    }
    expect(PresenterScrollMotion.step(1000, speed: 0.5), 3.5);
    expect(PresenterScrollMotion.step(1000, speed: 1), 7);
    expect(PresenterScrollMotion.step(1000, speed: 2), 14);
  });

  test('all slider combinations converge without overshoot or oscillation', () {
    for (final smoothness in [0.0, 0.5, 1.0]) {
      for (final speed in [0.25, 1.0, 2.0]) {
        for (final target in [-1000.0, -0.21, 0.0, 0.21, 1000.0]) {
          var current = 0.0;
          for (var tick = 0; tick < 10000 && current != target; tick++) {
            final distance = target - current;
            final step = PresenterScrollMotion.step(
              distance,
              smoothness: smoothness,
              speed: speed,
            );
            expect(step.abs(), lessThanOrEqualTo(distance.abs()));
            expect(step.abs(), lessThanOrEqualTo(7 * speed));
            expect(step.sign, distance.sign);
            current += step;
          }
          expect(current, target);
        }
      }
    }
  });

  test(
    'a new target or live setting change does not preserve stale velocity',
    () {
      var current = PresenterScrollMotion.step(100);
      final distance =
          2 - current; // New target is now behind the current offset.
      current += PresenterScrollMotion.step(distance, smoothness: 1, speed: 2);
      expect(current, inInclusiveRange(2, 3.5));
      expect(PresenterScrollMotion.step(0, smoothness: 0, speed: 2), 0);
    },
  );

  test(
    'invalid tuning values fall back; non-finite geometry cannot scroll',
    () {
      expect(
        PresenterScrollMotion.step(
          100,
          smoothness: double.nan,
          speed: double.infinity,
        ),
        closeTo(3.5, 1e-12),
      );
      expect(PresenterScrollMotion.step(double.nan), 0);
      expect(PresenterScrollMotion.step(double.infinity), 0);
    },
  );

  test('no word evidence or elapsed silence can create another target', () {
    var current = 0.0;
    const authorizedTarget = 120.0;
    for (var i = 0; i < 1200; i++) {
      current += PresenterScrollMotion.step(
        authorizedTarget - current,
        speed: 2,
      );
      expect(current, lessThanOrEqualTo(authorizedTarget));
    }
    expect(current, authorizedTarget);
  });
}
