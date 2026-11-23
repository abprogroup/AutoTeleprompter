import 'package:autoteleprompter/features/script/services/script_bookmark_service.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/presenter_horizontal_margins.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/presenter_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PresenterHorizontalMargins', () {
    test('defaults preserve exact 5% symmetric horizontal padding', () {
      final margins = PresenterHorizontalMargins.resolve(
        viewportWidth: 1000,
        sideMargin: 0.0,
        horizontalOffset: 0.0,
      );
      expect(margins.left, closeTo(50.0, 0.01));
      expect(margins.right, closeTo(50.0, 0.01));
    });

    test('side margin narrows column symmetrically for centered camera gaze', () {
      final margins = PresenterHorizontalMargins.resolve(
        viewportWidth: 1000,
        sideMargin: 0.20,
        horizontalOffset: 0.0,
      );
      expect(margins.left, closeTo(250.0, 0.01));
      expect(margins.right, closeTo(250.0, 0.01));
      expect(1000 - margins.left - margins.right, closeTo(500.0, 0.01));
    });

    test('left/right offset shifts column without shrinking width', () {
      final shiftedRight = PresenterHorizontalMargins.resolve(
        viewportWidth: 1000,
        sideMargin: 0.20,
        horizontalOffset: 0.10,
      );
      expect(shiftedRight.left, closeTo(350.0, 0.01));
      expect(shiftedRight.right, closeTo(150.0, 0.01));
      expect(1000 - shiftedRight.left - shiftedRight.right, closeTo(500.0, 0.01));

      final shiftedLeft = PresenterHorizontalMargins.resolve(
        viewportWidth: 1000,
        sideMargin: 0.20,
        horizontalOffset: -0.10,
      );
      expect(shiftedLeft.left, closeTo(150.0, 0.01));
      expect(shiftedLeft.right, closeTo(350.0, 0.01));
      expect(1000 - shiftedLeft.left - shiftedLeft.right, closeTo(500.0, 0.01));
    });

    test('extreme margin + offset always keeps >= 20% column and >= 2% edges', () {
      for (final margin in [-1.0, 0.0, 0.20, 0.35, 1.0, double.nan]) {
        for (final offset in [-1.0, -0.30, 0.0, 0.30, 1.0, double.infinity]) {
          final margins = PresenterHorizontalMargins.resolve(
            viewportWidth: 1000,
            sideMargin: margin,
            horizontalOffset: offset,
          );
          expect(margins.left, greaterThanOrEqualTo(20.0 - 0.01));
          expect(margins.right, greaterThanOrEqualTo(20.0 - 0.01));
          expect(
            1000 - margins.left - margins.right,
            greaterThanOrEqualTo(200.0 - 0.01),
          );
        }
      }
    });

    test('formats horizontal offset labels clearly', () {
      expect(PresenterHorizontalMargins.formatHorizontalOffsetLabel(0.0), 'Center');
      expect(
        PresenterHorizontalMargins.formatHorizontalOffsetLabel(-0.12),
        'Left 12%',
      );
      expect(
        PresenterHorizontalMargins.formatHorizontalOffsetLabel(0.15),
        'Right 15%',
      );
    });
  });

  group('SettingsNotifier side margins & offset persistence', () {
    test('persists and clamps presenterSideMargin and presenterHorizontalOffset', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      // Let initial async _load() settle before mutating settings.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await notifier.setPresenterSideMargin(0.22);
      await notifier.setPresenterHorizontalOffset(-0.14);

      final updated = container.read(settingsProvider);
      expect(updated.presenterSideMargin, closeTo(0.22, 0.0001));
      expect(updated.presenterHorizontalOffset, closeTo(-0.14, 0.0001));

      // Clamping checks
      await notifier.setPresenterSideMargin(0.99);
      await notifier.setPresenterHorizontalOffset(0.99);
      expect(container.read(settingsProvider).presenterSideMargin, closeTo(0.35, 0.0001));
      expect(container.read(settingsProvider).presenterHorizontalOffset, closeTo(0.30, 0.0001));

      // Verify persistence in SharedPreferences and reload into fresh notifier
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('presenterSideMargin'), closeTo(0.35, 0.0001));
      expect(prefs.getDouble('presenterHorizontalOffset'), closeTo(0.30, 0.0001));

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      reloaded.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reloaded.read(settingsProvider).presenterSideMargin, closeTo(0.35, 0.0001));
      expect(reloaded.read(settingsProvider).presenterHorizontalOffset, closeTo(0.30, 0.0001));
    });
  });

  group('Presenter remove bookmark resolution', () {
    test('removes bookmark in same paragraph or at scrolled reading line, not unrelated paragraphs', () {
      final words = WordAligner.tokenize(
        'First paragraph words here\n'
        'Second bookmarked heading line\n'
        'Third unrelated paragraph',
      );
      final firstParaStart = words.indexWhere((w) => w.raw == 'First');
      final secondParaStart = words.indexWhere((w) => w.raw == 'Second');
      final secondParaLast = words.indexWhere((w) => w.raw == 'line');
      final thirdParaWord = words.indexWhere((w) => w.raw == 'Third');

      final bookmarks = [
        ScriptBookmark(
          id: 'b0',
          label: 'First paragraph',
          wordIndex: firstParaStart,
          blockIndex: 0,
          offset: 0,
          createdAt: DateTime(2026),
        ),
        ScriptBookmark(
          id: 'b1',
          label: 'Second bookmarked heading',
          wordIndex: secondParaStart,
          blockIndex: 1,
          offset: 0,
          createdAt: DateTime(2026),
        ),
      ];

      // 1. Mid-paragraph cursor still resolves the paragraph's bookmark.
      expect(
        ScriptBookmarkService.resolvePresenterBookmarkForRemoval(
          words: words,
          bookmarks: bookmarks,
          currentWordIndex: secondParaLast,
        ),
        secondParaStart,
      );

      // 2. Scrolled reading line on the bookmarked paragraph removes THAT
      // visible bookmark even when off-screen word 0 also has a bookmark!
      expect(
        ScriptBookmarkService.resolvePresenterBookmarkForRemoval(
          words: words,
          bookmarks: bookmarks,
          currentWordIndex: firstParaStart,
          readingLineWordIndex: secondParaLast,
        ),
        secondParaStart,
      );

      // 3. Unrelated paragraph returns null so other bookmarks stay safe.
      expect(
        ScriptBookmarkService.resolvePresenterBookmarkForRemoval(
          words: words,
          bookmarks: bookmarks,
          currentWordIndex: thirdParaWord,
          readingLineWordIndex: thirdParaWord,
        ),
        isNull,
      );
    });
  });

  group('Compact presenter notification bar', () {
    testWidgets('renders slim single-line SnackBar <= 28px tall', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    buildCompactPresenterSnackBar(
                      'Bookmark: 2. Long Hebrew heading line that should stay one slim row',
                    ),
                  );
                },
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      final snackSize = tester.getSize(find.byType(SnackBar));
      expect(snackSize.height, lessThanOrEqualTo(28.0));
    });
  });
}
