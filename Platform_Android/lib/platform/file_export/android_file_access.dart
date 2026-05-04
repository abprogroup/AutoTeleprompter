import 'dart:io';

import 'package:flutter/services.dart';

class AndroidDocumentEntry {
  final String displayName;
  final String location;
  final String mimeType;

  const AndroidDocumentEntry({
    required this.displayName,
    required this.location,
    this.mimeType = '',
  });

  factory AndroidDocumentEntry.fromMap(Map<dynamic, dynamic> value) {
    return AndroidDocumentEntry(
      displayName: (value['displayName'] as String? ?? '').trim(),
      location: (value['uri'] as String? ?? '').trim(),
      mimeType: (value['mimeType'] as String? ?? '').trim(),
    );
  }
}

class AndroidFileAccess {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/android_files');

  static bool isContentUri(String value) => value.startsWith('content://');

  static String displayNameFromPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  static String displayNameHintFromLocation(String value) {
    try {
      final uri = Uri.parse(value);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        var hint = Uri.decodeComponent(segments.last);
        if (hint.contains('/')) hint = hint.split('/').last;
        if (hint.contains(':')) hint = hint.split(':').last;
        if (hint.trim().isNotEmpty) return hint.trim();
      }
    } catch (_) {}
    return displayNameFromPath(value);
  }

  static Future<List<AndroidDocumentEntry>> findDocumentsByDisplayBase({
    required String baseName,
    required String format,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'findDocumentsByDisplayBase',
        {
          'baseName': baseName,
          'format': format,
        },
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(AndroidDocumentEntry.fromMap)
          .where((entry) =>
              entry.displayName.isNotEmpty && entry.location.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> pickExportFolder() async {
    try {
      final value = await _channel.invokeMethod<String>('pickExportFolder');
      return value?.trim().isEmpty == true ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasPersistedExportFolder(String treeUri) async {
    if (treeUri.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPersistedExportFolder', {
            'treeUri': treeUri,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<AndroidDocumentEntry>> listExportFolder(
    String treeUri,
  ) async {
    if (treeUri.trim().isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listExportFolder',
        {'treeUri': treeUri},
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(AndroidDocumentEntry.fromMap)
          .where((entry) =>
              entry.displayName.isNotEmpty && entry.location.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> createExportDocument({
    required String treeUri,
    required String displayName,
    required String mimeType,
  }) async {
    if (treeUri.trim().isEmpty ||
        displayName.trim().isEmpty ||
        mimeType.trim().isEmpty) {
      return null;
    }
    try {
      final value = await _channel.invokeMethod<String>(
        'createExportDocument',
        {
          'treeUri': treeUri,
          'displayName': displayName,
          'mimeType': mimeType,
        },
      );
      return value?.trim().isEmpty == true ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<List<AndroidDocumentEntry>> listDefaultExportFolder() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listDefaultExportFolder',
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(AndroidDocumentEntry.fromMap)
          .where((entry) =>
              entry.displayName.isNotEmpty && entry.location.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> createDefaultExportDocument({
    required String displayName,
    required String mimeType,
  }) async {
    if (displayName.trim().isEmpty || mimeType.trim().isEmpty) return null;
    try {
      final value = await _channel.invokeMethod<String>(
        'createDefaultExportDocument',
        {
          'displayName': displayName,
          'mimeType': mimeType,
        },
      );
      return value?.trim().isEmpty == true ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> deleteDocument(String location) async {
    if (!isContentUri(location)) {
      try {
        final file = File(location);
        if (!await file.exists()) return true;
        await file.delete();
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      return await _channel.invokeMethod<bool>('deleteDocument', {
            'uri': location,
          }) ??
          false;
    } catch (_) {
      return false;
    }
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
