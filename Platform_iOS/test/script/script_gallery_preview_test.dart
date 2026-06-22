import 'package:autoteleprompter/core/services/styling_service.dart';
import 'package:autoteleprompter/features/auth/providers/auth_provider.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/auth/services/account_session_store.dart';
import 'package:autoteleprompter/features/script/widgets/script_gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recent preview uses first two non-empty visible lines', () {
    final preview = StylingService.recentScriptPreviewText(
      fullText: '\n\n[align=right]\nשלום עולם\nשורה שניה\nשורה שלישית',
    );

    expect(preview, 'שלום עולם\nשורה שניה');
  });

  test('recent preview strips markup and ignores empty snippet', () {
    final preview = StylingService.recentScriptPreviewText(
      snippet: '   ',
      fullText: '[bg=#805000]EP1: Intro[/bg]\n[u]Imported text[/u]',
    );

    expect(preview, 'EP1: Intro\nImported text');
  });

  testWidgets('mobile gallery shows shortcuts and compact premium actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ScriptGalleryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Feedback'), findsOneWidget);
    expect(find.byTooltip('Remote'), findsOneWidget);
    expect(find.byTooltip('Cloud'), findsOneWidget);
    expect(find.byTooltip('Sign in'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    Finder premiumButton(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        );

    final cloudButton = premiumButton('Cloud');
    final remoteButton = premiumButton('Remote');
    final signInButton = premiumButton('Sign in');

    expect(cloudButton, findsOneWidget);
    expect(remoteButton, findsOneWidget);
    expect(signInButton, findsOneWidget);
    expect(tester.getSize(cloudButton).height, lessThanOrEqualTo(40));
    expect(tester.getSize(remoteButton).height, lessThanOrEqualTo(40));
    expect(tester.getSize(signInButton).height, lessThanOrEqualTo(40));
  });

  testWidgets('gallery sign in shortcut opens password account connection',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifier(
                accountBackendConfig: const AccountBackendConfig(enabled: true),
                accountSessionStore: _MemoryAccountSessionStore(),
              )),
        ],
        child: const MaterialApp(home: ScriptGalleryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Use email verification code'), findsOneWidget);
  });
}

class _MemoryAccountSessionStore extends AccountSessionStore {
  AccountSessionSnapshot? snapshot;

  @override
  Future<void> save(AccountSessionSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<AccountSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}
