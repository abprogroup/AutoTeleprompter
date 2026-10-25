// Synthetic equivalents of private speech-log regressions. Exact attachment
// replays remain local and are run separately before publication.
import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_consumed_speech_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_movement_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_tracking_state.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_transcript_buffer_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_visible_skip_context_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: true,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(3, 2),
  safetyRecovery: SttEvidenceThreshold(2, 1),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

Script passage(int prefix, String text) {
  final raw = '${List.filled(prefix, 'unrelated').join(' ')} $text';
  return Script(
    id: 'replay',
    title: 'Log replay',
    rawText: raw,
    words: WordAligner.tokenize(raw),
    isRtl: false,
    sessionId: 'replay',
  );
}

final firstLogScript = passage(
  469,
  'And we need to understand that Morgan did not switch from being Lead of '
  'the Crew to Lead of the Fleet. He becomes Lead of the fleet AS Lead '
  'of the Crew. His guidance flows through this office, through these '
  'workshops, through this plan. Not as a tradition that started 2000 '
  'years ago, but a solution and schedule planned from the beginning of work. '
  '${List.filled(20, 'unrelated').join(' ')}',
);

final secondLogScript = passage(
  668,
  'The studio has a separate path. Both lead to home.\n\n\nE1S19\n'
  "And make no mistake home's room is big enough for the entire fleet "
  'He cares about the worker in Santa New Marbella who has never heard '
  'the name of Cameron. He cares about the local artist in Red Rock '
  'who has never heard the schedule He cares about the chef in Riverton '
  'who is searching\n\nThe same pathway is the only way for all of them.\n'
  'E1S22\nThis should never move without speech.',
);

class ReplaySpeech extends AbstractSttService {
  @override
  String get platformName => 'Replay';
  @override
  bool get isListening => true;
  @override
  Future<SpeechStartResult> start({String? localeId}) async =>
      SpeechStartResult(success: true);
  @override
  Future<void> stop() async {}
}

class ReplaySettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(
    debugMode: true,
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

class Replay {
  final speech = ReplaySpeech();
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(ReplaySettings.new),
      teleprompterProvider.overrideWith(
        () => TeleprompterNotifier(browserSpeechService: speech),
      ),
    ],
  );
  TeleprompterNotifier get notifier =>
      container.read(teleprompterProvider.notifier);
  int get position => container.read(teleprompterProvider).confirmedWordIndex;
  List<String> get logs => container.read(teleprompterProvider).debugLogs;

  Replay(Script script, int position, int start, int end) {
    notifier.jumpToPosition(position, script: script);
    speech.onStatusChange!(SpeechStatus.listening);
    // Resolve the initial locale before delivering test speech.
    notifier.jumpToPosition(position);
    notifier.setVisibleWordWindow(start, end);
  }

  void hear(
    String text, {
    bool finalResult = false,
    bool cumulative = false,
    int streamId = 1,
  }) => speech.onResult!(
    SpeechResult(
      text,
      finalResult,
      isCumulative: cumulative,
      streamId: cumulative ? streamId : null,
    ),
  );
  Future<void> close() async {
    await notifier.stopSession();
    container.dispose();
  }
}

void main() {
  test('fixture positions match the two logs', () {
    expect(firstLogScript.words[512].raw, 'plan.');
    expect(firstLogScript.words[519].raw, '2000');
    expect(secondLogScript.words[677].raw, 'home.');
    expect(secondLogScript.words[681].raw, 'E1S19');
    expect(secondLogScript.words[704].raw, 'Marbella');
    expect(secondLogScript.words[750].raw, 'them.');
  });

  testWidgets(
    '49:48-50:04 consumed revision, numeric partials and aside recover',
    (tester) async {
      final r = Replay(firstLogScript, 502, 477, 532);
      r.hear('flows through this office through these workshops through this');
      await tester.pump(const Duration(seconds: 2));
      r.hear('this');
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.position, 511, reason: r.logs.join('\n'));
      r.hear(
        'flows through his office through these workshops through his plan',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(r.position, 512, reason: r.logs.join('\n'));
      r.hear(
        'flows through His office, through these workshops, through His plan.',
        finalResult: true,
      );
      expect(
        r.logs.any((line) => line.contains('already_confirmed_revision')),
        isTrue,
      );
      expect(
        r.logs.any((line) => line.contains('TRACK_RESET_OFF_SCRIPT')),
        isFalse,
      );
      for (final text in [
        'addition',
        'addition started',
        'addition started 2',
        'addition started 2000',
        'years ago',
        'years ago but',
        'years ago but a sol',
      ]) {
        r.hear(text);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, inInclusiveRange(521, 524), reason: r.logs.join('\n'));
      r.hear('planned from the beginning of work, so just a second.');
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 532, reason: r.logs.join('\n'));
      r.hear('yeah');
      r.hear('Yeah.', finalResult: true);
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 532);
      await r.close();
    },
  );

  for (final sample in [
    (677, 'The studio has a separate path. Both lead to home.'),
    (704, 'fleet he cares about the worker in santa new marbella'),
    (750, 'same pathway is the only way for all of them.'),
  ]) {
    testWidgets(
      'second log consumed revision at ${sample.$1} holds without reset',
      (tester) async {
        final r = Replay(
          secondLogScript,
          sample.$1,
          sample.$1 - 25,
          sample.$1 + 12,
        );
        r.hear(sample.$2, finalResult: true);
        await tester.pump(const Duration(seconds: 1));
        expect(r.position, sample.$1);
        expect(
          r.logs.any((line) => line.contains('already_confirmed_revision')),
          isTrue,
        );
        expect(
          r.logs.any((line) => line.contains('TRACK_RESET_OFF_SCRIPT')),
          isFalse,
        );
        await r.close();
      },
    );
  }

  testWidgets('57:21 proper-name completion does not stop following words', (
    tester,
  ) async {
    final r = Replay(secondLogScript, 695, 681, 740);
    r.hear('He cares about the worker in');
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 701, reason: r.logs.join('\n'));
    r.hear('fleet he cares about the worker in santa new marbel');
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 704, reason: r.logs.join('\n'));
    r.hear('fleet he cares about the worker in santa new marbella');
    r.hear('who');
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 705, reason: r.logs.join('\n'));
    r.hear('who has never heard');
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 708);
    await r.close();
  });

  testWidgets('57:37 backward scroll consumes prior cumulative speech only', (
    tester,
  ) async {
    final r = Replay(secondLogScript, 750, 723, 764);
    const old = 'same pathway is the only way for all of them';
    r.hear(old, cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 750);
    for (final index in [
      748,
      741,
      735,
      729,
      723,
      717,
      712,
      707,
      702,
      696,
      689,
      683,
      681,
    ]) {
      r.notifier.jumpToPosition(index);
    }
    r.notifier.setVisibleWordWindow(677, 716);
    r.hear('$old. is that', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 681);
    expect(r.logs.any((line) => line.contains('heard="is that"')), isTrue);
    r.hear('and make no mistake', cumulative: true, streamId: 2);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
    await r.close();
  });

  testWidgets('off-screen local and visible matches never advance', (
    tester,
  ) async {
    final r = Replay(firstLogScript, 512, 477, 512);
    r.hear('Not as a tradition that started 2000 years ago');
    await tester.pump(const Duration(seconds: 3));
    expect(r.position, 512);
    r.notifier.setVisibleWordWindow(null, null);
    r.hear('Not as a tradition');
    await tester.pump(const Duration(seconds: 3));
    expect(r.position, 512);
    await r.close();
  });

  testWidgets('viewport change cancels an already-qualified animation', (
    tester,
  ) async {
    final r = Replay(firstLogScript, 512, 477, 532);
    r.hear('planned from the beginning of work');
    r.notifier.setVisibleWordWindow(477, 512);
    await tester.pump(const Duration(seconds: 3));
    expect(r.position, 512);
    await r.close();
  });

  test('anchored numeric/word revisions replace instead of duplicate', () {
    const c = SttVisibleSkipContextService();
    for (final pair in [
      ('addition started 2', 'addition started 2000'),
      ('years ago but a sol', 'years ago but a solution'),
    ]) {
      expect(
        c.mergePendingTranscript(
          pendingTranscript: pair.$1,
          transcript: pair.$2,
        ),
        pair.$2,
      );
    }
    expect(
      c.mergePendingTranscript(
        pendingTranscript: 'addition started 20',
        transcript: 'unrelated sentence 22',
      ),
      'addition started 20 unrelated sentence 22',
    );
  });

  test('consumed guard never swallows fresh suffixes or unequal numbers', () {
    const c = SttConsumedSpeechService();
    expect(
      c.isConsumed(
        script: WordAligner.tokenize('very very clear'),
        confirmedIndex: 0,
        transcript: 'very',
      ),
      isFalse,
    );
    expect(
      c.isConsumed(
        script: firstLogScript.words,
        confirmedIndex: 519,
        transcript: 'started 20',
      ),
      isFalse,
    );
    expect(
      c.isConsumed(
        script: firstLogScript.words,
        confirmedIndex: 512,
        transcript: 'through this plan Not',
      ),
      isFalse,
    );
  });

  test('every candidate kind fails closed outside the actual viewport', () {
    for (final kind in SttAlignmentKind.values) {
      final result = const SttMovementPolicyService().evaluateCandidate(
        alignment: AlignmentResult(
          101,
          1,
          'test',
          SttAlignmentDecision.advance,
          kind,
          SttThresholdFamily.safetyRecovery,
          [],
          ['clear', 'words'],
          101,
          101,
        ),
        policy: profile,
        trackingState: SttEvidenceTrackingState.tracking,
        currentIndex: 100,
        advanceGuardIndex: 100,
        visibleSkipTargetTrusted: false,
        requireVisibleTarget: true,
        maxLocalAdvanceWithoutWait: 2,
      );
      expect(result.shouldBlock, isTrue, reason: kind.name);
      expect(result.reason, 'offscreen_target_blocked');
    }
  });

  test(
    'manual-scroll boundary suppresses final rewrites but accepts new appends',
    () {
      const buffer = SttTranscriptBufferService();
      final old = buffer.update(
        rawTranscript: 'same pathway is the only way',
        transcriptFloor: 0,
      );
      final revised = buffer.update(
        rawTranscript: 'same pathway is the ONLY road',
        transcriptFloor: old.spokenWords.length,
        cumulativeReplacement: true,
        cumulativeBaselineWords: old.spokenWords,
        cumulativeFinal: true,
        allowFinalTailReplay: false,
      );
      expect(revised.hasFreshSpeech, isFalse);
      final appended = buffer.update(
        rawTranscript: 'same pathway is the ONLY road and make no mistake',
        transcriptFloor: revised.transcriptFloor,
        cumulativeReplacement: true,
        cumulativeBaselineWords: revised.spokenWords,
        allowFinalTailReplay: false,
      );
      expect(appended.recentTranscript, 'and make no mistake');
    },
  );

  test('unmatched trailing words cannot satisfy a visible-skip threshold', () {
    const context = SttVisibleSkipContextService();
    final result = context.rescueAlignment(
      script: firstLogScript.words,
      pendingTranscript: 'years ago',
      transcript: 'years ago unrelated words',
      lastConfirmedIndex: 512,
      visibleSkipStartIndex: 477,
      maxSkipTargetIndex: 546,
      policy: profile,
    );
    expect(result, isNull);
  });

  test('partial numeric preservation refuses structured times and ranges', () {
    const context = SttVisibleSkipContextService();
    for (final text in [
      'addition started 20:00',
      'addition started 2-2000',
      'addition started 2 2000',
      'addition started 20.00',
    ]) {
      expect(
        context.preservationAlignment(
          script: firstLogScript.words,
          transcript: text,
          lastConfirmedIndex: 512,
          visibleSkipStartIndex: 477,
          maxSkipTargetIndex: 546,
          policy: profile,
        ),
        isNull,
        reason: text,
      );
    }
  });
}
