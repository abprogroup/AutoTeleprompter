import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/splash/widgets/splash_screen.dart';

class AutoTeleprompterApp extends ConsumerWidget {
  const AutoTeleprompterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'AUTOTELEPROMPTER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFBF00),
          surface: Color(0xFF1A1A1A),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      builder: (context, child) {
        final media = MediaQuery.maybeOf(context);
        if (media == null || child == null) {
          return child ?? const SizedBox.shrink();
        }
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: settings.reduceMotion,
          ),
          child: child,
        );
      },
      home: const AutoTeleprompterSplashScreen(),
    );
  }
}
