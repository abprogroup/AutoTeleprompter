import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/feedback/services/lightweight_diagnostics.dart';
import 'platform/permissions/platform_permissions.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installDiagnostics();
  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: AutoTeleprompterApp()));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_requestStartupPermissions());
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
      debugPrint('iOS startup permission request failed: $error');
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
