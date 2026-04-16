import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'platform/permissions/platform_permissions.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformPermissions.requestAll();
  runApp(const ProviderScope(child: AutoTeleprompterApp()));
}
