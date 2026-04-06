import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/script/widgets/script_editor_screen.dart';

class AutoTelepromptApp extends StatelessWidget {
  const AutoTelepromptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'AutoTeleprompt',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFBF00),
            surface: Color(0xFF1A1A1A),
          ),
          segmentedButtonTheme: const SegmentedButtonThemeData(),
        ),
        home: const ScriptEditorScreen(),
      ),
    );
  }
}
