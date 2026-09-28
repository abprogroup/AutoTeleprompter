import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/platform/stt/stt_host_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('current-release speech-host boundary', () {
    test('persisted settings only retry and stop the embedded host', () async {
      const persistedValues = <String?>[
        null,
        AppSettings.sttEngineAuto,
        AppSettings.sttEngineWindowsOffline,
        AppSettings.sttEngineBrowserOnline,
        AppSettings.sttEngineBrowserExternalEdge,
        AppSettings.sttEngineBrowserExternalChrome,
        AppSettings.sttEngineBrowserSmartCompatibility,
        AppSettings.sttEngineWhisperTiny,
        AppSettings.sttEngineWhisperBase,
        AppSettings.sttEngineWhisperSmall,
        AppSettings.sttEngineWhisperMedium,
        'google',
        'unexpected',
      ];

      for (final value in persistedValues) {
        final mode = WindowsSttHostMode.fromSetting(value);
        final policy = await WindowsSttHostPolicy.resolve(
          mode: mode,
          webView2RuntimeVersion: '153.0.4234.32',
          embeddedRecoveryBudget: 1,
        );
        expect(mode, WindowsSttHostMode.smart);
        expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
        expect(
          (await policy.handleFailure(
            failedHost: WindowsSttBrowserHost.embeddedWebView2,
          )).action,
          WindowsSttHostAction.retry,
        );
        expect(
          (await policy.handleFailure(
            failedHost: WindowsSttBrowserHost.embeddedWebView2,
          )).action,
          WindowsSttHostAction.stop,
        );
      }
    });

    test('no persisted setting selects an external browser host', () {
      const persistedValues = <String?>[
        null,
        AppSettings.sttEngineAuto,
        AppSettings.sttEngineWindowsOffline,
        AppSettings.sttEngineBrowserOnline,
        AppSettings.sttEngineBrowserExternalEdge,
        AppSettings.sttEngineBrowserExternalChrome,
        AppSettings.sttEngineBrowserSmartCompatibility,
        AppSettings.sttEngineWhisperTiny,
        AppSettings.sttEngineWhisperBase,
        AppSettings.sttEngineWhisperSmall,
        AppSettings.sttEngineWhisperMedium,
        'google',
        'unexpected',
      ];

      for (final value in persistedValues) {
        expect(
          usesExternalEdgeSttHost(value),
          isFalse,
          reason: 'Persisted setting "$value" must not launch Edge.',
        );
        expect(
          usesExternalChromeSttHost(value),
          isFalse,
          reason: 'Persisted setting "$value" must not launch Chrome.',
        );
      }
    });

    test('every persisted setting keeps STT in the embedded WebView', () {
      const url = 'http://localhost:8082/?session=private-token';
      const persistedValues = <String?>[
        null,
        AppSettings.sttEngineAuto,
        AppSettings.sttEngineWindowsOffline,
        AppSettings.sttEngineBrowserOnline,
        AppSettings.sttEngineBrowserExternalEdge,
        AppSettings.sttEngineBrowserExternalChrome,
        AppSettings.sttEngineBrowserSmartCompatibility,
        AppSettings.sttEngineWhisperTiny,
        AppSettings.sttEngineWhisperBase,
        'google',
        'unexpected',
      ];

      for (final value in persistedValues) {
        final usesExternalBrowser =
            usesExternalEdgeSttHost(value) || usesExternalChromeSttHost(value);
        expect(
          embeddedSttWebViewUrlForHost(
            usesExternalEdge: usesExternalBrowser,
            adapterUrl: url,
          ),
          url,
          reason: 'Persisted setting "$value" must keep the in-app URL.',
        );
      }
    });
  });
}
