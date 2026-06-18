import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MacOSCameraDevice {
  final String id;
  final String name;
  final String position;

  const MacOSCameraDevice({
    required this.id,
    required this.name,
    required this.position,
  });

  factory MacOSCameraDevice.fromMap(Map<Object?, Object?> map) {
    return MacOSCameraDevice(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      position: (map['position'] ?? 'unspecified').toString(),
    );
  }
}

class MacOSCameraController {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/camera');

  final String deviceId;
  final String deviceName;
  final String resolution;
  final bool enableAudio;

  bool isInitialized = false;
  int? textureId;
  Size? previewSize;

  MacOSCameraController({
    required this.deviceId,
    required this.deviceName,
    required this.resolution,
    required this.enableAudio,
  });

  static Future<List<MacOSCameraDevice>> availableCameras() async {
    if (!Platform.isMacOS) return const [];
    final raw = await _channel.invokeMethod<List<Object?>>('listDevices') ??
        const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(MacOSCameraDevice.fromMap)
        .where((device) => device.id.isNotEmpty && device.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> initialize() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'initialize',
      {
        'deviceId': deviceId,
        'resolution': resolution,
        'enableAudio': enableAudio,
      },
    );
    if (result == null) {
      throw StateError('macOS camera initialization returned no data.');
    }
    textureId = (result['textureId'] as num?)?.toInt();
    final width = (result['width'] as num?)?.toDouble();
    final height = (result['height'] as num?)?.toDouble();
    if (textureId == null || width == null || height == null) {
      throw StateError('macOS camera initialization returned invalid data.');
    }
    previewSize = Size(width, height);
    isInitialized = true;
  }

  Future<void> startVideoRecording(String path) async {
    await _channel.invokeMethod<bool>('startRecording', {'path': path});
  }

  Future<String> stopVideoRecording() async {
    final path = await _channel.invokeMethod<String>('stopRecording');
    if (path == null || path.isEmpty) {
      throw StateError('macOS camera recording returned no file path.');
    }
    return path;
  }

  Future<void> dispose() async {
    isInitialized = false;
    textureId = null;
    previewSize = null;
    await _channel.invokeMethod<bool>('dispose');
  }

  Widget preview() {
    final id = textureId;
    if (id == null) return const SizedBox.shrink();
    return Texture(textureId: id);
  }
}
