import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class AndroidFileAccess {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/android_files');

  static bool isContentUri(String value) => value.startsWith('content://');

  static String displayNameFromPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  static Future<void> writeBytes(String location, Uint8List bytes) async {
    if (isContentUri(location)) {
      final ok = await _channel.invokeMethod<bool>('writeBytesToUri', {
        'uri': location,
        'bytes': bytes,
      });
      if (ok != true) {
        throw FileSystemException('Unable to write content URI', location);
      }
      return;
    }
    await File(location).writeAsBytes(bytes);
  }

  static Future<String?> displayNameForLocation(String location) async {
    if (!isContentUri(location)) return displayNameFromPath(location);
    try {
      final value = await _channel.invokeMethod<String>('displayNameForUri', {
        'uri': location,
      });
      return value?.trim().isEmpty == true ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> rename(String location, String displayName) async {
    if (isContentUri(location)) {
      try {
        return await _channel.invokeMethod<String>('renameDocument', {
          'uri': location,
          'displayName': displayName,
        });
      } catch (_) {
        return null;
      }
    }

    try {
      final file = File(location);
      if (!await file.exists()) return null;
      final parent = file.parent.path;
      final separator = Platform.pathSeparator;
      final renamed = await file.rename('$parent$separator$displayName');
      return renamed.path;
    } catch (_) {
      return null;
    }
  }
}
