import 'dart:async';
import 'dart:ui';

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
        Future<void>(() async {
          try {
            await PlatformPermissions.requestAll();
          } catch (error, stackTrace) {
            LightweightDiagnostics.instance.recordError(
              error,
              stackTrace,
              source: 'permissions',
            );
            debugPrint('macOS startup permission request failed: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        });
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
