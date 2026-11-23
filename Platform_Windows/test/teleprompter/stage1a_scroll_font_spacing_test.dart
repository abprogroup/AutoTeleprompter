import 'package:autoteleprompter/core/security/secure_script_store.dart';
import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/services/editor_inline_style_operation.dart';
import 'package:autoteleprompter/features/script/services/script_typography_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/teleprompter_screen.dart';
import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStt extends AbstractSttService {
  @override
  String get platformName => 'Stage1A Fake STT';

  @override
  bool get isListening => true;

  @override
  Future<SpeechStartResult> start({String? localeId}) async =>
      SpeechStartResult(success: true);

  @override
  Future<void> stop() async {}

  void markListening(TeleprompterNotifier notifier) {
    notifier.reportEmbeddedSttHostLoaded();
    for (final event in [
      'socketConnected',
      'microphoneReady',
      'recognizerListening',
    ]) {
      onRuntimeHealth?.call(
        SttRuntimeHealth(type: event, listening: true, locale: 'en-US'),
      );
    }
    onStatusChange?.call(SpeechStatus.listening);
  }
}

class _TestSettings extends SettingsNotifier {
  _TestSettings([this._initial = const AppSettings(
    fontSize: 20,
    allowScrollDuringActiveSession: true,
    languageMode: AppSettings.languageModeEnglish,
  )]);
  final AppSettings _initial;

  @override
  AppSettings build() => _initial;
}

class _TestScript extends ScriptNotifier {
  _TestScript(this._initial);
  final Script _initial;

  @override
  Script build() {
    super.build();
    return _initial;
  }
}

class _MemoryStore extends SecureScriptStore {
  final records = <String, String>{};
  @override
  Future<SecureScriptData?> read(String? recordId) async =>
      records.containsKey(recordId)
          ? SecureScriptData(text: records[recordId]!)
          : null;
  @override
  Future<String> save({
    required String recordId,
    required String text,
    String? historyJson,
  }) async {
    records[recordId] = text;
    return recordId;
  }
}

SecureScriptStore _createTempStore() => _MemoryStore();

Script _buildMixedDocxScript({String sessionId = 'sess-stage1a'}) {
  final lines = <String>[
    '[font=Arial][size=18]Heading One[/size][/font]',
    for (var i = 0; i < 40; i++)
      '[font=Arial][size=11]Paragraph line $i alpha beta gamma delta epsilon[/size][/font]',
  ];
  final raw = lines.join('\n');
  return Script(
    id: 'stage1a',
    title: 'Mixed DOCX',
    rawText: raw,
    words: WordAligner.tokenize(raw),
    isRtl: false,
    sessionId: sessionId,
    fontSize: 11,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Stage 1A — Bug 2: Proportional font size & spacing', () {
    test('scales mixed-size DOCX inline tags proportionally without stripping', () {
      const raw =
          '[font=Arial][size=18]Title[/size][/font]\n[font=Arial][size=11]Body words here[/size][/font]';
      final script = Script(
        id: 'mixed',
        title: 'Mixed',
        rawText: raw,
        words: WordAligner.tokenize(raw),
        isRtl: false,
        sessionId: 'mixed-1',
        fontSize: 11,
      );

      final base = ScriptTypographyService.effectiveBaseFontSize(script, 24);
      expect(base, 11.0);

      final scaled = ScriptTypographyService.scaleInlineFontSizes(
        raw,
        fromBaseSize: base,
        toBaseSize: 22.0,
      );
      expect(scaled, contains('[size=36]Title[/size]'));
      expect(scaled, contains('[size=22]Body words here[/size]'));
    });

    test('rapid applyBaseFontSize updates script state synchronously (+1 step)', () async {
      final store = _createTempStore();
      final script = _buildMixedDocxScript();
      final container = ProviderContainer(
        overrides: [
          scriptLibraryStoreProvider.overrideWithValue(store),
          settingsProvider.overrideWith(_TestSettings.new),
          scriptProvider.overrideWith(() => _TestScript(script)),
        ],
      );
      addTearDown(container.dispose);

      // Start at dominant body 11 -> bump +1 to 12, 13, 14 synchronously!
      final notifier = container.read(scriptProvider.notifier);
      notifier.applyBaseFontSize(12);
      expect(container.read(scriptProvider)!.fontSize, 12.0);
      expect(container.read(settingsProvider).fontSize, 12.0);
      expect(
        container.read(scriptProvider)!.words.first.fontSize,
        closeTo(19.6, 0.2),
      );
      notifier.applyBaseFontSize(13);
      expect(container.read(scriptProvider)!.fontSize, 13.0);
      await notifier.applyBaseFontSize(14);
      expect(container.read(scriptProvider)!.fontSize, 14.0);
      expect(
        container.read(scriptProvider)!.words.first.fontSize,
        closeTo(22.9, 0.2),
      );
    });

    test('presenter A+ button enlarges mixed DOCX by +1 proportionally', () async {
      // Widget-level check in the next test; here verify spacing helper math.
      expect(ScriptTypographyService.effectiveSpacing(0.0), isNull);
      expect(ScriptTypographyService.effectiveSpacing(1.5, scale: 2.0), 3.0);
      expect(ScriptTypographyService.presenterWordGap(40.0, 2.0), closeTo(15.2, 0.01));

      // Per-paragraph word gap scales to large inline headings instead of
      // staying cramped at the small base body font size.
      final mixed = WordAligner.tokenize(
        '[size=50]Big Heading Line[/size]\n[size=17]small body line[/size]',
      );
      final headingPara = mixed.takeWhile((w) => !w.isNewline).toList();
      final bodyPara = mixed.skipWhile((w) => !w.isNewline).skip(1).toList();
      final headingSize = ScriptTypographyService.paragraphPresentationFontSize(
        headingPara,
        34.0,
      );
      final bodySize = ScriptTypographyService.paragraphPresentationFontSize(
        bodyPara,
        34.0,
      );
      expect(headingSize, closeTo(100.0, 0.01));
      expect(bodySize, closeTo(34.0, 0.01));
      expect(
        ScriptTypographyService.presenterWordGap(headingSize, 0.0),
        closeTo(28.0, 0.01),
      );
      expect(
        ScriptTypographyService.maxScriptWordGap([headingPara, bodyPara], 34.0, 0.0),
        closeTo(28.0, 0.01),
      );
    });

    test(
      'v5.2.5: blank lines inherit surrounding font size, min font reaches 1, and A- keeps shrinking larger text at floor',
      () async {
        // 1. Blank line inherits surrounding paragraph rendered font size
        final tokenized = WordAligner.tokenize(
          '[size=50]Big Heading[/size]\n\n[size=17]small body[/size]',
        );
        final paras = <List<ScriptWord>>[];
        var cur = <ScriptWord>[];
        for (final w in tokenized) {
          if (w.isNewline) {
            if (cur.isNotEmpty) {
              paras.add(cur);
              cur = [];
            }
            paras.add([w]);
          } else {
            cur.add(w);
          }
        }
        if (cur.isNotEmpty) paras.add(cur);
        final blankIdx = paras.indexWhere(
          (p) => p.length == 1 && p.first.isNewline && p.first.raw == '\n\n',
        );
        expect(blankIdx, greaterThan(0));
        expect(
          ScriptTypographyService.blankLinePresentationFontSize(
            paras,
            blankIdx,
            16.0,
          ),
          closeTo(100.0, 0.01),
        );

        // 2. Minimum font size reaches 1.0 (not stuck at 8.0), and A- continues
        // shrinking remaining larger headings even after base/body hits 1.0.
        expect(ScriptTypographyService.minBaseFontSize, 1.0);
        expect(ScriptTypographyService.minInlineFontSize, 1.0);

        final store = _createTempStore();
        const raw =
            '[size=40]Heading[/size]\n[size=1]tiny body one two three four[/size]';
        final script = Script(
          id: 'floor-test',
          title: 'Floor Test',
          rawText: raw,
          words: WordAligner.tokenize(raw),
          isRtl: false,
          fontSize: 1.0,
          sessionId: 'floor-test',
        );
        final container = ProviderContainer(
          overrides: [
            scriptLibraryStoreProvider.overrideWithValue(store),
            settingsProvider.overrideWith(_TestSettings.new),
            scriptProvider.overrideWith(() => _TestScript(script)),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(scriptProvider.notifier);
        await notifier.applyFontSizeDelta(-1);
        final afterFirst = container.read(scriptProvider)!;
        expect(afterFirst.fontSize, 1.0);
        expect(afterFirst.words.first.fontSize, closeTo(39.0, 0.1));

        await notifier.applyFontSizeDelta(-1);
        final afterSecond = container.read(scriptProvider)!;
        expect(afterSecond.words.first.fontSize, closeTo(38.0, 0.1));
      },
    );
  });

  group('Stage 1A — Bug 1: Active-STT manual scroll greying & script identity', () {
    test('finishManualScroll still commits after scriptProvider copyWith font resize', () async {
      final store = _createTempStore();
      final stt = _FakeStt();
      final script = _buildMixedDocxScript(sessionId: 'same-session');
      final container = ProviderContainer(
        overrides: [
          scriptLibraryStoreProvider.overrideWithValue(store),
          settingsProvider.overrideWith(_TestSettings.new),
          scriptProvider.overrideWith(() => _TestScript(script)),
          teleprompterProvider.overrideWith(
            () => TeleprompterNotifier(browserSpeechService: stt),
          ),
        ],
      );
      addTearDown(container.dispose);

      final tp = container.read(teleprompterProvider.notifier);
      await tp.startSession(script);
      stt.markListening(tp);
      expect(container.read(teleprompterProvider).isListening, isTrue);

      // Change font size during active session -> creates a NEW Script instance.
      await container.read(scriptProvider.notifier).applyBaseFontSize(24);
      final updatedScript = container.read(scriptProvider)!;
      expect(identical(updatedScript, script), isFalse);
      expect(updatedScript.sessionId, script.sessionId);

      expect(tp.beginManualScroll(), isTrue);
      tp.finishManualScroll(15, script: updatedScript);
      expect(container.read(teleprompterProvider).confirmedWordIndex, 15);

      await tp.stopSession();
    });

    testWidgets('active STT manual wheel scroll greys text live & commits; stopped scroll keeps greying quiet', (
      tester,
    ) async {
      final store = _createTempStore();
      final stt = _FakeStt();
      final script = _buildMixedDocxScript(sessionId: 'live-grey-session');
      final container = ProviderContainer(
        overrides: [
          scriptLibraryStoreProvider.overrideWithValue(store),
          settingsProvider.overrideWith(_TestSettings.new),
          scriptProvider.overrideWith(() => _TestScript(script)),
          teleprompterProvider.overrideWith(
            () => TeleprompterNotifier(browserSpeechService: stt),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 750);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(
              platform: TargetPlatform.windows,
              brightness: Brightness.dark,
            ),
            home: const TeleprompterScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // 1) Stopped (mic OFF): scrolling must NOT advance confirmedWordIndex.
      final scrollFinder = find.byType(SingleChildScrollView).first;
      final center = tester.getCenter(scrollFinder);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 320)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(teleprompterProvider).confirmedWordIndex, 0);

      // Scroll back to top, then start active STT session.
      final controller =
          tester.widget<SingleChildScrollView>(scrollFinder).controller!;
      controller.jumpTo(0);
      await tester.pump();

      final tp = container.read(teleprompterProvider.notifier);
      var started = false;
      final startup = tp.startSession(script).then((_) => started = true);
      for (var i = 0; i < 20 && !started; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(started, isTrue);
      await startup;
      stt.markListening(tp);
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(teleprompterProvider).isListening, isTrue);

      // 2) Mic ON + manual wheel scroll: greyed word opacity updates live
      //    BEFORE the 420ms commit timer settles, then commits after quiet window.
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 360)));
      await tester.pump(const Duration(milliseconds: 120));

      // Before 420ms settle, provider is still in manual scroll transaction,
      // yet word 0 ("Heading") is already visually dimmed (pastWordOpacity).
      expect(tp.manualScrollInProgress, isTrue);
      final firstWordText = tester.widget<Text>(find.text('Heading').first);
      expect(firstWordText.style!.color!.a, lessThan(0.9));

      // After quiet window, confirmedWordIndex commits > 0.
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        container.read(teleprompterProvider).confirmedWordIndex,
        greaterThan(0),
      );

      // 3) Bug 2 live check: tapping Larger font (A+) during active STT scales
      //    mixed DOCX by +1 proportionally (11 -> 12, Heading 18 -> ~19.6) AND
      //    a subsequent manual scroll still commits (no !identical drop!).
      // Reveal bottom control bar via hover hot-zone on Windows.
      await tester.sendEventToBinding(pointer.hover(const Offset(550, 720)));
      await tester.pump(const Duration(milliseconds: 300));
      final beforeHeadingSize =
          tester.widget<Text>(find.text('Heading').first).style!.fontSize!;
      await tester.tap(find.byTooltip('Larger font'));
      await tester.pump();
      final afterHeadingSize =
          tester.widget<Text>(find.text('Heading').first).style!.fontSize!;
      expect(afterHeadingSize, greaterThan(beforeHeadingSize));
      expect(container.read(scriptProvider)!.fontSize, 12.0);

      await tp.stopSession();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Stage 1A — Bug 3: Edit mode font resize keeps clean letter & word spacing', () {
    test('applyParameterized does not fragment [size=...] across inline [font=]/[bg=]/[u] tags', () {
      const input =
          '[font=Arial][size=11]Hello[/size][/font] [bg=#FFFF00][font=Arial][size=11]world[/size][/font][/bg] [u]now[/u]';
      final result = EditorInlineStyleOperation.applyParameterized(
        text: input,
        selection: const TextSelection(baseOffset: 0, extentOffset: input.length),
        family: 'size',
        value: '28',
      );
      expect(
        RegExp(r'\[size=28\]').allMatches(result.text).length,
        1,
        reason: 'Should wrap once instead of fragmenting around every inline tag: ${result.text}',
      );
      expect(
        RegExp(r'\[/size\]').allMatches(result.text).length,
        1,
        reason: 'Should emit a single closing tag: ${result.text}',
      );
    });

    testWidgets('MarkupController keeps normal word/letter box geometry after inline resize on styled Hebrew + English text', (
      tester,
    ) async {
      const original =
          '[font=Arial][size=11]שלום עולם[/size][/font] [bg=#FFFF00][font=Arial][size=11]בדיקה[/size][/font][/bg]';
      final resized = EditorInlineStyleOperation.applyParameterized(
        text: original,
        selection: const TextSelection(baseOffset: 0, extentOffset: original.length),
        family: 'size',
        value: '32',
      );
      final plainCtrl = MarkupController(text: 'שלום עולם בדיקה');
      final styledCtrl = MarkupController(text: resized.text);
      addTearDown(() {
        plainCtrl.dispose();
        styledCtrl.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              child: Column(
                children: [
                  TextField(
                    controller: plainCtrl,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 32, fontFamily: 'Arial'),
                  ),
                  TextField(
                    controller: styledCtrl,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontSize: 32, fontFamily: 'Arial'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final plainEditable = tester
          .state<EditableTextState>(find.byType(EditableText).at(0))
          .renderEditable;
      final styledEditable = tester
          .state<EditableTextState>(find.byType(EditableText).at(1))
          .renderEditable;

      final plainBoxes = plainEditable.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plainCtrl.text.length),
      );
      final styledBoxes = styledEditable.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: styledCtrl.text.length),
      );

      double spanWidth(List<TextBox> boxes) {
        final nonEmpty = boxes.where((b) => b.right - b.left > 0.01).toList();
        final left = nonEmpty.map((b) => b.left).reduce((a, b) => a < b ? a : b);
        final right =
            nonEmpty.map((b) => b.right).reduce((a, b) => a > b ? a : b);
        return right - left;
      }

      final plainWidth = spanWidth(plainBoxes);
      final styledWidth = spanWidth(styledBoxes);

      // Hidden tags must not inflate total line width beyond tiny rounding epsilon.
      expect(
        (styledWidth - plainWidth).abs(),
        lessThan(4.0),
        reason: 'Styled width=$styledWidth vs plain width=$plainWidth',
      );
    });
  });
}
