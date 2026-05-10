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
