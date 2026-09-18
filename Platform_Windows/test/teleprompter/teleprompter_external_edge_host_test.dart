import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/platform/stt/stt_host_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('external Edge STT host policy', () {
    test('Smart uses offline Whisper only after the Chrome tier stops', () {
      expect(
        shouldStartOfflineWhisperFallback(
          mode: WindowsSttHostMode.smart,
          failedHost: WindowsSttBrowserHost.externalChrome,
          action: WindowsSttHostAction.stop,
        ),
        isTrue,
      );
      expect(
        shouldStartOfflineWhisperFallback(
          mode: WindowsSttHostMode.smart,
          failedHost: WindowsSttBrowserHost.externalEdge,
          action: WindowsSttHostAction.stop,
        ),
        isFalse,
      );
      expect(
        shouldStartOfflineWhisperFallback(
          mode: WindowsSttHostMode.smart,
          failedHost: WindowsSttBrowserHost.embeddedWebView2,
          action: WindowsSttHostAction.switchHost,
        ),
        isFalse,
      );
    });

    test('selects external Chrome only for the explicit Chrome option', () {
      expect(
        usesExternalChromeSttHost(AppSettings.sttEngineBrowserExternalChrome),
        isTrue,
      );
      expect(usesExternalChromeSttHost(AppSettings.sttEngineAuto), isFalse);
      expect(
        usesExternalChromeSttHost(AppSettings.sttEngineBrowserExternalEdge),
        isFalse,
      );
    });

    test(
      'selects external Edge only for the explicit compatibility option',
      () {
        expect(
          usesExternalEdgeSttHost(AppSettings.sttEngineBrowserExternalEdge),
          isTrue,
        );
        expect(usesExternalEdgeSttHost(AppSettings.sttEngineAuto), isFalse);
        expect(
          usesExternalEdgeSttHost(AppSettings.sttEngineBrowserOnline),
          isFalse,
        );
        expect(
          usesExternalEdgeSttHost(AppSettings.sttEngineWindowsOffline),
          isFalse,
        );
      },
    );

    test('keeps authenticated adapter URL out of embedded WebView state', () {
      const url = 'http://localhost:8082/?session=private-token';
      expect(
        embeddedSttWebViewUrlForHost(usesExternalEdge: true, adapterUrl: url),
        isNull,
      );
      expect(
        embeddedSttWebViewUrlForHost(usesExternalEdge: false, adapterUrl: url),
        url,
      );
    });

    test('launch failure tells the user how to restore embedded mode', () {
      final message = externalEdgeSttLaunchFailureMessage(
        'Microsoft Edge is not installed or could not be found.',
      );

      expect(message, contains('Smart compatibility'));
      expect(message, contains('Offline Whisper'));
      expect(message, contains('install Microsoft Edge'));
      expect(message, isNot(contains('localhost')));
    });

    test('disconnect fails immediately without waiting for retries', () {
      expect(
        externalEdgeRuntimeFailureReason(
          error: 'browser-disconnected',
          consecutiveNetworkFailures: 0,
        ),
        contains('disconnected'),
      );
    });

    test('network errors fail only at the bounded threshold', () {
      expect(
        externalEdgeRuntimeFailureReason(
          error: 'network',
          consecutiveNetworkFailures: externalEdgeNetworkFailureLimit - 1,
        ),
        isNull,
      );
      expect(
        externalEdgeRuntimeFailureReason(
          error: 'network',
          consecutiveNetworkFailures: externalEdgeNetworkFailureLimit,
        ),
        contains('network'),
      );
    });
  });
}
