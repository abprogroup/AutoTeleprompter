// Real authenticated adapter -> real provider. Browser events are synthetic;
// this verifies transcript/position ownership, not microphone/network quality.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../teleprompter/stt_log_replay_test.dart' as fixture;

void main() {
  for (final restartAdapter in [false, true]) {
    for (final visible in [true, false]) {
      testWidgets(
        '${restartAdapter ? 'host recovery' : 'page replacement'} after manual '
        'jump ${visible ? 'accepts fresh speech' : 'cannot jump off-screen'}',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final adapter = SttBrowserAdapter();
          final container = ProviderContainer(
            overrides: [
              settingsProvider.overrideWith(fixture.ReplaySettings.new),
              teleprompterProvider.overrideWith(
                () => TeleprompterNotifier(browserSpeechService: adapter),
              ),
            ],
          );
          final notifier = container.read(teleprompterProvider.notifier);
          final sockets = <WebSocket>[];
          final subscriptions = <StreamSubscription<dynamic>>[];
          addTearDown(() async {
            await tester.runAsync(() async {
              await notifier.stopSession();
              for (final socket in sockets) {
                await socket.close();
              }
              for (final subscription in subscriptions) {
                await subscription.cancel();
              }
              await adapter.stop();
            });
            container.dispose();
          });
          var received = 0;
          final originalOnResult = adapter.onResult!;
          adapter.onResult = (result) {
            originalOnResult(result);
            received++;
          };
          int position() =>
              container.read(teleprompterProvider).confirmedWordIndex;
          String logs() =>
              container.read(teleprompterProvider).debugLogs.join('\n');

          Future<WebSocket> connect() async {
            final uri = Uri.parse(adapter.sttWebViewUrl!);
            final socket = await WebSocket.connect(
              uri.replace(scheme: 'ws', path: '/ws').toString(),
              headers: {'Origin': uri.origin},
            );
            sockets.add(socket);
            subscriptions.add(
              socket.listen((message) {
                if ((jsonDecode(message as String) as Map)['type'] == 'close') {
                  socket.add(jsonEncode({'type': 'closeAck'}));
                }
              }),
            );
            return socket;
          }

          Future<void> hear(WebSocket socket, String text) async {
            final expected = received + 1;
            socket.add(
              jsonEncode({
                'type': 'result',
                'words': text,
                'isFinal': false,
                'isCumulative': true,
                'streamId': 1,
              }),
            );
            await _waitFor(() => received == expected);
          }

          notifier.jumpToPosition(750, script: fixture.secondLogScript);
          final first = await tester.runAsync(() async {
            expect((await adapter.start(localeId: 'en-US')).success, isTrue);
            final socket = await connect();
            socket.add(jsonEncode({'type': 'listening'}));
            await _waitFor(
              () => container.read(teleprompterProvider).isListening,
            );
            return socket;
          });
          notifier.jumpToPosition(750);
          notifier.setVisibleWordWindow(723, 764);
          await tester.runAsync(
            () => hear(first!, 'same pathway is the only way for all of them'),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(position(), 750, reason: logs());
          notifier.jumpToPosition(681);
          notifier.setVisibleWordWindow(677, visible ? 716 : 681);

          await tester.runAsync(() async {
            if (restartAdapter) {
              expect((await adapter.start(localeId: 'en-US')).success, isTrue);
            }
            final replacement = await connect();
            await hear(replacement, 'and make no mistake');
            // These callbacks originate in the real socket zone; give their
            // bounded visual confirmation timer time to settle as well.
            await Future<void>.delayed(const Duration(seconds: 1));
          });
          await tester.pump(const Duration(seconds: 1));
          expect(position(), visible ? 686 : 681, reason: logs());
          expect(container.read(teleprompterProvider).hasError, isFalse);
        },
      );
    }
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Browser event missing');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
