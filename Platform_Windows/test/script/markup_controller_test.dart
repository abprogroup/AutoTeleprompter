import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden markup renders as neutral placeholders', (tester) async {
    final controller = MarkupController(
      text: '[align=right][u]שלום [פסח][/u][/align=right]',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: false,
            );
            final renderedPlain = span.toPlainText();

            expect(renderedPlain.length, controller.text.length);
            expect(renderedPlain, isNot(contains('[align=right]')));
            expect(renderedPlain, isNot(contains('[/align=right]')));
            expect(renderedPlain, isNot(contains('[u]')));
            expect(renderedPlain, isNot(contains('[/u]')));
            expect(
              renderedPlain.replaceAll('\u2060', ''),
              'שלום [פסח]',
            );

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
