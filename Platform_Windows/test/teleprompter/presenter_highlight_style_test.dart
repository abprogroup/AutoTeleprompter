import 'dart:ui' as ui;

import 'package:autoteleprompter/features/script/services/highlight_band_painter.dart';
import 'package:autoteleprompter/features/teleprompter/services/presenter_highlight_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'faded connected band has equal pixels under words and in word gaps',
    () async {
      final recording = ui.PictureRecorder();
      final canvas = Canvas(recording);
      const size = Size(120, 60);
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
      const yellow = Color(0xFFFFFF00);
      HighlightBandPainter.paintConnectedRegion(
        canvas,
        [const Rect.fromLTWH(10, 10, 100, 40)],
        yellow.withValues(alpha: 0.15),
        size,
      );
      final wordBackground = PresenterHighlightStyle.wordBackground(
        imported: yellow,
        tracking: null,
        isPast: true,
        customPainterEnabled: true,
      );
      if (wordBackground != null) {
        canvas.drawRect(
          const Rect.fromLTWH(10, 10, 30, 40),
          Paint()..color = wordBackground,
        );
      }
      final picture = recording.endRecording();
      final image = await picture.toImage(120, 60);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int channelAt(int x) => pixels.getUint8((20 * 120 + x) * 4);
      expect(
        channelAt(20),
        channelAt(60),
        reason: 'word backgrounds must not double-paint the band',
      );
      expect(channelAt(20), inInclusiveRange(37, 39));
      image.dispose();
      picture.dispose();
    },
  );
  test(
    'connected highlight has no second per-word paint, including faded words',
    () {
      for (final past in [false, true]) {
        expect(
          PresenterHighlightStyle.wordBackground(
            imported: Colors.yellow,
            tracking: null,
            isPast: past,
            customPainterEnabled: true,
          ),
          isNull,
        );
      }
    },
  );
  test('legacy fallback and reading cursor remain visible', () {
    expect(
      PresenterHighlightStyle.wordBackground(
        imported: Colors.yellow,
        tracking: null,
        isPast: false,
        customPainterEnabled: false,
      ),
      Colors.yellow,
    );
    final cursor = Colors.orange.withValues(alpha: 0.3);
    expect(
      PresenterHighlightStyle.wordBackground(
        imported: Colors.yellow,
        tracking: cursor,
        isPast: false,
        customPainterEnabled: true,
      ),
      cursor,
    );
  });
  test('fallback fade retains imported transparency', () {
    expect(
      PresenterHighlightStyle.wordBackground(
        imported: Colors.yellow.withValues(alpha: 0.5),
        tracking: null,
        isPast: true,
        customPainterEnabled: false,
      )!.a,
      closeTo(0.075, 0.001),
    );
  });
  test('white and yellow text remain readable on yellow imported bands', () {
    for (final color in [Colors.white, Colors.yellow]) {
      expect(
        PresenterHighlightStyle.readableText(
          text: color,
          imported: Colors.yellow,
          tracking: null,
          scriptBackground: Colors.black,
          isPast: false,
        ),
        Colors.black,
      );
    }
  });
  test('legible authored color and unhighlighted text are not changed', () {
    expect(
      PresenterHighlightStyle.readableText(
        text: Colors.blue.shade900,
        imported: Colors.yellow,
        tracking: null,
        scriptBackground: Colors.black,
        isPast: false,
      ),
      Colors.blue.shade900,
    );
    expect(
      PresenterHighlightStyle.readableText(
        text: Colors.white,
        imported: null,
        tracking: Colors.yellow,
        scriptBackground: Colors.black,
        isPast: false,
      ),
      Colors.white,
    );
  });
  test('read-word opacity survives contrast correction and theme changes', () {
    final faded = Colors.white.withValues(alpha: 0.3);
    expect(
      PresenterHighlightStyle.readableText(
        text: faded,
        imported: Colors.yellow,
        tracking: null,
        scriptBackground: Colors.white,
        isPast: true,
      ),
      Colors.black.withValues(alpha: 0.3),
    );
    expect(
      PresenterHighlightStyle.readableText(
        text: faded,
        imported: Colors.yellow,
        tracking: null,
        scriptBackground: Colors.black,
        isPast: true,
      ),
      faded,
    );
  });
}
