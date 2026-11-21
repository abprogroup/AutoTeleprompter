import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/splash/widgets/splash_screen.dart';
import 'core/widgets/connection_lifecycle.dart';

class AutoTeleprompterApp extends ConsumerWidget {
  const AutoTeleprompterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ConnectionLifecycle(
      child: MaterialApp(
        title: 'AUTOTELEPROMPTER',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        builder: (context, child) {
          final media = MediaQuery.maybeOf(context);
          if (media == null || child == null) {
            return child ?? const SizedBox.shrink();
          }
          return MediaQuery(
            data: media.copyWith(
              disableAnimations: settings.reduceMotion,
              textScaler: TextScaler.linear(
                AppTheme.clampUiScale(settings.uiScale),
              ),
            ),
            child: child,
          );
        },
        home: const AutoTeleprompterSplashScreen(),
      ),
    );
  }
}
