import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ScriptBookmark {
  final String id;
  final String label;
  final int wordIndex;
  final int blockIndex;
  final int offset;
  final DateTime createdAt;

  const ScriptBookmark({
    required this.id,
    required this.label,
    required this.wordIndex,
    required this.blockIndex,
    required this.offset,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'wordIndex': wordIndex,
        'blockIndex': blockIndex,
        'offset': offset,
        'createdAt': createdAt.toIso8601String(),
      };

  static ScriptBookmark fromJson(Map<String, dynamic> json) {
    return ScriptBookmark(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Bookmark',
      wordIndex: (json['wordIndex'] as num?)?.toInt() ?? 0,
      blockIndex: (json['blockIndex'] as num?)?.toInt() ?? -1,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ScriptBookmarkService {
  static const _prefix = 'scriptBookmarks.v1';

  static String scopeKey(String? sessionId, String title) {
    final raw = ((sessionId != null && sessionId.trim().isNotEmpty)
            ? sessionId.trim()
            : title.trim())
        .replaceAll(RegExp(r'\s+'), ' ');
    final encoded =
        base64Url.encode(utf8.encode(raw.isEmpty ? 'untitled' : raw));
    return '$_prefix.$encoded';
  }

  static Future<List<ScriptBookmark>> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(key) ?? const [];
    final result = <ScriptBookmark>[];
    for (final item in raw) {
      try {
        result.add(
          ScriptBookmark.fromJson(
            Map<String, dynamic>.from(jsonDecode(item) as Map),
          ),
        );
      } catch (_) {}
    }
    result.sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    return result;
  }

  static Future<void> save(String key, List<ScriptBookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...bookmarks]
      ..sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    await prefs.setStringList(
      key,
      sorted.map((bookmark) => jsonEncode(bookmark.toJson())).toList(),
    );
  }

  static List<ScriptBookmark> upsert(
    List<ScriptBookmark> bookmarks,
    ScriptBookmark bookmark,
  ) {
    final next = bookmarks
        .where((existing) =>
            existing.wordIndex != bookmark.wordIndex ||
            existing.blockIndex != bookmark.blockIndex ||
            existing.offset != bookmark.offset)
        .toList()
      ..add(bookmark)
      ..sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    return next;
  }
}
