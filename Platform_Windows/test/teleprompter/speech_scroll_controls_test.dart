import 'dart:io';
import 'dart:ui' as ui;

import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/speech_scroll_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  final proofKey = GlobalKey();

  setUpAll(() async {
    final fonts = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/google_fonts/Inter-Regular.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'displayName': 'scroll-ui-loaded'});
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  Future<void> showControls(
    WidgetTester tester, {
    double width = 480,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: proofKey,
                child: Container(
                  color: const Color(0xFF1A1A1A),
                  width: width,
                  padding: const EdgeInsets.all(20),
                  child: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(textScale),
                    ),
                    child: const SingleChildScrollView(
                      child: SpeechScrollControls(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).displayName, 'scroll-ui-loaded');
  }

  Slider slider(WidgetTester tester, String suffix) =>
      tester.widget<Slider>(find.byKey(ValueKey('speech-scroll-$suffix')));

  testWidgets(
    'two active sliders and separate reset buttons, no extra toggles',
    (tester) async {
      await showControls(tester);
      expect(find.byType(Slider), findsNWidgets(2));
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(IconButton), findsNWidgets(2));
      expect(slider(tester, 'smoothness').value, 0.5);
      expect(slider(tester, 'speed').value, 1);
      expect(slider(tester, 'smoothness').onChanged, isNotNull);
      expect(slider(tester, 'speed').onChanged, isNotNull);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('1.00x'), findsOneWidget);
    },
  );

  testWidgets(
    'dragging sliders changes persisted values live and independently',
    (tester) async {
      await showControls(tester);
      await tester.drag(
        find.byKey(const ValueKey('speech-scroll-smoothness')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      final smoothness =
          container.read(settingsProvider).speechScrollSmoothness;
      expect(smoothness, greaterThan(0.5));
      expect(container.read(settingsProvider).speechScrollSpeed, 1);
      await tester.drag(
        find.byKey(const ValueKey('speech-scroll-speed')),
        const Offset(50, 0),
      );
      await tester.pumpAndSettle();
      final speed = container.read(settingsProvider).speechScrollSpeed;
      expect(speed, greaterThan(1));
      expect(
        container.read(settingsProvider).speechScrollSmoothness,
        smoothness,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('speechScrollSmoothness'), smoothness);
      expect(prefs.getDouble('speechScrollSpeed'), speed);
    },
  );

  testWidgets(
    'each reset restores only its slider and survives closing/reopening',
    (tester) async {
      await showControls(tester);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setSpeechScrollSmoothness(0.8);
      await notifier.setSpeechScrollSpeed(1.8);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('speech-scroll-smoothness-reset')),
      );
      await tester.pumpAndSettle();
      expect(slider(tester, 'smoothness').value, 0.5);
      expect(slider(tester, 'speed').value, 1.8);
      await notifier.setSpeechScrollSmoothness(0.75);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speech-scroll-speed-reset')));
      await tester.pumpAndSettle();
      expect(slider(tester, 'speed').value, 1);
      expect(slider(tester, 'smoothness').value, 0.75);
      await tester.pumpWidget(const SizedBox());
      await showControls(tester);
      expect(slider(tester, 'smoothness').value, 0.75);
      expect(slider(tester, 'speed').value, 1);
    },
  );

  testWidgets('narrow panel and larger text do not overflow', (tester) async {
    await showControls(tester, width: 320, textScale: 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional rendered controls proof', (tester) async {
    await showControls(tester);
    if (Platform.environment['SCROLL_CONTROLS_PROOF'] != '1') return;
    final boundary =
        proofKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final proof = File(
        'test/deep_analysis/20261025_scroll_controls/final_proof.png',
      );
      await proof.parent.create(recursive: true);
      await proof.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
