import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'platform/permissions/platform_permissions.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AutoTeleprompterApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>(() async {
      try {
        await PlatformPermissions.requestAll();
      } catch (error, stackTrace) {
        debugPrint('macOS startup permission request failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  });
}
