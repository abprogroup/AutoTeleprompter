import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    // On iOS, calling initialize() triggers the native permission dialogs
    // for both microphone (AVAudioSession) and speech recognition (SFSpeechRecognizer).
    // This is the correct way — permission_handler does not reliably trigger
    // these dialogs for sideloaded apps.
    try {
      final stt = SpeechToText();
      await stt.initialize();
    } catch (_) {}
  }
  runApp(const ProviderScope(child: AutoTeleprompterApp()));
}
