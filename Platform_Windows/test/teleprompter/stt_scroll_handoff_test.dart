// Combined presenter/provider regressions. Only the speech transport is fake:
// wheel/drag notifications, viewport bounds and tracking decisions are real.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/models/alignment_result.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_connection_status.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/teleprompter_screen.dart';
import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _proofDirectory = String.fromEnvironment('STT_SCROLL_PROOF_DIR');

class _SpeechTransport extends AbstractSttService {
  int starts = 0;
  int stops = 0;
  final locales = <String>[];
  @override
  String get platformName => 'Combined scroll fake transport';
  @override
  bool get isListening => true;
  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    starts++;
    return SpeechStartResult(success: true);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  void setLocale(String locale) => locales.add(locale);

  void hear(String text, {int stream = 7, bool finalResult = false}) {
    onResult!(
      SpeechResult(text, finalResult, isCumulative: true, streamId: stream),
    );
  }

  void health(String type) => onRuntimeHealth!(
    SttRuntimeHealth(type: type, listening: true, locale: 'en-US'),
  );
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(
    fontSize: 36,
    currentWordColor: 0xFFFF00FF,
    scrollLead: .35,
    debugMode: true,
    allowScrollDuringActiveSession: true,
    languageMode: AppSettings.languageModeEnglish,
    sttManualProfileEnabled: true,
    sttVisibleSkipEnabled: true,
    sttManualStartAdvanceSmallWords: 3,
    sttManualStartAdvanceBigWords: 2,
    sttManualSafetySmallWords: 2,
    sttManualSafetyBigWords: 1,
    sttManualVisibleSkipSmallWords: 4,
    sttManualVisibleSkipBigWords: 3,
  );
}

class _Script extends ScriptNotifier {
  _Script(this.script);
  final Script script;
  @override
  Script build() => script;
}

class _Harness {
  _Harness(this.tester);
  final WidgetTester tester;
  final speech = _SpeechTransport();
  bool _closed = false;
  final proofKey = GlobalKey();
  late final script = _makeScript();
  late final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_Settings.new),
      scriptProvider.overrideWith(() => _Script(script)),
      teleprompterProvider.overrideWith(
        () => TeleprompterNotifier(browserSpeechService: speech),
      ),
    ],
  );
  TeleprompterNotifier get notifier =>
      container.read(teleprompterProvider.notifier);
  TeleprompterState get state => container.read(teleprompterProvider);
  int get position => state.confirmedWordIndex;
  List<String> get jumps =>
      state.debugLogs.where((line) => line.contains('POSITION JUMP')).toList();
  String get diagnostics => state.debugLogs.join('\n');
  ScrollController get scroll =>
      tester
          .widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          )
          .controller!;
  String phrase(int start, int count) =>
      script.words.skip(start).take(count).map((word) => word.raw).join(' ');

  Future<void> mount() async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 750);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // Flutter widget tests otherwise default to Android touch metrics.
          theme: ThemeData(
            platform: TargetPlatform.windows,
            brightness: Brightness.dark,
            fontFamily: 'Inter',
          ),
          home: RepaintBoundary(
            key: proofKey,
            child: Stack(
              children: [
                const TeleprompterScreen(),
                if (_proofDirectory.isNotEmpty)
                  const Positioned(
                    top: 4,
                    left: 4,
                    child: IgnorePointer(
                      child: Text(
                        'SIMULATED SPEECH TRANSPORT - REAL PRESENTER + TRACKING',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await startSpeech();
  }

  Future<void> startSpeech() async {
    var started = false;
    final startup = notifier.startSession(script).then((_) => started = true);
    for (var i = 0; i < 20 && !started; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(started, isTrue, reason: diagnostics);
    await startup;
    notifier.reportEmbeddedSttHostLoaded();
    for (final event in [
      'socketConnected',
      'microphoneReady',
      'recognizerListening',
    ]) {
      speech.health(event);
    }
    speech.onStatusChange!(SpeechStatus.listening);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.isListening, isTrue, reason: diagnostics);
  }

  Future<void> capture(String name) async {
    if (_proofDirectory.isEmpty) return;
    await tester.pump();
    final boundary =
        proofKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_proofDirectory);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> wheel(double delta) async {
    final position = tester.getCenter(find.byType(SingleChildScrollView).first);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: Offset(0, delta),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
  }

  Future<void> settleScroll() async {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await notifier.stopSession();
    container.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Script _makeScript() {
  const paragraphs = [
    'Travelers discover remarkable gardens beside peaceful rivers where bright '
        'flowers welcome curious visitors every morning. Nearby musicians gather '
        'under ancient branches while thoughtful children share colorful stories '
        'about mountains oceans forests deserts islands valleys and distant cities.',
    'Careful engineers prepare detailed drawings before building durable bridges '
        'across narrow channels. Their colleagues discuss practical schedules '
        'and inspect important measurements together. Each completed structure '
        'offers reliable passage during changing weather throughout the year.',
    'Experienced teachers encourage patient observation because meaningful '
        'questions reveal unexpected discoveries. Students describe familiar '
        'patterns using ordinary language before comparing different explanations '
        'with evidence collected during afternoon experiments inside the laboratory.',
    'Friendly neighbors organize seasonal celebrations around the public square. '
        'Local artists display wonderful paintings while skilled bakers provide '
        'fresh bread and delicious pastries. Everyone enjoys conversation before '
        'walking home beneath the evening stars.',
  ];
  final raw = List.generate(3, (_) => paragraphs.join('\n\n')).join('\n\n');
  return Script(
    id: 'scroll-handoff',
    title: 'Combined scroll fixture',
    rawText: raw,
    words: WordAligner.tokenize(raw),
    isRtl: false,
    sessionId: 'scroll-handoff',
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_proofDirectory.isEmpty) return;
    await (FontLoader('Inter')..addFont(
      rootBundle.load('assets/fonts/google_fonts/Inter-Regular.ttf'),
    )).load();
    final mono = FontLoader('monospace');
    for (final file in ['consola.ttf', 'consolab.ttf']) {
      final bytes = await File('C:/Windows/Fonts/$file').readAsBytes();
      mono.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await mono.load();
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  Future<_Harness> mount(WidgetTester tester) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    await h.mount();
    return h;
  }

  testWidgets('wheel burst commits one reading anchor only after quiet', (
    tester,
  ) async {
    final h = await mount(tester);
    final origin = h.position;
    final jumps = h.jumps.length;
    for (var detent = 0; detent < 4; detent++) {
      await h.wheel(120);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        h.position,
        origin,
        reason:
            'A wheel burst must not commit intermediate anchors.\n${h.diagnostics}',
      );
    }
    expect(h.scroll.offset, greaterThan(0));
    await h.settleScroll();
    expect(h.position, greaterThan(origin), reason: h.diagnostics);
    expect(h.jumps.length - jumps, 1, reason: h.diagnostics);
    expect(h.speech.starts, 1);
    expect(h.speech.locales, isEmpty);
  });

  testWidgets('live callback during moving cannot advance the old anchor', (
    tester,
  ) async {
    final h = await mount(tester);
    final origin = h.position;
    await h.wheel(120);
    h.speech.hear(h.phrase(1, 5));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      h.position,
      origin,
      reason:
          'Incoming old-location speech must not win during manual scrolling.\n${h.diagnostics}',
    );
    await h.wheel(120);
    await h.settleScroll();
    final committed = h.position;
    h.speech.hear(h.phrase(1, 5));
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.position, committed, reason: h.diagnostics);
    expect(h.speech.starts, 1);
  });

  testWidgets(
    'fresh same-stream append immediately after commit is not swallowed',
    (tester) async {
      final h = await mount(tester);
      final old = h.phrase(1, 5);
      await h.wheel(360);
      h.speech.hear(old);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      final committed = h.position;
      expect(committed, greaterThan(0), reason: h.diagnostics);
      await h.capture('01_manual_anchor_settled');
      final fresh = h.phrase(committed + 1, 3);
      h.speech.hear('$old $fresh');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(h.position, committed + 3, reason: h.diagnostics);
      expect(h.speech.starts, 1);
      expect(h.speech.locales, isEmpty);
      await h.capture('02_fresh_same_stream_advanced');
    },
  );

  testWidgets(
    'new recognizer stream during wheel motion keeps its fresh suffix',
    (tester) async {
      final h = await mount(tester);
      await h.wheel(360);
      h.speech.hear(h.phrase(1, 4), stream: 7);
      final during = h.phrase(5, 3);
      h.speech.hear(during, stream: 8);
      await h.settleScroll();
      final committed = h.position;
      h.speech.hear(during, stream: 8, finalResult: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.position, committed, reason: h.diagnostics);
      h.speech.hear('$during ${h.phrase(committed + 1, 3)}', stream: 8);
      await tester.pump(const Duration(milliseconds: 700));
      expect(h.position, committed + 3, reason: h.diagnostics);
      expect(h.speech.starts, 1);
    },
  );

  testWidgets(
    'network waiting plus scroll holds until actual fresh visible speech',
    (tester) async {
      final h = await mount(tester);
      await h.wheel(360);
      h.speech.health('network');
      h.speech.health('networkAwaitingSpeech');
      await h.settleScroll();
      final committed = h.position;
      expect(h.state.statusMessage, SttConnectionStatus.awaitingSpeech);
      h.speech.onSoundLevelChange!(.8);
      for (var i = 0; i < 3; i++) {
        h.speech.health('heartbeat');
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(h.position, committed, reason: h.diagnostics);
      expect(h.speech.starts, 1);
      h.speech.hear(h.phrase(committed + 1, 3), stream: 8);
      h.speech.health('productiveResult');
      await tester.pump(const Duration(milliseconds: 700));
      expect(h.position, committed + 3, reason: h.diagnostics);
      expect(h.state.statusMessage, isEmpty);
    },
  );

  testWidgets(
    'scroll never makes off-screen speech eligible for an automatic jump',
    (tester) async {
      final h = await mount(tester);
      await h.wheel(360);
      await h.settleScroll();
      final committed = h.position;
      final offset = h.scroll.offset;
      final offscreen = h.phrase(95, 7);
      h.speech.hear(offscreen, stream: 8);
      await tester.pump(const Duration(milliseconds: 700));
      h.speech.hear(offscreen, stream: 8, finalResult: true);
      await tester.pump(const Duration(milliseconds: 700));
      expect(h.position, committed, reason: h.diagnostics);
      expect(h.scroll.offset, closeTo(offset, .1));
      expect(h.speech.starts, 1);
    },
  );

  testWidgets('drag freezes callbacks until release, then accepts new speech', (
    tester,
  ) async {
    final h = await mount(tester);
    final gesture = await tester.startGesture(const Offset(550, 350));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    final origin = h.position;
    h.speech.hear(h.phrase(1, 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.position, origin, reason: h.diagnostics);
    await gesture.moveBy(const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await h.settleScroll();
    final committed = h.position;
    expect(committed, greaterThan(origin), reason: h.diagnostics);
    h.speech.hear(h.phrase(committed + 1, 3), stream: 8);
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.position, committed + 3, reason: h.diagnostics);
  });

  testWidgets('a held drag stays suspended beyond the wheel quiet interval', (
    tester,
  ) async {
    final h = await mount(tester);
    final origin = h.position;
    final gesture = await tester.startGesture(const Offset(550, 350));
    // The first move crosses gesture slop; the second actually scrolls.
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    expect(h.scroll.offset, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    h.speech.hear(h.phrase(1, 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.position, origin, reason: h.diagnostics);
    expect(h.notifier.manualScrollInProgress, isTrue);
    await gesture.up();
    await h.settleScroll();
    expect(h.position, greaterThan(origin), reason: h.diagnostics);
    expect(h.notifier.manualScrollInProgress, isFalse);
  });

  testWidgets('stop and restart invalidate the pending old wheel anchor', (
    tester,
  ) async {
    final h = await mount(tester);
    await h.wheel(360);
    await tester.pump(const Duration(milliseconds: 100));
    await h.notifier.stopSession();
    expect(h.notifier.manualScrollInProgress, isFalse);
    await h.startSpeech();
    final restartedPosition = h.position;
    await h.settleScroll();
    expect(h.position, restartedPosition, reason: h.diagnostics);
    expect(h.speech.starts, 2);
    expect(h.notifier.manualScrollInProgress, isFalse);
    // A new gesture, not the stale timer, may now choose another anchor.
    await h.wheel(180);
    await h.settleScroll();
    final committed = h.position;
    h.speech.hear(h.phrase(committed + 1, 3), stream: 30);
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.position, committed + 3, reason: h.diagnostics);
  });

  testWidgets('held drag survives resize and release during another reflow', (
    tester,
  ) async {
    final h = await mount(tester);
    final origin = h.position;
    final gesture = await tester.startGesture(const Offset(550, 350));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    expect(h.scroll.offset, greaterThan(0));
    tester.view.physicalSize = const Size(1350, 820);
    await tester.pump();
    await h.settleScroll();
    h.speech.hear(h.phrase(1, 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.position, origin, reason: h.diagnostics);
    expect(h.notifier.manualScrollInProgress, isTrue);
    tester.view.physicalSize = const Size(1200, 780);
    // Release before the new viewport's post-frame restoration completes.
    await gesture.up();
    await tester.pump();
    await h.settleScroll();
    await h.settleScroll();
    final committed = h.position;
    expect(committed, greaterThan(origin), reason: h.diagnostics);
    expect(h.notifier.manualScrollInProgress, isFalse);
    h.speech.hear(h.phrase(committed + 1, 3), stream: 40);
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.position, committed + 3, reason: h.diagnostics);
  });

  testWidgets(
    'resize during a wheel handoff restores one anchor and can resume',
    (tester) async {
      final h = await mount(tester);
      await h.wheel(360);
      await tester.pump(const Duration(milliseconds: 100));
      tester.view.physicalSize = const Size(1350, 820);
      await tester.pump();
      h.speech.hear(h.phrase(1, 4));
      await h.settleScroll();
      final committed = h.position;
      expect(committed, greaterThan(0), reason: h.diagnostics);
      h.speech.hear(h.phrase(committed + 1, 3), stream: 8);
      await tester.pump(const Duration(milliseconds: 700));
      expect(h.position, committed + 3, reason: h.diagnostics);
      expect(h.speech.starts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repeated handoffs and disposal cancel pending gesture work', (
    tester,
  ) async {
    final h = await mount(tester);
    for (var i = 0; i < 3; i++) {
      await h.wheel(i == 1 ? -120 : 240);
      h.speech.hear(h.phrase(1, 4), stream: i + 10);
      await h.settleScroll();
      final committed = h.position;
      h.speech.hear(h.phrase(committed + 1, 3), stream: i + 20);
      await tester.pump(const Duration(milliseconds: 700));
      expect(h.position, committed + 3, reason: h.diagnostics);
    }
    expect(h.speech.starts, 1);
    await h.wheel(120);
    final callback = h.speech.onResult!;
    await h.close();
    callback(
      SpeechResult(
        'stale result after disposal',
        true,
        isCumulative: true,
        streamId: 22,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
