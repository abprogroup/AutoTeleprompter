import 'package:autoteleprompter/features/script/models/editor_state.dart';
import 'package:autoteleprompter/features/script/widgets/editor/components/editor_primitives.dart';
import 'package:autoteleprompter/features/script/widgets/editor/suites/formatting_toolbar_mvp.dart';
import 'package:autoteleprompter/features/script/widgets/editor/suites/project_actions_mvp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor project actions exposes settings shortcut',
      (tester) async {
    var settingsTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectActionsSuite(
            title: 'Draft',
            onBack: () {},
            onPresent: () {},
            onClear: () {},
            onSave: () {},
            onImport: () {},
            onRename: () {},
            onSearch: () {},
            onSettings: () => settingsTapCount++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();

    expect(settingsTapCount, 1);
  });

  testWidgets('bookmark suite keeps previous and next actions open',
      (tester) async {
    var previousTapCount = 0;
    var nextTapCount = 0;
    var activeSuite = EditorSuite.none;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return FormattingToolbarMVP(
                onBold: () {},
                onUnderline: () {},
                onItalic: () {},
                onClear: () {},
                onFontSize: (_) {},
                onAlign: (_) {},
                onDirection: (_) {},
                onTextColor: (_) {},
                onBgColor: (_) {},
                onFontFamily: (_) {},
                onBgColorChange: (_) {},
                onAddBookmark: () {},
                onRemoveBookmark: () {},
                onPreviousBookmark: () => previousTapCount++,
                onNextBookmark: () => nextTapCount++,
                onLockedBookmarks: () {},
                lastTextColor: Colors.white,
                lastHighlightColor: Colors.transparent,
                onUndo: () {},
                onRedo: () {},
                canUndo: false,
                canRedo: false,
                history: const <EditorState>[],
                historyIndex: 0,
                onHistorySelected: (_) {},
                activeSuite: activeSuite,
                onSuiteToggle: (suite) => setState(() {
                  activeSuite = activeSuite == suite ? EditorSuite.none : suite;
                }),
                onLayoutInteraction: (_) {},
                bookmarksEnabled: true,
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next bookmark'));
    await tester.pumpAndSettle();
    expect(nextTapCount, 1);
    expect(find.byTooltip('Next bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Next bookmark'));
    await tester.pumpAndSettle();
    expect(nextTapCount, 2);
    expect(find.byTooltip('Next bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous bookmark'));
    await tester.pumpAndSettle();
    expect(previousTapCount, 1);
    expect(find.byTooltip('Previous bookmark'), findsOneWidget);
  });

  testWidgets('locked bookmark suite calls pro discovery action',
      (tester) async {
    var lockedTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattingToolbarMVP(
            onBold: () {},
            onUnderline: () {},
            onItalic: () {},
            onClear: () {},
            onFontSize: (_) {},
            onAlign: (_) {},
            onDirection: (_) {},
            onTextColor: (_) {},
            onBgColor: (_) {},
            onFontFamily: (_) {},
            onBgColorChange: (_) {},
            onAddBookmark: () {},
            onRemoveBookmark: () {},
            onPreviousBookmark: () {},
            onNextBookmark: () {},
            onLockedBookmarks: () => lockedTapCount++,
            lastTextColor: Colors.white,
            lastHighlightColor: Colors.transparent,
            onUndo: () {},
            onRedo: () {},
            canUndo: false,
            canRedo: false,
            history: const <EditorState>[],
            historyIndex: 0,
            onHistorySelected: (_) {},
            activeSuite: EditorSuite.none,
            onSuiteToggle: (_) {},
            onLayoutInteraction: (_) {},
            bookmarksEnabled: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Bookmarks are included with Pro'));
    await tester.pumpAndSettle();

    expect(lockedTapCount, 1);
    expect(find.byTooltip('Add bookmark'), findsNothing);
  });
}
