import 'dart:io';

import 'package:flutter/services.dart';

class WindowsMicVolumeInfo {
  final bool available;
  final int volumePercent;
  final bool muted;
  final String deviceName;
  final String? error;

  const WindowsMicVolumeInfo({
    required this.available,
    required this.volumePercent,
    required this.muted,
    this.deviceName = '',
    this.error,
  });

  bool get isLowVolume => available && (muted || volumePercent < 80);

  factory WindowsMicVolumeInfo.fromMap(Map<Object?, Object?> map) {
    final available = map['available'] == true;
    final rawPercent = map['volumePercent'];
    final volumePercent =
        rawPercent is num ? rawPercent.round().clamp(0, 100) : 0;
    final muted = map['muted'] == true;
    final deviceName = (map['deviceName'] as String? ?? '').trim();
    final rawError = (map['error'] as String? ?? '').trim();
    return WindowsMicVolumeInfo(
      available: available,
      volumePercent: volumePercent,
      muted: muted,
      deviceName: deviceName,
      error: rawError.isEmpty ? null : rawError,
    );
  }
}

class WindowsMicVolumeService {
  const WindowsMicVolumeService();

  static const MethodChannel _channel = MethodChannel(
    'autoteleprompter/windows_mic_volume',
  );

  Future<WindowsMicVolumeInfo> getMicVolume({String? preferredLabel}) async {
    if (!Platform.isWindows) {
      return const WindowsMicVolumeInfo(
        available: false,
        volumePercent: 0,
        muted: false,
      );
    }
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getMicVolume',
        {'preferredLabel': preferredLabel ?? ''},
      );
      if (result == null) {
        return const WindowsMicVolumeInfo(
          available: false,
          volumePercent: 0,
          muted: false,
          error: 'Could not read Windows microphone volume.',
        );
      }
      return WindowsMicVolumeInfo.fromMap(result);
    } on MissingPluginException {
      return const WindowsMicVolumeInfo(
        available: false,
        volumePercent: 0,
        muted: false,
      );
    } catch (error) {
      return WindowsMicVolumeInfo(
        available: false,
        volumePercent: 0,
        muted: false,
        error: error.toString(),
      );
    }
  }

  Future<WindowsMicVolumeInfo> setMicVolume({
    String? preferredLabel,
    required int volumePercent,
    bool? muted,
  }) async {
    if (!Platform.isWindows) {
      return const WindowsMicVolumeInfo(
        available: false,
        volumePercent: 0,
        muted: false,
      );
    }
    try {
      final args = <String, Object>{
        'preferredLabel': preferredLabel ?? '',
        'volumePercent': volumePercent.clamp(0, 100),
      };
      if (muted != null) {
        args['muted'] = muted;
      }
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'setMicVolume',
        args,
      );
      if (result == null) {
        return const WindowsMicVolumeInfo(
          available: false,
          volumePercent: 0,
          muted: false,
          error: 'Could not update Windows microphone volume.',
        );
      }
      return WindowsMicVolumeInfo.fromMap(result);
    } on MissingPluginException {
      return const WindowsMicVolumeInfo(
        available: false,
        volumePercent: 0,
        muted: false,
      );
    } catch (error) {
      return WindowsMicVolumeInfo(
        available: false,
        volumePercent: 0,
        muted: false,
        error: error.toString(),
      );
    }
  }
}
