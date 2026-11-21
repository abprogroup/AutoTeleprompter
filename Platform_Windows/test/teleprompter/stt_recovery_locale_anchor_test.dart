// Combined real recovery policy/provider with a controllably delayed transport.
// No actual microphone, cloud service, or native browser is exercised here.
import 'dart:async';

import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/models/alignment_result.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stt_log_replay_test.dart' as fixture;

void main() {
  for (final firstEvent in ['listening', 'result']) {
    testWidgets('scroll committed during recovery reconciles locale before '
        '$firstEvent', (tester) async {
      final h = _Harness(tester);
      addTearDown(h.close);
      await h.start();
      await h.holdRecovery();
      h.notifier.finishManualScroll(h.anchor, script: h.script);
      h.notifier.setVisibleWordWindow(h.anchor, h.script.words.length - 1);
      await h.releaseRecovery();
      if (firstEvent == 'result') {
        h.speech.hear('and make no mistake');
      } else {
        h.speech.onStatusChange!(SpeechStatus.listening);
      }
      await tester.pump();
      expect(h.speech.locales, ['he_IL'], reason: h.logs);
      expect(h.state.confirmedWordIndex, h.anchor, reason: h.logs);
      // Readiness alone cannot move. Duplicate readiness must not reset floors.
      h.speech.onStatusChange!(SpeechStatus.listening);
      h.speech.onStatusChange!(SpeechStatus.listening);
      expect(h.speech.locales, ['he_IL']);
      h.speech.hear('משפט חשוב מאוד');
      await tester.pump(const Duration(seconds: 1));
      expect(h.state.confirmedWordIndex, h.anchor + 3, reason: h.logs);
      await h.close();
    });
  }

  testWidgets(
    'still-held recovery does not switch locale until gesture settles',
    (tester) async {
      final h = _Harness(tester);
      addTearDown(h.close);
      await h.start();
      await h.holdRecovery();
      await h.releaseRecovery();
      h.speech.onStatusChange!(SpeechStatus.listening);
      expect(h.speech.locales, isEmpty);
      expect(h.notifier.manualScrollInProgress, isTrue);
      h.notifier.finishManualScroll(h.anchor, script: h.script);
      expect(h.speech.locales, ['he_IL']);
      await h.close();
    },
  );

  testWidgets(
    'recovery without navigation preserves explicitly selected language',
    (tester) async {
      final h = _Harness(tester, forcedEnglish: true);
      addTearDown(h.close);
      await h.start();
      await h.holdRecovery();
      h.notifier.finishManualScroll(
        h.state.confirmedWordIndex,
        script: h.script,
      );
      await h.releaseRecovery();
      h.speech.onStatusChange!(SpeechStatus.listening);
      expect(h.speech.locales, isEmpty);
      expect(h.speech.startedLocales, ['en_US', 'en_US']);
      await h.close();
    },
  );

  testWidgets(
    'stop during held recovery invalidates late locale reconciliation',
    (tester) async {
      final h = _Harness(tester);
      addTearDown(h.close);
      await h.start();
      await h.holdRecovery();
      h.notifier.finishManualScroll(h.anchor, script: h.script);
      final stopped = h.notifier.stopSession();
      h.speech.releaseStop();
      await _pumpUntil(tester, () => !h.state.isStarting);
      await stopped;
      h.speech.onStatusChange!(SpeechStatus.listening);
      h.speech.hear('and make no mistake');
      expect(h.speech.locales, isEmpty);
      expect(h.speech.startedLocales, hasLength(1));
      expect(h.state.isListening, isFalse);
      expect(h.state.confirmedWordIndex, h.anchor);
      await h.close();
    },
  );

  testWidgets('failed first retry preserves the original moved-anchor fence', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    await h.start();
    await h.holdRecovery();
    h.notifier.finishManualScroll(h.anchor, script: h.script);
    h.speech.failNextStart = true;
    h.speech.releaseStop();
    await _pumpUntil(tester, () => h.speech.startedLocales.length == 3);
    await tester.pump();
    h.speech.onStatusChange!(SpeechStatus.listening);
    expect(h.speech.locales, ['he_IL'], reason: h.logs);
    expect(h.state.confirmedWordIndex, h.anchor);
    await h.close();
  });

  testWidgets('replacement script cannot inherit a pending recovery anchor', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    await h.start();
    await h.holdRecovery();
    final replacement = fixture.passage(
      0,
      'different opening words before this cue התחלה משפט חדש אחרון',
    );
    h.notifier.jumpToPosition(h.state.confirmedWordIndex, script: replacement);
    await h.releaseRecovery();
    h.speech.onStatusChange!(SpeechStatus.listening);
    expect(
      h.speech.locales,
      isEmpty,
      reason: 'retired script identity is not a new script locale decision',
    );
    await h.close();
  });

  testWidgets('dispose while recovery is held cannot request a late locale', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await h.holdRecovery();
    h.notifier.finishManualScroll(h.anchor, script: h.script);
    h.container.dispose();
    h.speech.releaseStop();
    await tester.pump();
    h.speech.onStatusChange!(SpeechStatus.listening);
    h.speech.hear('and make no mistake');
    expect(h.speech.locales, isEmpty);
    expect(h.speech.startedLocales, hasLength(1));
  });
}

class _DelayedSpeech extends AbstractSttService {
  final startedLocales = <String?>[];
  final locales = <String>[];
  Completer<void>? blockedStop;
  bool stopEntered = false;
  bool failNextStart = false;
  @override
  bool get isListening => true;
  @override
  String get platformName => 'Delayed recovery transport';
  @override
  String? get sttWebViewUrl => 'http://localhost:8082/?session=test';
  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    startedLocales.add(localeId);
    if (failNextStart) {
      failNextStart = false;
      return SpeechStartResult(
        success: false,
        message: 'Synthetic retry failure',
      );
    }
    return SpeechStartResult(success: true);
  }

  @override
  Future<void> stop() async {
    final pending = blockedStop;
    if (pending != null) {
      stopEntered = true;
      await pending.future;
    }
  }

  @override
  void setLocale(String locale) => locales.add(locale);
  void releaseStop() {
    final pending = blockedStop;
    blockedStop = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void hear(String words, {int stream = 7}) => onResult!(
    SpeechResult(words, false, isCumulative: true, streamId: stream),
  );
  void health(String type) => onRuntimeHealth!(
    SttRuntimeHealth(type: type, listening: true, locale: 'en-US'),
  );
}

class _Settings extends fixture.ReplaySettings {
  _Settings(this.forcedEnglish);
  final bool forcedEnglish;
  @override
  AppSettings build() => super.build().copyWith(
    languageMode:
        forcedEnglish
            ? AppSettings.languageModeEnglish
            : AppSettings.languageModeAuto,
  );
}

class _Harness {
  _Harness(this.tester, {this.forcedEnglish = false});
  final WidgetTester tester;
  final bool forcedEnglish;
  bool _closed = false;
  final speech = _DelayedSpeech();
  final script = fixture.passage(
    0,
    'Opening and make no mistake ending. תחילת משפט חשוב מאוד '
    'and make no mistake final.',
  );
  late final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _Settings(forcedEnglish)),
      teleprompterProvider.overrideWith(
        () => TeleprompterNotifier(browserSpeechService: speech),
      ),
    ],
  );
  TeleprompterNotifier get notifier =>
      container.read(teleprompterProvider.notifier);
  TeleprompterState get state => container.read(teleprompterProvider);
  String get logs => state.debugLogs.join('\n');
  int get anchor => script.words.indexWhere((word) => word.raw == 'תחילת');

  Future<void> start() async {
    SharedPreferences.setMockInitialValues({});
    var started = false;
    final startup = notifier.startSession(script).then((_) => started = true);
    await _pumpUntil(tester, () => started);
    await startup;
    notifier.reportEmbeddedSttHostLoaded();
    for (final phase in [
      'socketConnected',
      'microphoneReady',
      'recognizerListening',
    ]) {
      speech.health(phase);
    }
    speech.onStatusChange!(SpeechStatus.listening);
    notifier.jumpToPosition(0);
    notifier.setVisibleWordWindow(0, anchor - 1);
    speech.hear('and make no mistake', stream: 5);
    await tester.pump(const Duration(seconds: 1));
    speech.locales.clear();
    expect(state.isListening, isTrue, reason: logs);
  }

  Future<void> holdRecovery() async {
    expect(notifier.beginManualScroll(), isTrue);
    speech.blockedStop = Completer<void>();
    notifier.reportEmbeddedSttHostFailure(reasonCode: 'webview-load-failed');
    await _pumpUntil(tester, () => speech.stopEntered);
    expect(state.isStarting, isTrue);
    expect(state.isListening, isFalse);
  }

  Future<void> releaseRecovery() async {
    speech.releaseStop();
    await _pumpUntil(tester, () => speech.startedLocales.length == 2);
    await tester.pump();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    speech.releaseStop();
    await notifier.stopSession();
    container.dispose();
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 40 && !predicate(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: 'expected recovery stage did not arrive');
}
