import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/core/theme/app_theme.dart';
import 'package:autoteleprompter/features/auth/services/account_grace_token.dart';
import 'package:autoteleprompter/features/settings/services/update_check_service.dart';
import 'package:autoteleprompter/features/settings/services/update_install_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Stage 3: AppTheme and UI scale', () {
    test('AppTheme.dark exposes semantic studio palette', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.canvas);
      expect(theme.colorScheme.primary, AppColors.amber);
      expect(theme.colorScheme.surface, AppColors.surface);
      expect(theme.dialogTheme.backgroundColor, AppColors.surface);
    });

    test('clampUiScale bounds extreme and non-finite inputs safely', () {
      expect(AppTheme.clampUiScale(double.nan), 1.0);
      expect(AppTheme.clampUiScale(double.infinity), 1.0);
      expect(AppTheme.clampUiScale(0.5), AppTheme.minUiScale);
      expect(AppTheme.clampUiScale(1.1), 1.1);
      expect(AppTheme.clampUiScale(2.5), AppTheme.maxUiScale);
    });
  });

  group('Stage 4: Updater SHA-256 verification', () {
    test('UpdateCheckService parses optional sha256 from manifest', () {
      const sampleHash =
          '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF';
      final body = jsonEncode({
        'channels': {
          'stable': {
            'version': '9.9.9+999',
            'url': 'https://example.invalid/update.zip',
            'sha256': sampleHash,
            'notes': 'Security update',
          },
        },
      });
      final result = UpdateCheckService().parseManifestJson(body, 'stable');
      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.sha256, sampleHash.toLowerCase());
    });

    test('verifyPackageSha256 accepts matching digest and rejects tampered file', () async {
      final tempDir = await Directory.systemTemp.createTemp('atp_sha256_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pkg = File('${tempDir.path}${Platform.pathSeparator}update.zip');
      await pkg.writeAsBytes(utf8.encode('autoteleprompter-update-bytes'));
      final expectedHash =
          sha256.convert(await pkg.readAsBytes()).toString().toLowerCase();

      await UpdateInstallService.verifyPackageSha256(pkg, expectedHash);
      await UpdateInstallService.verifyPackageSha256(
        pkg,
        expectedHash.toUpperCase(),
      );

      final wrongHash = '0' * 64;
      await expectLater(
        UpdateInstallService.verifyPackageSha256(pkg, wrongHash),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        UpdateInstallService.verifyPackageSha256(pkg, 'not-a-sha256'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Stage 4: Grace token multi-key safety', () {
    test('rejects unknown kid, malformed tokens, and empty key sets', () {
      const verifier = AccountGraceTokenVerifier(trustedKeys: {});
      final payload = base64Url.encode(
        utf8.encode(
          jsonEncode({
            'kid': 'unknown-prod-key',
            'aud': 'autoteleprompter-windows',
            'device_id': 'windows-test',
            'role': 'pro',
            'status': 'active',
            'issued_at': DateTime.now().toUtc().toIso8601String(),
            'grace_expires_at':
                DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String(),
          }),
        ),
      );
      final fakeSig = base64Url.encode(List<int>.filled(256, 7));

      expect(
        verifier.verify('$payload.$fakeSig', expectedDeviceId: 'windows-test'),
        isNull,
      );
      expect(
        const AccountGraceTokenVerifier().verify(
          'not-valid-base64.!!!',
          expectedDeviceId: 'windows-test',
        ),
        isNull,
      );
    });

    test('GraceTokenPublicKey validates key metadata', () {
      const invalidShort = GraceTokenPublicKey(
        keyId: 'k1',
        modulusHex: 'abcd',
      );
      const invalidNonHex = GraceTokenPublicKey(
        keyId: 'k1',
        modulusHex: 'zzzz',
      );
      final validShape = GraceTokenPublicKey(
        keyId: 'prod-2026',
        modulusHex: 'a' * 512,
      );
      expect(invalidShort.isValid, isFalse);
      expect(invalidNonHex.isValid, isFalse);
      expect(validShape.isValid, isTrue);
    });
  });

  group('Stage 4: Supabase & CI security contracts', () {
    test('Supabase functions enforce ban preservation, atomic redeem, revoked check, and PII scrub', () {
      final repoRoot = Directory.current.parent.path;
      final accountTs = File(
        '$repoRoot${Platform.pathSeparator}supabase${Platform.pathSeparator}functions${Platform.pathSeparator}_shared${Platform.pathSeparator}account.ts',
      ).readAsStringSync();
      final redeemTs = File(
        '$repoRoot${Platform.pathSeparator}supabase${Platform.pathSeparator}functions${Platform.pathSeparator}redeem-license-code${Platform.pathSeparator}index.ts',
      ).readAsStringSync();
      final refreshTs = File(
        '$repoRoot${Platform.pathSeparator}supabase${Platform.pathSeparator}functions${Platform.pathSeparator}refresh-session${Platform.pathSeparator}index.ts',
      ).readAsStringSync();
      final deleteTs = File(
        '$repoRoot${Platform.pathSeparator}supabase${Platform.pathSeparator}functions${Platform.pathSeparator}delete-account${Platform.pathSeparator}index.ts',
      ).readAsStringSync();
      final feedbackTs = File(
        '$repoRoot${Platform.pathSeparator}supabase${Platform.pathSeparator}functions${Platform.pathSeparator}submit-feedback${Platform.pathSeparator}index.ts',
      ).readAsStringSync();

      expect(accountTs, contains('ignoreDuplicates: true'));
      expect(redeemTs, contains('redeem_license_code_atomic'));
      expect(refreshTs, contains('session_revoked'));
      expect(deleteTs, contains('scrub_user_audit_pii'));
      expect(deleteTs, isNot(contains('audit(auth.client, "account_delete", userId, "ok", { email })')));
      expect(feedbackTs, contains('MAX_FEEDBACK_BYTES'));
      expect(feedbackTs, contains('AbortSignal.timeout'));
    });

    test('CI workflows avoid build-ios -v leak and emit Windows manifest sha256', () {
      final repoRoot = Directory.current.parent.path;
      final iosYml = File(
        '$repoRoot${Platform.pathSeparator}.github${Platform.pathSeparator}workflows${Platform.pathSeparator}build-ios.yml',
      ).readAsStringSync();
      final winYml = File(
        '$repoRoot${Platform.pathSeparator}.github${Platform.pathSeparator}workflows${Platform.pathSeparator}build-windows.yml',
      ).readAsStringSync();

      expect(iosYml, isNot(contains('--no-codesign -v')));
      expect(winYml, contains('Verify Release Binary Contains No Secrets'));
      expect(winYml, contains('zip_sha256'));
    });
  });
}
