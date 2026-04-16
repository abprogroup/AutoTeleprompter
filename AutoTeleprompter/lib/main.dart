import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isIOS) {
    // Explicitly demand microphone permission from iOS
    await Permission.microphone.request();

    // Explicitly demand speech recognition permission from iOS
    await Permission.speech.request();

    // Also call speech_to_text initialize() which triggers
    // the native SFSpeechRecognizer.requestAuthorization() API directly
    try {
      await SpeechToText().initialize();
    } catch (_) {}
  }

  runApp(const ProviderScope(child: AutoTeleprompterApp()));
}
