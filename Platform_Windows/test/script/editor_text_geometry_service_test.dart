import 'package:autoteleprompter/features/script/models/editor_state.dart';
import 'package:autoteleprompter/features/script/services/editor_text_geometry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int identityRawToVisible(String _, int offset) => offset;
  int identityVisibleToRaw(String _, int offset) => offset;

  TextPainter painterFor(
    String text, {
    required TextDirection direction,
    double width = 700,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 28, height: 1.2),
      ),
      textDirection: direction,
      textAlign:
          direction == TextDirection.rtl ? TextAlign.right : TextAlign.left,
    )..layout(maxWidth: width);
    return painter;
  }

  test('Hebrew empty row between Hebrew blocks resolves RTL', () {
    final blocks = [
      '\u05e9\u05d5\u05e8\u05d4 \u05e8\u05d0\u05e9\u05d5\u05e0\u05d4',
      '',
      '[u]\u05e9\u05d5\u05e8\u05d4 \u05e9\u05e0\u05d9\u05d4[/u]',
    ];

    expect(EditorTextGeometryService.resolveBlockRtl(blocks, 1), isTrue);
  });

  test('English empty row between English blocks resolves LTR', () {
    final blocks = [
      'First line',
      '[bg=#00FF00]   [/bg]',
      'Second line',
    ];

    expect(EditorTextGeometryService.resolveBlockRtl(blocks, 1), isFalse);
  });

  test('empty script defaults to LTR', () {
    expect(EditorTextGeometryService.resolveBlockRtl(['', '   '], 0), isFalse);
    expect(EditorTextGeometryService.resolveBlockRtl(['', '   '], 1), isFalse);
  });

  test('explicit alignment overrides resolved direction alignment', () {
    expect(
      EditorTextGeometryService.resolveTextAlign(
        '[align=center]\u05e9\u05dc\u05d5\u05dd[/align=center]',
        isRtl: true,
      ),
      TextAlign.center,
    );
    expect(
      EditorTextGeometryService.resolveTextAlign('', isRtl: true),
      TextAlign.right,
    );
    expect(
      EditorTextGeometryService.resolveTextAlign('', isRtl: false),
      TextAlign.left,
    );
  });

  test('max font size comes from the same markup rule used by layout', () {
    expect(
      EditorTextGeometryService.maxFontSize('[size=64]big[/size] small', 42),
      64,
    );
    expect(
      EditorTextGeometryService.maxFontSize('[size=36]small[/size]', 42),
      42,
    );
  });

  test('visual horizontal navigation keeps English LTR arrow behavior', () {
    const text = 'hello world';
    final painter = painterFor(text, direction: TextDirection.ltr);

    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 0,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      1,
    );
    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 1,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      0,
    );
  });

  test('visual horizontal navigation inverts correctly for Hebrew RTL', () {
    const text = '\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd';
    final painter = painterFor(text, direction: TextDirection.rtl);

    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 0,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      1,
    );
    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 1,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      0,
    );
  });

  test('visual horizontal navigation steps through whitespace-only LTR row',
      () {
    const text = ' ';
    final painter = painterFor(text, direction: TextDirection.ltr);

    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 0,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      1,
    );
    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 1,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      0,
    );
  });

  test('visual horizontal navigation steps through whitespace-only RTL row',
      () {
    const text = ' ';
    final painter = painterFor(text, direction: TextDirection.rtl);

    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 0,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      1,
    );
    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 1,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      0,
    );
  });

  test('visual horizontal navigation keeps English run LTR inside Hebrew RTL',
      () {
    const text = '\u05d0\u05d1\u05d2 abc \u05d3\u05d4\u05d5';
    final painter = painterFor(text, direction: TextDirection.rtl);
    final englishStart = text.indexOf('abc');

    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: englishStart,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      englishStart + 1,
    );
    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: englishStart + 1,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      englishStart,
    );
  });

  test('visual horizontal navigation carries punctuation with English island',
      () {
    const text =
        '\u05de\u05d4 \u05d6\u05d4 \u05de - TEMU? \u05de\u05d2\u05d4\u05d5\u05dc\u05d4?';
    final painter = painterFor(text, direction: TextDirection.rtl);
    final englishStart = text.indexOf('TEMU');
    final questionAfterEnglish = text.indexOf('?') + 1;

    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: englishStart + 4,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      questionAfterEnglish,
    );
    expect(
      EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: questionAfterEnglish,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      questionAfterEnglish - 1,
    );
  });

  test('wrapped Hebrew arrow-left walks the visual line without row bouncing',
      () {
    const text =
        '\u05d5\u05d4\u05d1\u05ea \u05e9\u05dc\u05d9 \u05d2\u05dd \u05d0\u05d9\u05df \u05dc\u05d4 \u05d1\u05e2\u05d9\u05d4 \u05dc\u05e9\u05e7\u05e8 \u05dc\u05d9 \u05d1\u05e4\u05e8\u05e6\u05d5\u05e3';
    final painter = painterFor(text, direction: TextDirection.rtl, width: 360);

    var offset = 0;
    for (var expected = 1; expected <= 12; expected++) {
      offset = EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: offset,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      )!;
      expect(offset, expected);
    }
  });

  test('wrapped Hebrew arrow-left walks pure RTL text without loops', () {
    const text =
        '\u05d0\u05ea \u05d0\u05d5\u05de\u05e8\u05ea \u05e0\u05d2\u05de\u05e8\u05d5 \u05d4\u05de\u05e9\u05d7\u05e7\u05d9\u05dd \u05e0\u05d5\u05e4\u05dc\u05ea \u05db\u05d5\u05e1 \u05e2\u05dc \u05d4\u05e1\u05d3\u05d9\u05e0\u05d9\u05dd \u05d0\u05e0\u05d9 \u05e0\u05d5\u05d7\u05e8 \u05db\u05de\u05d5 \u05db\u05dc\u05d1 \u05d1\u05d0\u05d9\u05d2\u05d5\u05d3 \u05d4\u05e0\u05d5\u05db\u05dc\u05d9\u05dd \u05d0\u05d9\u05df \u05d9\u05d5\u05ea\u05e8 \u05de\u05d5\u05e2\u05d3\u05d5\u05e0\u05d9\u05dd';
    final painter = painterFor(text, direction: TextDirection.rtl, width: 360);

    var offset = 0;
    final visited = <int>{offset};
    for (var i = 0; i < text.length + 12 && offset < text.length; i++) {
      final next = EditorTextGeometryService.visualHorizontalTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: offset,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      );
      expect(next, isNotNull);
      expect(next, isNot(offset));
      expect(visited.add(next!), isTrue);
      offset = next;
    }
    expect(offset, text.length);
  });

  test('wrapped Hebrew vertical arrows choose adjacent visual-line caret stops',
      () {
    const text =
        '\u05d0\u05ea \u05d0\u05d5\u05de\u05e8\u05ea \u05e0\u05d2\u05de\u05e8\u05d5 \u05d4\u05de\u05e9\u05d7\u05e7\u05d9\u05dd \u05e0\u05d5\u05e4\u05dc\u05ea \u05db\u05d5\u05e1 \u05e2\u05dc \u05d4\u05e1\u05d3\u05d9\u05e0\u05d9\u05dd \u05d0\u05e0\u05d9 \u05e0\u05d5\u05d7\u05e8 \u05db\u05de\u05d5 \u05db\u05dc\u05d1 \u05d1\u05d0\u05d9\u05d2\u05d5\u05d3 \u05d4\u05e0\u05d5\u05db\u05dc\u05d9\u05dd \u05d0\u05d9\u05df \u05d9\u05d5\u05ea\u05e8 \u05de\u05d5\u05e2\u05d3\u05d5\u05e0\u05d9\u05dd';
    final painter = painterFor(text, direction: TextDirection.rtl, width: 360);
    final lowerWord = text.indexOf(
      '\u05de\u05d5\u05e2\u05d3\u05d5\u05e0\u05d9\u05dd',
    );
    final sourceOffset = lowerWord + 1;
    final targetOffset =
        EditorTextGeometryService.visualVerticalTargetRawOffset(
      painter: painter,
      rawText: text,
      rawOffset: sourceOffset,
      moveUp: true,
      rawToVisibleOffset: identityRawToVisible,
      visibleToRawOffset: identityVisibleToRaw,
    );

    expect(targetOffset, isNotNull);
    expect(targetOffset, 81);
    final sourceAgain = EditorTextGeometryService.visualVerticalTargetRawOffset(
      painter: painter,
      rawText: text,
      rawOffset: targetOffset!,
      moveUp: false,
      rawToVisibleOffset: identityRawToVisible,
      visibleToRawOffset: identityVisibleToRaw,
    );
    expect(sourceAgain, sourceOffset);
  });

  test('wrapped Hebrew vertical arrows preserve screen column', () {
    const text =
        '\u05d0\u05ea \u05d0\u05d5\u05de\u05e8\u05ea \u05e0\u05d2\u05de\u05e8\u05d5 \u05d4\u05de\u05e9\u05d7\u05e7\u05d9\u05dd \u05e0\u05d5\u05e4\u05dc\u05ea \u05db\u05d5\u05e1 \u05e2\u05dc \u05d4\u05e1\u05d3\u05d9\u05e0\u05d9\u05dd \u05d0\u05e0\u05d9 \u05e0\u05d5\u05d7\u05e8 \u05db\u05de\u05d5 \u05db\u05dc\u05d1 \u05d1\u05d0\u05d9\u05d2\u05d5\u05d3 \u05d4\u05e0\u05d5\u05db\u05dc\u05d9\u05dd \u05d0\u05d9\u05df \u05d9\u05d5\u05ea\u05e8 \u05de\u05d5\u05e2\u05d3\u05d5\u05e0\u05d9\u05dd';
    final painter = painterFor(text, direction: TextDirection.rtl, width: 360);
    final lowerWord = text.indexOf(
      '\u05de\u05d5\u05e2\u05d3\u05d5\u05e0\u05d9\u05dd',
    );
    final sourceOffset = lowerWord + 1;
    final targetOffset =
        EditorTextGeometryService.visualVerticalTargetRawOffset(
      painter: painter,
      rawText: text,
      rawOffset: sourceOffset,
      moveUp: true,
      rawToVisibleOffset: identityRawToVisible,
      visibleToRawOffset: identityVisibleToRaw,
    );

    expect(targetOffset, isNotNull);
    final sourceX = painter
        .getOffsetForCaret(
          TextPosition(offset: sourceOffset),
          Rect.zero,
        )
        .dx;
    final targetX = painter
        .getOffsetForCaret(
          TextPosition(offset: targetOffset!),
          Rect.zero,
        )
        .dx;
    expect((sourceX - targetX).abs(), lessThan(24));
  });

  test('RTL line target from right edge uses visual caret stops', () {
    const text =
        '\u05d0\u05ea \u05d0\u05d5\u05de\u05e8\u05ea \u05e0\u05d2\u05de\u05e8\u05d5 \u05d4\u05de\u05e9\u05d7\u05e7\u05d9\u05dd \u05e0\u05d5\u05e4\u05dc\u05ea \u05db\u05d5\u05e1 \u05e2\u05dc \u05d4\u05e1\u05d3\u05d9\u05e0\u05d9\u05dd \u05d0\u05e0\u05d9 \u05e0\u05d5\u05d7\u05e8 \u05db\u05de\u05d5 \u05db\u05dc\u05d1 \u05d1\u05d0\u05d9\u05d2\u05d5\u05d3 \u05d4\u05e0\u05d5\u05db\u05dc\u05d9\u05dd \u05d0\u05d9\u05df \u05d9\u05d5\u05ea\u05e8 \u05de\u05d5\u05e2\u05d3\u05d5\u05e0\u05d9\u05dd';
    const width = 360.0;
    final painter =
        painterFor(text, direction: TextDirection.rtl, width: width);

    final target = EditorTextGeometryService.visualLineTargetRawOffset(
      painter: painter,
      rawText: text,
      x: width,
      fromBottom: true,
      visibleToRawOffset: identityVisibleToRaw,
    );

    expect(target, isNotNull);
    final targetX =
        painter.getOffsetForCaret(TextPosition(offset: target!), Rect.zero).dx;
    expect((targetX - width).abs(), lessThan(32));
  });

  test('visual word navigation keeps English Ctrl arrows LTR', () {
    const text = 'hello world';
    final painter = painterFor(text, direction: TextDirection.ltr);

    expect(
      EditorTextGeometryService.visualWordTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 0,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      5,
    );
    expect(
      EditorTextGeometryService.visualWordTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 5,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      0,
    );
  });

  test('visual word navigation inverts Hebrew Ctrl arrows by visual order', () {
    const text = '\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd';
    final painter = painterFor(text, direction: TextDirection.rtl);

    expect(
      EditorTextGeometryService.visualWordTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 0,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      4,
    );
    expect(
      EditorTextGeometryService.visualWordTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: 4,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      0,
    );
  });

  test('visual word navigation keeps English Ctrl arrows inside Hebrew RTL',
      () {
    const text = '\u05d0\u05d1\u05d2 abc \u05d3\u05d4\u05d5';
    final painter = painterFor(text, direction: TextDirection.rtl);
    final englishStart = text.indexOf('abc');

    expect(
      EditorTextGeometryService.visualWordTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: englishStart,
        moveLeft: false,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      englishStart + 3,
    );
    expect(
      EditorTextGeometryService.visualWordTargetRawOffset(
        painter: painter,
        rawText: text,
        rawOffset: englishStart + 3,
        moveLeft: true,
        rawToVisibleOffset: identityRawToVisible,
        visibleToRawOffset: identityVisibleToRaw,
      ),
      englishStart,
    );
  });

  EditorState stateWithHistoryMetadata({
    int? focusBlockIndex,
    int? selectionBaseOffset,
    int? selectionExtentOffset,
    double? scrollOffset,
  }) {
    return EditorState(
      text: 'first\nsecond',
      timestamp: DateTime.utc(2026, 5, 7),
      description: 'Edit Text',
      fontSize: 42,
      fontFamily: 'Inter',
      lineSpacing: 1.2,
      letterSpacing: 0,
      wordSpacing: 0,
      scriptBgColor: 0xFF000000,
      currentWordColor: 0xFFFFBF00,
      futureWordColor: 0xFFFFFFFF,
      textAlign: 'left',
      focusBlockIndex: focusBlockIndex,
      selectionBaseOffset: selectionBaseOffset,
      selectionExtentOffset: selectionExtentOffset,
      scrollOffset: scrollOffset,
    );
  }

  test('history focus metadata round-trips', () {
    final state = stateWithHistoryMetadata(
      focusBlockIndex: 1,
      selectionBaseOffset: 4,
      selectionExtentOffset: 7,
      scrollOffset: 220.5,
    );
    final restored = EditorState.fromJson(state.toJson());

    expect(restored.focusBlockIndex, 1);
    expect(restored.selectionBaseOffset, 4);
    expect(restored.selectionExtentOffset, 7);
    expect(restored.scrollOffset, 220.5);
  });

  test('old history JSON remains backwards-compatible', () {
    final json = stateWithHistoryMetadata().toJson()
      ..remove('focusBlockIndex')
      ..remove('selectionBaseOffset')
      ..remove('selectionExtentOffset')
      ..remove('scrollOffset');

    final restored = EditorState.fromJson(json);

    expect(restored.text, 'first\nsecond');
    expect(restored.focusBlockIndex, isNull);
    expect(restored.selectionBaseOffset, isNull);
    expect(restored.selectionExtentOffset, isNull);
    expect(restored.scrollOffset, isNull);
  });
}
