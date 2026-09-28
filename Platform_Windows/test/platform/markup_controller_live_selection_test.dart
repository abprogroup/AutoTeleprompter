import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkupController live custom selection painting', () {
    late MarkupController controller;

    setUp(() {
      controller = MarkupController(text: 'abcdef');
    });

    tearDown(() {
      controller.dispose();
    });

    test(
      'uses the native TextField range while a same-block drag is active',
      () {
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );

        expect(
          controller.customPaintSelection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
      },
    );

    test('does not paint a collapsed native caret', () {
      controller.selection = const TextSelection.collapsed(offset: 3);

      expect(controller.customPaintSelection, isNull);
    });

    test('external overlay selection takes priority over the native range', () {
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      controller.externalSelection = const TextSelection(
        baseOffset: 2,
        extentOffset: 4,
      );

      expect(
        controller.customPaintSelection,
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
    });

    test('collapsed external ownership suppresses stale native selection', () {
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      controller.externalSelection = const TextSelection.collapsed(offset: 2);

      expect(controller.customPaintSelection, isNull);
    });

    test('global selection covers the complete raw block', () {
      controller.selection = const TextSelection.collapsed(offset: 2);
      controller.isGlobalSelected = true;

      expect(
        controller.customPaintSelection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
    });

    test('clamps externally supplied offsets to the raw block', () {
      controller.externalSelection = const TextSelection(
        baseOffset: 2,
        extentOffset: 30,
      );

      expect(
        controller.customPaintSelection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
    });
  });
}
