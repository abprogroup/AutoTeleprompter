import 'package:autoteleprompter/features/teleprompter/services/presenter_reading_position_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bounded presenter geometry lookup', () {
    test('re-anchors beyond stale padding in a 3000-word script', () {
      const wordCount = 3000;
      const scrollOffset = 72000.0;
      const readingLine = 400.0;
      var geometryLookups = 0;

      PresenterReadingWordBounds boundsAt(int index) {
        geometryLookups++;
        final leading = index * 30.0 - scrollOffset;
        return PresenterReadingWordBounds(
          index: index,
          leading: leading,
          trailing: leading + 8.0,
        );
      }

      final anchor = PresenterReadingPositionService.anchorIndexNearAxis(
        wordCount: wordCount,
        axis: readingLine,
        boundsAt: boundsAt,
      );

      expect(anchor, 2414);
      expect(anchor, greaterThan(140));

      final range = PresenterReadingPositionService.boundedRangeAround(
        wordCount: wordCount,
        anchorIndex: anchor!,
        padding: 140,
      );
      final candidates = <PresenterReadingWordBounds>[
        for (var index = range.start; index < range.end; index++)
          boundsAt(index),
      ];
      final selected = PresenterReadingPositionService.wordIndexAtReadingLine(
        words: candidates,
        readingLine: readingLine,
      );

      expect(selected, 2414);
      expect(range.end - range.start, lessThanOrEqualTo(281));
      expect(geometryLookups, lessThan(310));
    });

    test('refreshes its anchor after a large wheel-scroll position change', () {
      const wordCount = 3000;
      var scrollOffset = 0.0;

      PresenterReadingWordBounds boundsAt(int index) {
        final leading = index * 30.0 - scrollOffset;
        return PresenterReadingWordBounds(
          index: index,
          leading: leading,
          trailing: leading + 8.0,
        );
      }

      final initial = PresenterReadingPositionService.anchorIndexNearAxis(
        wordCount: wordCount,
        axis: 400,
        boundsAt: boundsAt,
      );
      scrollOffset = 54000;
      final afterWheel = PresenterReadingPositionService.anchorIndexNearAxis(
        wordCount: wordCount,
        axis: 400,
        boundsAt: boundsAt,
      );

      expect(initial, 14);
      expect(afterWheel, 1814);
      expect(afterWheel! - initial!, greaterThan(140));
    });

    test('clamps bounded ranges at both script edges', () {
      expect(
        PresenterReadingPositionService.boundedRangeAround(
          wordCount: 3000,
          anchorIndex: 0,
          padding: 140,
        ),
        (start: 0, end: 141),
      );
      expect(
        PresenterReadingPositionService.boundedRangeAround(
          wordCount: 3000,
          anchorIndex: 2999,
          padding: 140,
        ),
        (start: 2859, end: 3000),
      );
    });

    test('keeps lookup work bounded when layout geometry is unavailable', () {
      var geometryLookups = 0;

      final anchor = PresenterReadingPositionService.anchorIndexNearAxis(
        wordCount: 3000,
        axis: 400,
        boundsAt: (_) {
          geometryLookups++;
          return null;
        },
      );

      expect(anchor, isNull);
      expect(geometryLookups, lessThanOrEqualTo(25));
    });
  });
}
