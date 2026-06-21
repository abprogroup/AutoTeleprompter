import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/feedback/services/lightweight_diagnostics.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installDiagnostics();
  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: AutoTeleprompterApp()));
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
