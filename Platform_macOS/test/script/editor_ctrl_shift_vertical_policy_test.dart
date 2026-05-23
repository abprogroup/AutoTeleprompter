import 'package:autoteleprompter/features/script/widgets/script_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bookmark = '\u00BB';

  test('Ctrl+Shift vertical moves block by block through structural rows', () {
    final texts = [
      'You see sin is stronger than us',
      'There is something within us',
      bookmark,
      'EP8S23',
      '',
      'Are you struggling with guilt?',
    ];

    final fromBodyEnd = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 5,
      focusOffset: texts[5].length,
      moveUp: true,
    );
    expect(fromBodyEnd, (block: 5, offset: 0));

    final fromBodyStart = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 5,
      focusOffset: 0,
      moveUp: true,
    );
    expect(fromBodyStart, (block: 4, offset: 0));

    final fromEmpty = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 4,
      focusOffset: 0,
      moveUp: true,
    );
    expect(fromEmpty, (block: 3, offset: 0));

    final fromTitle = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 3,
      focusOffset: 0,
      moveUp: true,
    );
    expect(fromTitle, (block: 2, offset: 0));

    final fromBookmark = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 2,
      focusOffset: 0,
      moveUp: true,
    );
    expect(fromBookmark, (block: 1, offset: 0));
  });

  test('Ctrl+Shift vertical moves to adjacent block ends going down', () {
    final texts = [
      'First paragraph',
      bookmark,
      'EP8S23',
      '',
      'Next paragraph',
    ];

    final withinFirst = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 0,
      focusOffset: 0,
      moveUp: false,
    );
    expect(withinFirst, (block: 0, offset: texts[0].length));

    final afterFirst = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 0,
      focusOffset: texts[0].length,
      moveUp: false,
    );
    expect(afterFirst, (block: 1, offset: texts[1].length));

    final afterBookmark = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 1,
      focusOffset: texts[1].length,
      moveUp: false,
    );
    expect(afterBookmark, (block: 2, offset: texts[2].length));

    final afterTitle = EditorCtrlShiftVerticalPolicy.blockBoundaryTarget(
      texts: texts,
      blockIndex: 2,
      focusOffset: texts[2].length,
      moveUp: false,
    );
    expect(afterTitle, (block: 3, offset: 0));
  });
}
