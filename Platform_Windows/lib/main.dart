import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/feedback/services/lightweight_diagnostics.dart';
import 'platform/permissions/platform_permissions.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await PlatformPermissions.requestAll();
  FlutterError.onError = (details) {
    LightweightDiagnostics.instance.recordError(
      details.exception,
      details.stack,
      source: 'flutter',
      data: {'errorType': details.exception.runtimeType.toString()},
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    LightweightDiagnostics.instance.recordError(
      error,
      stackTrace,
      source: 'platform',
      data: {'errorType': error.runtimeType.toString()},
    );
    return true;
  };
  runZonedGuarded(
    () => runApp(const ProviderScope(child: AutoTeleprompterApp())),
    (error, stackTrace) {
      LightweightDiagnostics.instance.recordError(
        error,
        stackTrace,
        source: 'zone',
        data: {'errorType': error.runtimeType.toString()},
      );
    },
  );
}
