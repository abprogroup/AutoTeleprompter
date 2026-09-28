import 'package:autoteleprompter/platform/webview2/webview2_runtime_bootstrap.dart';
import 'package:autoteleprompter/platform/webview2/webview2_runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebView2RuntimeConfig', () {
    test('pins hidden STT to the qualified legacy speech service', () {
      final arguments = WebView2RuntimeConfig.localSttArguments;

      expect(
        arguments,
        contains('--disable-features=msSpeechRecognitionServiceUseCetoService'),
      );
      expect(arguments, isNot(contains('--enable-features=')));
      expect('--disable-features='.allMatches(arguments), hasLength(1));
    });

    test('retains every authenticated loopback STT origin', () {
      final arguments = WebView2RuntimeConfig.localSttArguments;

      for (var port = 8082; port <= 8092; port++) {
        expect(arguments, contains('http://localhost:$port'));
      }
      expect(arguments, contains('--use-fake-ui-for-media-stream'));
      expect(arguments, contains('--autoplay-policy=no-user-gesture-required'));
    });
  });

  group('WebView2RuntimeBootstrap.decide', () {
    test('uses the verified Evergreen 152 family directly', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: '152.0.4191.66',
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.invalid,
        evergreenQuarantined: false,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.evergreen);
      expect(decision.reason, WebView2RuntimeSelectionReason.verifiedEvergreen);
      expect(decision.requiresCompatibilityRuntime, isFalse);
    });

    test('uses bundled Fixed for the known-bad newer Evergreen family', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: '153.0.4234.32',
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.available,
        evergreenQuarantined: false,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.bundledFixed);
      expect(
        decision.reason,
        WebView2RuntimeSelectionReason.evergreenUnverified,
      );
      expect(decision.requiresCompatibilityRuntime, isTrue);
    });

    test('uses bundled Fixed for an unknown future Evergreen family', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: '199.0.9999.1',
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.available,
        evergreenQuarantined: false,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.bundledFixed);
      expect(
        decision.reason,
        WebView2RuntimeSelectionReason.evergreenUnverified,
      );
      expect(decision.requiresCompatibilityRuntime, isTrue);
    });

    test('uses bundled Fixed when Evergreen is missing', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: null,
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.available,
        evergreenQuarantined: false,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.bundledFixed);
      expect(decision.reason, WebView2RuntimeSelectionReason.evergreenMissing);
      expect(decision.requiresCompatibilityRuntime, isTrue);
    });

    test('uses bundled Fixed when verified Evergreen is quarantined', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: '152.0.4191.66',
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.available,
        evergreenQuarantined: true,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.bundledFixed);
      expect(
        decision.reason,
        WebView2RuntimeSelectionReason.evergreenQuarantined,
      );
      expect(decision.requiresCompatibilityRuntime, isTrue);
    });

    test('fails closed when a required Fixed runtime is missing', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: '153.0.4234.32',
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.missing,
        evergreenQuarantined: false,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.unavailable);
      expect(
        decision.reason,
        WebView2RuntimeSelectionReason.bundledFixedUnavailable,
      );
      expect(decision.requiresCompatibilityRuntime, isTrue);
    });

    test('fails closed when a required Fixed runtime is invalid', () {
      final decision = WebView2RuntimeBootstrap.decide(
        installedEvergreenVersion: '153.0.4234.32',
        fixedRuntimeStatus: WebView2FixedRuntimeStatus.invalid,
        evergreenQuarantined: false,
      );

      expect(decision.preferredMode, WebView2RuntimeMode.unavailable);
      expect(
        decision.reason,
        WebView2RuntimeSelectionReason.bundledFixedInvalid,
      );
      expect(decision.requiresCompatibilityRuntime, isTrue);
    });
  });
}
