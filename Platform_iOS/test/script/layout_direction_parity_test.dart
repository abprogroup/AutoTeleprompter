import 'package:autoteleprompter/features/script/models/cursor_style.dart';
import 'package:autoteleprompter/features/script/services/styling_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/suites/layout_suite_mvp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('layout and direction tags do not erase each other', () {
    final aligned = StylingService.applyLayout(
      '[rtl][center]שלום עולם[/center][/rtl]',
      const TextSelection.collapsed(offset: 0),
      'right',
    );

    expect(aligned, '[right][rtl]שלום עולם[/rtl][/right]');

    final directed = StylingService.applyDirection(
      '[left][ltr]hello world[/ltr][/left]',
      const TextSelection.collapsed(offset: 0),
      'rtl',
    );

    expect(directed, '[rtl][left]hello world[/left][/rtl]');
  });

  testWidgets('LayoutSuite exposes explicit LTR and RTL actions',
      (tester) async {
    final directions = <String>[];
    final interactions = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cursorStyleProvider.overrideWith(
            (ref) => CursorStyle(textDirection: 'rtl'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LayoutSuite(
              onAlign: (_) {},
              onDirection: directions.add,
              onInteraction: interactions.add,
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Force LTR'), findsOneWidget);
    expect(find.byTooltip('Force RTL'), findsOneWidget);

    await tester.tap(find.byTooltip('Force LTR'));
    await tester.pump();

    expect(directions, ['ltr']);
    expect(interactions, ['Text Direction']);
  });
}
