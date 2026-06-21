import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/feedback/services/lightweight_diagnostics.dart';
import 'features/settings/services/update_install_service.dart';
import 'platform/permissions/platform_permissions.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  _installDiagnostics();
  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: AutoTeleprompterApp()));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runStartupMaintenance());
      });
    },
    (error, stackTrace) {
      LightweightDiagnostics.instance.recordError(
        error,
        stackTrace,
        source: 'zone',
      );
    },
  );
}

Future<void> _runStartupMaintenance() async {
  await _cleanupCompletedUpdateTemp('startup.updateCleanup.initial');
  await _requestStartupPermissions();
  await Future<void>.delayed(const Duration(seconds: 5));
  await _cleanupCompletedUpdateTemp('startup.updateCleanup.retry5s');
  await Future<void>.delayed(const Duration(seconds: 15));
  await _cleanupCompletedUpdateTemp('startup.updateCleanup.retry20s');
}

Future<void> _cleanupCompletedUpdateTemp(String source) async {
  try {
    await UpdateInstallService.cleanupCompletedUpdateTemp();
  } catch (error, stackTrace) {
    LightweightDiagnostics.instance.recordError(
      error,
      stackTrace,
      source: source,
    );
  }
}

Future<void> _requestStartupPermissions() async {
  try {
    await PlatformPermissions.requestAll();
  } catch (error, stackTrace) {
    LightweightDiagnostics.instance.recordError(
      error,
      stackTrace,
      source: 'permissions',
    );
    if (kDebugMode) {
      debugPrint('macOS startup permission request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

void _installDiagnostics() {
  FlutterError.onError = (details) {
    LightweightDiagnostics.instance.recordError(
      details.exception,
      details.stack,
      source: 'flutter',
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    LightweightDiagnostics.instance.recordError(
      error,
      stackTrace,
      source: 'platform',
    );
    return false;
  };
}
