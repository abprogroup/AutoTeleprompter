import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stt_log_replay_test.dart' as fixture;

void main() {
  fixture.Replay replay() => fixture.Replay(
    fixture.passage(10, 'the reader returns to the visible passage calmly'),
    10,
    10,
    18,
  );
  void health(fixture.Replay r, String type) => r.speech.onRuntimeHealth!(
    SttRuntimeHealth(type: type, listening: true, locale: 'en-US'),
  );

  testWidgets('network outage remains recoverable after repeated failures', (
    tester,
  ) async {
    final r = replay();
    addTearDown(r.close);
    for (var i = 0; i < 6; i++) {
      health(r, 'network');
      await tester.pump(const Duration(seconds: 2));
      final state = r.container.read(teleprompterProvider);
      expect(state.statusMessage, contains('Reconnecting'));
      expect(state.hasError, isFalse);
      expect(
        state.isListening,
        isTrue,
        reason: 'keep stop/session controls available',
      );
      expect(r.position, 10);
    }
  });

  testWidgets('readiness and microphone do not prove speech recovered', (
    tester,
  ) async {
    final r = replay();
    addTearDown(r.close);
    health(r, 'network');
    health(r, 'recognizerListening');
    r.speech.onStatusChange!(SpeechStatus.listening);
    r.speech.onSoundLevelChange!(0.9);
    health(r, 'heartbeat');
    expect(r.container.read(teleprompterProvider).statusMessage, isNotEmpty);
    health(r, 'networkAwaitingSpeech');
    expect(
      r.container.read(teleprompterProvider).statusMessage,
      contains('waiting for speech'),
    );
    expect(r.position, 10);
    health(r, 'productiveResult');
    expect(
      r.container.read(teleprompterProvider).statusMessage,
      contains('finding your place'),
    );
    expect(r.position, 10, reason: 'health is not movement evidence');
  });

  testWidgets(
    'offline hint, reconnect and stopped callbacks preserve position',
    (tester) async {
      final r = replay();
      addTearDown(r.close);
      health(r, 'networkOffline');
      expect(
        r.container.read(teleprompterProvider).statusMessage,
        contains('Offline'),
      );
      r.notifier.jumpToPosition(12);
      health(r, 'networkRecovering');
      expect(r.position, 12);
      await r.notifier.stopSession();
      health(r, 'network');
      health(r, 'networkAwaitingSpeech');
      health(r, 'productiveResult');
      expect(r.container.read(teleprompterProvider).statusMessage, isEmpty);
      expect(r.container.read(teleprompterProvider).isListening, isFalse);
      expect(r.position, 12);
    },
  );

  testWidgets('recovery does not relax visible-only alignment', (tester) async {
    final r = replay();
    addTearDown(r.close);
    health(r, 'network');
    health(r, 'networkAwaitingSpeech');
    r.notifier.setVisibleWordWindow(10, 12);
    r.hear('to the visible passage calmly', cumulative: true, streamId: 2);
    health(r, 'productiveResult');
    await tester.pump(const Duration(seconds: 2));
    expect(r.position, lessThanOrEqualTo(12));
  });

  testWidgets('fresh visible speech resumes after network recovery', (
    tester,
  ) async {
    final r = replay();
    addTearDown(r.close);
    health(r, 'network');
    health(r, 'networkAwaitingSpeech');
    r.hear(
      'reader returns to the visible passage',
      cumulative: true,
      streamId: 7,
    );
    health(r, 'productiveResult');
    await tester.pump(const Duration(seconds: 2));
    expect(r.position, 16);
    expect(r.container.read(teleprompterProvider).statusMessage, isEmpty);
    expect(r.container.read(teleprompterProvider).hasError, isFalse);
  });

  testWidgets('lost words catch up only from sufficient fresh visible evidence', (
    tester,
  ) async {
    final script = fixture.passage(
      10,
      'the reader pauses while a brief outage interrupts these words then returns '
      'to the visible passage calmly now',
    );
    final end = script.words.length - 1;
    final r = fixture.Replay(script, 10, 10, end);
    addTearDown(r.close);
    r.hear('reader pauses', cumulative: true);
    await tester.pump(const Duration(seconds: 2));
    final confirmed = r.position;
    health(r, 'network');
    await tester.pump(const Duration(seconds: 30));
    expect(r.position, confirmed, reason: 'outage cannot supply evidence');
    health(r, 'networkAwaitingSpeech');
    r.hear('returns', cumulative: true, streamId: 7);
    health(r, 'productiveResult');
    await tester.pump(const Duration(seconds: 2));
    expect(r.position, confirmed, reason: 'do not loosen profile threshold');
    expect(
      r.container.read(teleprompterProvider).statusMessage,
      contains('finding your place'),
    );
    r.hear('returns to the visible passage', cumulative: true, streamId: 7);
    health(r, 'productiveResult');
    await tester.pump(const Duration(seconds: 2));
    expect(
      r.position,
      script.words.indexWhere((word) => word.raw == 'passage'),
      reason: r.logs.join('\n'),
    );
    expect(r.container.read(teleprompterProvider).statusMessage, isEmpty);
    expect(r.logs.any((line) => line.contains('profile_visible_skip')), isTrue);
  });

  testWidgets(
    'real session heartbeat does not stop repeated network recovery',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final script = fixture.passage(
        10,
        'the reader returns to the visible passage calmly',
      );
      final r = fixture.Replay(script, 10, 10, 18);
      addTearDown(r.close);
      var started = false;
      final startup = r.notifier
          .startSession(script)
          .then((_) => started = true);
      for (var i = 0; i < 20 && !started; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(started, isTrue, reason: r.logs.join('\n'));
      await startup;
      r.notifier.reportEmbeddedSttHostLoaded();
      health(r, 'socketConnected');
      health(r, 'microphoneReady');
      health(r, 'recognizerListening');
      r.speech.onStatusChange!(SpeechStatus.listening);
      r.notifier.setVisibleWordWindow(10, 18);
      for (var i = 0; i < 8; i++) {
        health(r, 'network');
        health(r, 'heartbeat');
        await tester.pump(const Duration(seconds: 5));
        expect(r.container.read(teleprompterProvider).hasError, isFalse);
        expect(
          r.container.read(teleprompterProvider).statusMessage,
          contains('Reconnecting'),
        );
        expect(r.position, 10);
      }
      r.hear(
        'reader returns to the visible passage',
        cumulative: true,
        streamId: 8,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 16);
      await r.notifier.stopSession();
    },
  );

  testWidgets(
    'offline startup keeps local handshake alive without claiming ready',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final script = fixture.passage(
        10,
        'the reader returns to the visible passage calmly',
      );
      final r = fixture.Replay(script, 10, 10, 18);
      addTearDown(r.close);
      var started = false;
      final startup = r.notifier
          .startSession(script)
          .then((_) => started = true);
      for (var i = 0; i < 20 && !started; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(started, isTrue);
      await startup;
      r.notifier.reportEmbeddedSttHostLoaded();
      health(r, 'socketConnected');
      health(r, 'microphoneReady');
      health(r, 'networkOffline');
      for (var i = 0; i < 12; i++) {
        health(r, 'heartbeat');
        await tester.pump(const Duration(seconds: 5));
        final state = r.container.read(teleprompterProvider);
        expect(state.hasError, isFalse);
        expect(state.isStarting, isTrue);
        expect(state.isListening, isFalse);
        expect(state.statusMessage, contains('Offline'));
        expect(r.position, 10);
      }
      health(r, 'networkRecovering');
      health(r, 'recognizerListening');
      r.speech.onStatusChange!(SpeechStatus.listening);
      health(r, 'networkAwaitingSpeech');
      r.notifier.setVisibleWordWindow(10, 18);
      r.hear(
        'reader returns to the visible passage',
        cumulative: true,
        streamId: 8,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 16);
      expect(r.container.read(teleprompterProvider).statusMessage, isEmpty);
      await r.notifier.stopSession();
    },
  );

  testWidgets('fatal microphone error outranks late connection notices', (
    tester,
  ) async {
    final r = replay();
    addTearDown(r.close);
    health(r, 'network');
    r.speech.onError!('Microphone blocked');
    health(r, 'networkRecovering');
    health(r, 'networkAwaitingSpeech');
    health(r, 'productiveResult');
    expect(r.container.read(teleprompterProvider).hasError, isTrue);
    expect(
      r.container.read(teleprompterProvider).statusMessage,
      'Microphone blocked',
    );
    expect(r.position, 10);
  });
}
