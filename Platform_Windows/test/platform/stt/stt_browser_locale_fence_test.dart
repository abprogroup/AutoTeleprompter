// Actual authenticated socket + actual provider; no live microphone claims.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../teleprompter/stt_log_replay_test.dart' as fixture;

void main() {
  test('locale switch rejects queued speech before first result and after '
      'switching back to the same language', () async {
    final h = _BrowserHarness();
    addTearDown(h.close);
    await h.start();
    final socket = await h.connect();
    final firstRevision = h.revision;
    h.adapter.setLocale('he_IL');
    await h.waitForLocale('he-IL');
    h.result(socket, 'queued before first result', revision: firstRevision);
    h.result(socket, 'untagged old page', revision: null);
    h.result(socket, 'current Hebrew', revision: h.revision, generation: 3);
    await h.flush(socket);
    expect(h.results.map((r) => r.words), ['current Hebrew']);

    h.adapter.setLocale('en_US');
    await h.waitForLocale('en-US');
    final currentRevision = h.revision;
    h.result(
      socket,
      'retired English with larger generation',
      revision: firstRevision,
      generation: 99,
    );
    h.result(socket, 'fresh English', revision: currentRevision, generation: 5);
    await h.flush(socket);
    expect(h.results.map((r) => r.words), ['current Hebrew', 'fresh English']);
    expect(h.health.where((type) => type == 'productiveResult'), hasLength(2));
  });

  test(
    'new socket receives pending locale and rejects obsolete bootstrap',
    () async {
      final h = _BrowserHarness();
      addTearDown(h.close);
      await h.start();
      await h.connect();
      final oldRevision = h.revision;
      h.adapter.setLocale('he-IL');
      await h.waitForLocale('he-IL');
      final requestedRevision = h.revision;
      final configsBefore = h.commands.length;
      final replacement = await h.connect();
      await h.flush(replacement);
      expect(
        h.commands.skip(configsBefore),
        contains(containsPair('configurationRevision', requestedRevision)),
      );
      h.result(replacement, 'stale fetched page', revision: oldRevision);
      h.result(replacement, 'legacy during transition', revision: null);
      h.result(replacement, 'new page new locale', revision: requestedRevision);
      await h.flush(replacement);
      expect(h.results.map((r) => r.words), ['new page new locale']);
    },
  );

  test(
    'tagged pages cannot downgrade to malformed or missing revision',
    () async {
      final h = _BrowserHarness();
      addTearDown(h.close);
      await h.start();
      final socket = await h.connect();
      h.result(socket, 'valid', revision: h.revision);
      for (final invalid in [null, -1, 0, 1.5, '1']) {
        h.result(socket, 'invalid', revision: invalid);
      }
      await h.flush(socket);
      expect(h.results.map((r) => r.words), ['valid']);
    },
  );

  test(
    'host restart does not accept a retired configuration revision',
    () async {
      final h = _BrowserHarness();
      addTearDown(h.close);
      await h.start();
      final retiredUrl = Uri.parse(h.adapter.sttWebViewUrl!);
      await h.connect();
      final oldRevision = h.revision;
      h.adapter.setLocale('he-IL');
      await h.waitForLocale('he-IL');
      await h.start();
      expect(h.revision, greaterThan(oldRevision));
      await expectLater(
        WebSocket.connect(
          retiredUrl.replace(scheme: 'ws', path: '/ws').toString(),
          headers: {'Origin': retiredUrl.origin},
        ),
        throwsA(isA<WebSocketException>()),
      );
      final socket = await h.connect();
      h.result(socket, 'retired host text', revision: oldRevision);
      h.result(socket, 'fresh host text', revision: h.revision);
      await h.flush(socket);
      expect(h.results.map((r) => r.words), ['fresh host text']);
    },
  );

  test('a result that switches locale cannot mark the new configuration '
      'productive before its own speech arrives', () async {
    final h = _BrowserHarness();
    addTearDown(h.close);
    await h.start();
    final socket = await h.connect();
    h.adapter.onResult = (result) {
      h.results.add(result);
      h.adapter.setLocale('he-IL');
    };
    h.result(socket, 'valid old-locale boundary', revision: h.revision);
    await h.flush(socket);
    expect(h.results, hasLength(1));
    expect(h.health, isNot(contains('productiveResult')));
  });

  test(
    'readiness that switches locale cannot acknowledge the new recognizer',
    () async {
      final h = _BrowserHarness();
      addTearDown(h.close);
      await h.start();
      final socket = await h.connect();
      h.adapter.onStatusChange = (status) {
        if (status == SpeechStatus.listening) h.adapter.setLocale('he-IL');
      };
      socket.add(
        jsonEncode({
          'type': 'lifecycle',
          'phase': 'recognizerListening',
          'configurationRevision': h.revision,
        }),
      );
      await h.flush(socket);
      expect(h.health, isNot(contains('recognizerListening')));
      await h.waitForLocale('he-IL');
      socket.add(
        jsonEncode({
          'type': 'lifecycle',
          'phase': 'recognizerListening',
          'configurationRevision': h.revision,
        }),
      );
      await h.flush(socket);
      expect(
        h.health.where((type) => type == 'recognizerListening'),
        hasLength(1),
      );
    },
  );

  testWidgets('manual bilingual scroll drops old locale snapshot then accepts '
      'fresh speech at the new visible anchor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final h = _BrowserHarness();
    final script = fixture.passage(
      0,
      'Opening and make no mistake ending. תחילת משפט חשוב מאוד '
      'and make no mistake final.',
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(fixture.ReplaySettings.new),
        teleprompterProvider.overrideWith(
          () => TeleprompterNotifier(browserSpeechService: h.adapter),
        ),
      ],
    );
    final notifier = container.read(teleprompterProvider.notifier);
    final providerResult = h.adapter.onResult!;
    h.adapter.onResult = (result) {
      h.results.add(result);
      providerResult(result);
    };
    final providerLevel = h.adapter.onSoundLevelChange;
    h.adapter.onSoundLevelChange = (level) {
      h.flushed++;
      providerLevel?.call(level);
    };
    addTearDown(() async {
      await tester.runAsync(() async {
        await notifier.stopSession();
        await h.close();
      });
      container.dispose();
    });
    final anchor = script.words.indexWhere((word) => word.raw == 'תחילת');
    int position() => container.read(teleprompterProvider).confirmedWordIndex;
    String logs() => container.read(teleprompterProvider).debugLogs.join('\n');
    notifier.jumpToPosition(anchor - 1, script: script);
    final socket = await tester.runAsync(() async {
      await h.start();
      final socket = await h.connect();
      socket.add(jsonEncode({'type': 'listening'}));
      await _waitFor(() => container.read(teleprompterProvider).isListening);
      return socket;
    });
    notifier.jumpToPosition(anchor - 1);
    notifier.setVisibleWordWindow(0, anchor - 1);
    await tester.runAsync(() async {
      h.result(socket!, 'and make no mistake', revision: h.revision);
      await h.flush(socket);
    });
    await tester.pump(const Duration(seconds: 1));
    final oldRevision = h.revision;
    notifier.beginManualScroll();
    notifier.setVisibleWordWindow(anchor, script.words.length - 1);
    notifier.finishManualScroll(anchor, script: script);
    final before = h.results.length;
    await tester.runAsync(() async {
      await h.waitForLocale('he-IL');
      // Already queued in the old recognizer before its locale command arrives.
      h.result(socket!, 'and make no mistake', revision: oldRevision);
      await h.flush(socket);
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump(const Duration(seconds: 1));
    expect(position(), anchor, reason: logs());
    expect(
      h.results.length,
      before,
      reason: 'old locale must never reach a provider whose floor was reset',
    );
    await tester.runAsync(() async {
      h.result(socket!, 'משפט חשוב מאוד', revision: h.revision, generation: 3);
      await h.flush(socket);
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump(const Duration(seconds: 1));
    expect(position(), anchor + 3, reason: logs());
  });
}

class _BrowserHarness {
  final adapter = SttBrowserAdapter();
  final results = <SpeechResult>[];
  final commands = <Map<String, dynamic>>[];
  final health = <String>[];
  final sockets = <WebSocket>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  int revision = 1;
  int flushed = 0;

  _BrowserHarness() {
    adapter.onResult = results.add;
    adapter.onRuntimeHealth = (event) => health.add(event.type);
    adapter.onSoundLevelChange = (_) => flushed++;
  }

  Future<void> start() async {
    expect((await adapter.start(localeId: 'en-US')).success, isTrue);
    // This file also has testWidgets: bypass only its fake HTTP client for our
    // authenticated localhost server, without changing any global override.
    final client = _LoopbackHttp().createHttpClient(null);
    try {
      final response =
          await (await client.getUrl(
            Uri.parse(adapter.sttWebViewUrl!),
          )).close();
      expect(response.statusCode, HttpStatus.ok);
      final html = await utf8.decoder.bind(response).join();
      revision =
          int.tryParse(
            RegExp(
                  r'let configurationRevision = (\d+);',
                ).firstMatch(html)?.group(1) ??
                '',
          ) ??
          1;
    } finally {
      client.close(force: true);
    }
  }

  Future<WebSocket> connect() async {
    final uri = Uri.parse(adapter.sttWebViewUrl!);
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '/ws').toString(),
      headers: {'Origin': uri.origin},
    );
    sockets.add(socket);
    subscriptions.add(
      socket.listen((message) {
        final command = jsonDecode(message as String) as Map<String, dynamic>;
        commands.add(command);
        if (command['type'] == 'close') {
          socket.add(jsonEncode({'type': 'closeAck'}));
        }
      }),
    );
    return socket;
  }

  Future<void> waitForLocale(String locale) async {
    await _waitFor(
      () => commands.any(
        (c) =>
            c['type'] == 'setLocale' &&
            c['locale'] == locale &&
            (c['configurationRevision'] == null ||
                (c['configurationRevision'] as int) > revision),
      ),
    );
    final command = commands.lastWhere(
      (c) => c['type'] == 'setLocale' && c['locale'] == locale,
    );
    revision = command['configurationRevision'] as int? ?? revision + 1;
  }

  void result(
    WebSocket socket,
    String words, {
    required Object? revision,
    int generation = 1,
  }) {
    socket.add(
      jsonEncode({
        'type': 'result',
        'words': words,
        'isCumulative': true,
        'streamId': generation,
        if (revision != null) 'configurationRevision': revision,
      }),
    );
  }

  Future<void> flush(WebSocket socket) async {
    final expected = flushed + 1;
    socket.add(jsonEncode({'type': 'level', 'level': 0.25}));
    await _waitFor(() => flushed >= expected);
  }

  Future<void> close() async {
    await adapter.stop();
    for (final socket in sockets) {
      await socket.close();
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

class _LoopbackHttp extends HttpOverrides {}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Browser event missing');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
