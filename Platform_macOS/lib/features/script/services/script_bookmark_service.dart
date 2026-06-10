import 'dart:convert';

import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/features/feedback/services/lightweight_diagnostics.dart';
import 'package:autoteleprompter/core/security/encrypted_file_store.dart';
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
  static const _bookmarkSign = '\u00BB';
  static final _tagStripRe = RegExp(r'\[[^\]]+\]');
  static final _alignTagStripRe = RegExp(r'\[\/?align=[^\]]+\]');

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
    final secureKey = '$key.secure';
    final secureRaw = prefs.getString(secureKey);
    if (secureRaw != null && secureRaw.isNotEmpty) {
      try {
        final bytes = await EncryptedFileStore().unprotectEnvelopeAsync(
          secureRaw,
          expectedKind: 'script-bookmarks',
        );
        final raw = (jsonDecode(utf8.decode(bytes)) as List).cast<dynamic>();
        return _decodeBookmarks(raw);
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'scriptBookmark.loadSecure',
          data: {'scopeKey': key},
        );
        return const [];
      }
    }
    final raw = prefs.getStringList(key) ?? const [];
    final result = _decodeBookmarks(raw);
    if (result.isNotEmpty) {
      await save(key, result);
      await prefs.remove(key);
    }
    return result;
  }

  static Future<void> save(String key, List<ScriptBookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...bookmarks]
      ..sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    final encrypted = await EncryptedFileStore().protectToEnvelopeAsync(
      utf8.encode(jsonEncode(sorted.map((b) => b.toJson()).toList())),
      kind: 'script-bookmarks',
    );
    await prefs.setString('$key.secure', encrypted);
    await prefs.remove(key);
  }

  static List<ScriptBookmark> _decodeBookmarks(List<dynamic> raw) {
    final result = <ScriptBookmark>[];
    for (final item in raw) {
      try {
        final decoded = item is String ? jsonDecode(item) : item;
        result.add(
          ScriptBookmark.fromJson(Map<String, dynamic>.from(decoded as Map)),
        );
      } catch (error) {
        LightweightDiagnostics.instance.record(
          'script',
          'ignored malformed bookmark metadata',
          data: {'error': error.toString()},
        );
      }
    }
    result.sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    return result;
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

  static int? nearestBookmarkableWordIndex(
    List<ScriptWord> words,
    int candidateIndex,
  ) {
    if (words.isEmpty) return null;
    final bookmarkable = <int>[];
    for (final word in words) {
      if (isBookmarkableWord(word)) bookmarkable.add(word.index);
    }
    if (bookmarkable.isEmpty) return null;

    final safeIndex = candidateIndex.clamp(0, words.length - 1).toInt();
    final first = bookmarkable.first;
    final last = bookmarkable.last;
    if (safeIndex <= first) return first;
    if (safeIndex >= last) return last;
    if (bookmarkable.contains(safeIndex)) return safeIndex;

    int best = first;
    var bestDistance = (safeIndex - first).abs();
    for (final index in bookmarkable.skip(1)) {
      final distance = (safeIndex - index).abs();
      final isBetter = distance < bestDistance ||
          (distance == bestDistance && index > safeIndex);
      if (!isBetter) continue;
      best = index;
      bestDistance = distance;
    }
    return best;
  }

  static int? anchoredWordIndexFromEditorPosition({
    required String rawText,
    required List<ScriptWord> words,
    required int blockIndex,
    required int offset,
  }) {
    if (blockIndex < 0 || words.isEmpty) return null;
    final blocks = rawText.split('\n');
    if (blockIndex >= blocks.length) return null;
    var cursor = 0;
    final lastBlock = blocks.length - 1;
    for (var i = 0; i < blockIndex; i++) {
      cursor += _tokenLengthForRawBlock(
        blocks[i],
        includeSoftBreak: i < lastBlock,
      );
    }
    cursor += _localWordIndexForRawOffset(blocks[blockIndex], offset);
    return nearestBookmarkableWordIndex(words, cursor);
  }

  static bool isBookmarkableWord(ScriptWord word) {
    if (word.isNewline) return false;
    final visible = word.raw
        .replaceAll(_tagStripRe, '')
        .replaceAll(_alignTagStripRe, '')
        .trim();
    return visible.isNotEmpty;
  }

  static int _tokenLengthForRawBlock(
    String text, {
    required bool includeSoftBreak,
  }) {
    final clean = _stripBookmarkSigns(text);
    if (clean.trim().isEmpty) return 1;
    final wordCount =
        WordAligner.tokenize(clean).where((word) => !word.isNewline).length;
    return wordCount + (includeSoftBreak ? 1 : 0);
  }

  static int _localWordIndexForRawOffset(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length).toInt();
    final signsBefore = RegExp(RegExp.escape(_bookmarkSign))
        .allMatches(text.substring(0, safeOffset))
        .length;
    final cleanText = _stripBookmarkSigns(text);
    final cleanOffset =
        (safeOffset - signsBefore).clamp(0, cleanText.length).toInt();
    final visibleText = _stripTags(cleanText);
    final visibleOffset = _rawToVisibleOffset(cleanText, cleanOffset)
        .clamp(0, visibleText.length)
        .toInt();
    final matches = RegExp(r'\S+').allMatches(visibleText).toList();
    if (matches.isEmpty) return 0;
    for (var i = 0; i < matches.length; i++) {
      if (visibleOffset <= matches[i].start) return i;
      if (visibleOffset > matches[i].start && visibleOffset < matches[i].end) {
        return i;
      }
    }
    return matches.length;
  }

  static String _stripBookmarkSigns(String text) =>
      text.replaceAll(_bookmarkSign, '');

  static String _stripTags(String text) =>
      text.replaceAll(_tagStripRe, '').replaceAll(_alignTagStripRe, '');

  static int _rawToVisibleOffset(String raw, int rawOffset) {
    var visible = 0;
    var i = 0;
    final safeOffset = rawOffset.clamp(0, raw.length).toInt();
    while (i < safeOffset) {
      if (raw.codeUnitAt(i) == 0x5B) {
        final close = raw.indexOf(']', i + 1);
        if (close >= 0 && close < safeOffset) {
          i = close + 1;
          continue;
        }
      }
      visible++;
      i++;
    }
    return visible;
  }
}
