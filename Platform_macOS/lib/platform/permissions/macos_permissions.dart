import 'dart:io';

import 'package:flutter/services.dart';

import '../system/external_url_launcher.dart';

class MacOSPermissionStatus {
  final String value;

  const MacOSPermissionStatus(this.value);

  bool get isGranted => value == 'granted';
  bool get isDenied => value == 'denied';
  bool get isRestricted => value == 'restricted';
  bool get isNotDetermined => value == 'notDetermined';
  bool get isBlocked => isDenied || isRestricted;
}

class MacOSPermissions {
  const MacOSPermissions._();

  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/permissions');

  static Future<MacOSPermissionStatus> microphoneStatus() {
    return _status('microphoneStatus');
  }

  static Future<MacOSPermissionStatus> requestMicrophone() {
    return _status('requestMicrophone');
  }

  static Future<MacOSPermissionStatus> cameraStatus() {
    return _status('cameraStatus');
  }

  static Future<MacOSPermissionStatus> requestCamera() {
    return _status('requestCamera');
  }

  static Future<MacOSPermissionStatus> speechStatus() {
    return _status('speechStatus');
  }

  static Future<MacOSPermissionStatus> requestSpeech() {
    return _status('requestSpeech');
  }

  static Future<bool> openMicrophoneSettings() {
    return _openPrivacyPane('Privacy_Microphone');
  }

  static Future<bool> openCameraSettings() {
    return _openPrivacyPane('Privacy_Camera');
  }

  static Future<bool> openSpeechSettings() {
    return _openPrivacyPane('Privacy_SpeechRecognition');
  }

  static Future<MacOSPermissionStatus> _status(String method) async {
    if (!Platform.isMacOS) return const MacOSPermissionStatus('unsupported');
    final value = await _channel.invokeMethod<String>(method);
    return MacOSPermissionStatus(value ?? 'unknown');
  }

  static Future<bool> _openPrivacyPane(String anchor) {
    return ExternalUrlLauncher.openUrl(
      'x-apple.systempreferences:com.apple.preference.security?$anchor',
    );
  }
}
