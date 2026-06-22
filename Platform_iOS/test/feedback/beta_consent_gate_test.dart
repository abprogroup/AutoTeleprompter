import 'package:autoteleprompter/features/feedback/providers/beta_consent_provider.dart';
import 'package:autoteleprompter/features/feedback/widgets/beta_consent_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows mobile privacy and permission consent areas',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          betaConsentProvider.overrideWith(_ReadyConsentNotifier.new),
        ],
        child: const MaterialApp(home: BetaConsentGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Privacy and permission areas'), findsOneWidget);
    expect(find.text('Feedback diagnostics'), findsOneWidget);
    expect(find.text('Script text'), findsOneWidget);
    expect(find.text('Microphone and speech recognition'), findsOneWidget);
    expect(find.text('Camera and Photos'), findsOneWidget);
    expect(find.text('Remote control and local network'), findsOneWidget);
    expect(find.text('Account, cloud, and local backup'), findsOneWidget);
    expect(find.text('File import and local documents'), findsOneWidget);
  });

  testWidgets('recovers when beta consent cannot be saved', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          betaConsentProvider.overrideWith(_FailingConsentNotifier.new),
        ],
        child: const MaterialApp(home: BetaConsentGate()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accept and continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept and continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text('Could not save beta consent. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Accept and continue'), findsOneWidget);
  });
}

class _ReadyConsentNotifier extends BetaConsentNotifier {
  @override
  BetaConsentState build() {
    return const BetaConsentState(
      loaded: true,
      deviceKey: 'test-device-key',
    );
  }
}

class _FailingConsentNotifier extends BetaConsentNotifier {
  @override
  BetaConsentState build() {
    return const BetaConsentState(
      loaded: true,
      deviceKey: 'test-device-key',
    );
  }

  @override
  Future<void> acceptCurrentPolicy() async {
    throw StateError('storage unavailable');
  }
}
