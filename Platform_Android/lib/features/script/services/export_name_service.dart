import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ExportNameService {
  static final RegExp _knownExtensionPattern = RegExp(
    r'\.(txt|pdf|docx|rtf|doc|pages|md)$',
    caseSensitive: false,
  );

  static String sanitizeBaseName(String title, String format) {
    final cleaned = title
        .trim()
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(_knownExtensionPattern, '')
        .trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  static String buildDisplayName(String baseName, String format) {
    final ext = format.toLowerCase();
    final base = sanitizeBaseName(baseName, ext);
    return '$base.$ext';
  }

  static String nextDuplicateDisplayName({
    required String baseName,
    required String format,
    required Iterable<String> existingDisplayNames,
  }) {
    final ext = format.toLowerCase();
    final safeBase = sanitizeBaseName(baseName, ext);
    final existing =
        existingDisplayNames.map((name) => name.toLowerCase().trim()).toSet();
    var index = 1;
    while (true) {
      final candidate = '$safeBase ($index).$ext';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
      index++;
    }
  }

  static String repairBrokenDuplicateSuffix(String displayName, String format) {
    final ext = format.toLowerCase();
    final pattern = RegExp(
      r'^(.*)\.' + RegExp.escape(ext) + r'\s+\((\d+)\)$',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(displayName.trim());
    if (match == null) return displayName;
    final base = (match.group(1) ?? '').trim();
    final suffix = match.group(2) ?? '1';
    if (base.isEmpty) return displayName;
    return '$base ($suffix).$ext';
  }

  static bool hasExpectedExtension(String displayName, String format) {
    return displayName
        .toLowerCase()
        .trim()
        .endsWith('.${format.toLowerCase()}');
  }
}

class SavedExportEntry {
  final String baseName;
  final String format;
  final String displayName;
  final String location;

  const SavedExportEntry({
    required this.baseName,
    required this.format,
    required this.displayName,
    required this.location,
  });

  factory SavedExportEntry.fromJson(Map<String, dynamic> json) {
    return SavedExportEntry(
      baseName: (json['baseName'] as String? ?? '').trim(),
      format: (json['format'] as String? ?? '').toLowerCase().trim(),
      displayName: (json['displayName'] as String? ?? '').trim(),
      location: (json['location'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'baseName': baseName,
        'format': format,
        'displayName': displayName,
        'location': location,
      };
}

class SavedExportRegistry {
  static const String _prefsKey = 'android_saved_exports_v1';

  static Future<List<SavedExportEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedExportEntry.fromJson)
          .where((entry) =>
              entry.baseName.isNotEmpty &&
              entry.format.isNotEmpty &&
              entry.displayName.isNotEmpty &&
              entry.location.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> record(SavedExportEntry entry) async {
    final existing = await load();
    final next = <SavedExportEntry>[];
    for (final item in existing) {
      final sameLocation = item.location == entry.location;
      final sameSlot = item.baseName == entry.baseName &&
          item.format == entry.format &&
          item.displayName == entry.displayName;
      if (!sameLocation && !sameSlot) next.add(item);
    }
    next.add(entry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(next.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  static SavedExportEntry? findExact({
    required List<SavedExportEntry> entries,
    required String baseName,
    required String format,
  }) {
    final normalizedFormat = format.toLowerCase();
    final displayName = ExportNameService.buildDisplayName(baseName, format);
    for (final entry in entries.reversed) {
      if (entry.baseName == baseName &&
          entry.format == normalizedFormat &&
          entry.displayName == displayName) {
        return entry;
      }
    }
    return null;
  }
}
