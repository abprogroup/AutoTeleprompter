import 'dart:convert';

import 'package:autoteleprompter/core/security/secure_script_store.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup stored-script load does not write after provider disposal',
      () async {
    SharedPreferences.setMockInitialValues({
      'lastScriptSessionId': 'missing-secure-script',
      'recentScripts': [
        jsonEncode({
          'title': 'Missing encrypted script',
          'sessionId': 'missing-secure-script',
          SecureScriptStore.recordIdKey: 'missing-secure-script',
        }),
      ],
    });

    final container = ProviderContainer();
    container.read(scriptProvider);
    container.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 25));
  });

  test('missing stored encrypted script keeps provider empty without throwing',
      () async {
    SharedPreferences.setMockInitialValues({
      'lastScriptSessionId': 'missing-secure-script',
      'recentScripts': [
        jsonEncode({
          'title': 'Missing encrypted script',
          'sessionId': 'missing-secure-script',
          SecureScriptStore.recordIdKey: 'missing-secure-script',
        }),
      ],
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(scriptProvider), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(container.read(scriptProvider), isNull);
  });
}
