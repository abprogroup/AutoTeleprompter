part of 'script_gallery_screen.dart';

List<String> _dedupedRecentMetadata(List<String> raw) {
  final seen = <String>{};
  final visible = <String>[];
  for (final item in raw) {
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(item));
      final keys = _recentGalleryIdentityKeys(decoded);
      if (keys.isEmpty) {
        visible.add(item);
        continue;
      }
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      visible.add(item);
    } catch (error) {
      LightweightDiagnostics.instance.record(
        'gallery',
        'ignored malformed recent metadata while displaying history',
        data: {'error': error.toString()},
      );
    }
  }
  return visible;
}

List<String> _recentGalleryIdentityKeys(Map<String, dynamic> decoded) {
  final keys = <String>[];
  final path = _normalizeRecentGalleryPath(decoded['sourcePath']?.toString());
  if (path.isNotEmpty) keys.add('path:$path');
  final title = _normalizeRecentGalleryTitle(decoded['title']?.toString());
  if (title.isNotEmpty) {
    final type = (decoded['type']?.toString() ?? '').trim().toUpperCase();
    keys.add('title:$type:$title');
  }
  return keys;
}

String _recentGallerySelectionKey(Map<String, dynamic> decoded) {
  final keys = _recentGalleryIdentityKeys(decoded);
  if (keys.isNotEmpty) return keys.first;
  final sessionId = decoded['sessionId']?.toString().trim();
  if (sessionId != null && sessionId.isNotEmpty) return 'session:$sessionId';
  return 'recent:${jsonEncode(decoded).hashCode}';
}

List<String> _recentGallerySourcePaths(Iterable<Map<String, dynamic>> rows) {
  final paths = <String>[];
  final seen = <String>{};
  for (final row in rows) {
    for (final field in const [
      'sourcePath',
      'sourceFilePath',
      'originalPath',
      'filePath',
      'path',
    ]) {
      final path = row[field]?.toString().trim();
      if (path == null || path.isEmpty) continue;
      final key = _normalizeRecentGalleryPath(path);
      if (key.isEmpty || !seen.add(key)) continue;
      paths.add(path);
    }
  }
  return paths;
}

Future<int> _deleteRecentGallerySourceFiles(
  Iterable<Map<String, dynamic>> rows,
) async {
  var deleted = 0;
  for (final path in _recentGallerySourcePaths(rows)) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      deleted++;
    }
  }
  return deleted;
}

String _normalizeRecentGalleryPath(String? value) {
  final path = value?.trim();
  if (path == null || path.isEmpty) return '';
  return path.replaceAll('/', '\\').toLowerCase();
}

String _normalizeRecentGalleryTitle(String? value) {
  var title = value?.trim().toLowerCase() ?? '';
  var changed = true;
  while (changed) {
    changed = false;
    final next = title.replaceFirst(
      RegExp(r'\.(?:atp|atp\.txt)$', caseSensitive: false),
      '',
    );
    if (next != title) {
      title = next;
      changed = true;
    }
  }
  return title.replaceAll(RegExp(r'\s+'), ' ');
}

class _ScriptListItem extends ConsumerWidget {
  static final Map<String, Future<String>> _previewCache = {};

  final String title;
  final String date;
  final String type;
  final String fullText;
  final String? snippet;
  final String? sessionId;
  final String? secureRecordId;
  final String? sourcePath;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  const _ScriptListItem({
    super.key,
    required this.title,
    required this.date,
    required this.type,
    required this.fullText,
    this.snippet,
    this.sessionId,
    this.secureRecordId,
    this.sourcePath,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelStyle = _labelStyleForType(type);
    final previewKey = [
      secureRecordId ?? '',
      title,
      date,
      fullText.hashCode.toString(),
      snippet.hashCode.toString(),
    ].join('|');
    final previewFuture =
        _previewCache.putIfAbsent(previewKey, _loadPreviewText);

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: selectionMode
                    ? () => onSelectionChanged?.call(!selected)
                    : () => _openRecentScript(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (selectionMode) ...[
                        Checkbox(
                          value: selected,
                          onChanged: (value) =>
                              onSelectionChanged?.call(value ?? false),
                          activeColor: const Color(0xFFFFBF00),
                          checkColor: Colors.black,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _ScriptTypePill(type: type, style: labelStyle),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FutureBuilder<String>(
                              future: previewFuture,
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? 'Loading preview...',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                );
                              },
                            ),
                            Text(
                              date,
                              style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white24,
                  size: 20,
                ),
                onPressed: selectionMode
                    ? null
                    : () => _confirmDeleteRecentScript(context, ref),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRecentScript(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choice = await showScriptDeleteDialog(
      context,
      title: title,
      sourcePath: sourcePath,
    );
    if (choice == null || !context.mounted) return;
    try {
      if (sessionId != null) {
        await ref.read(settingsProvider.notifier).deleteRecentScript(
              sessionId: sessionId,
              title: title,
            );
      } else {
        await ref.read(settingsProvider.notifier).deleteRecentScript(
              title: title,
            );
      }
      if (choice.deleteSourceFile && sourcePath != null) {
        final file = File(sourcePath!);
        if (await file.exists()) await file.delete();
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            choice.deleteSourceFile
                ? 'Deleted script and source file.'
                : 'Deleted script from the app.',
          ),
        ),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'gallery.deleteRecentScript',
        data: {
          'title': title,
          'sessionId': sessionId ?? '',
          'sourcePath': sourcePath ?? '',
        },
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this script.')),
      );
    }
  }

  Future<void> _openRecentScript(BuildContext context, WidgetRef ref) async {
    LightweightDiagnostics.instance.record(
      'gallery',
      'recent script opened',
      data: {
        'title': title,
        'sourceType': type,
        'sessionId': sessionId,
        'hasSecureRecord': secureRecordId != null && secureRecordId!.isNotEmpty,
      },
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final scriptNotifier = ref.read(scriptProvider.notifier);
    Map<String, dynamic>? decodedMeta;

    try {
      final recentScripts = ref.read(settingsProvider).recentScripts;
      final targetMeta = _findRecentMetadata(recentScripts);

      var resolvedText = fullText;
      String? resolvedHistoryJson;
      if (targetMeta != null) {
        final meta = jsonDecode(targetMeta) as Map<String, dynamic>;
        decodedMeta = meta;
        final secureData = await SecureScriptStore().readFromMetadata(meta);
        if (secureData != null) {
          resolvedText = secureData.text;
          resolvedHistoryJson = secureData.historyJson;
        }
        if (meta['style'] != null) {
          await settingsNotifier.applySessionStyles(meta['style']);
        }
      }

      scriptNotifier.loadText(
        resolvedText,
        title: title,
        sourceType: type,
        sourcePath: decodedMeta?['sourcePath'] as String?,
        sessionId: sessionId,
        historyJson: resolvedHistoryJson,
        fontSize: (decodedMeta?['style']?['fontSize'] as num?)?.toDouble(),
        fontFamily: decodedMeta?['style']?['fontFamily'],
        lineSpacing:
            (decodedMeta?['style']?['lineSpacing'] as num?)?.toDouble(),
        letterSpacing:
            (decodedMeta?['style']?['letterSpacing'] as num?)?.toDouble(),
        wordSpacing:
            (decodedMeta?['style']?['wordSpacing'] as num?)?.toDouble(),
        textAlign: decodedMeta?['style']?['textAlign'],
        scriptBgColor: decodedMeta?['style']?['scriptBgColor'],
        currentWordColor: decodedMeta?['style']?['currentWordColor'],
        futureWordColor: decodedMeta?['style']?['futureWordColor'],
        persist: decodedMeta == null,
        tokenize: false,
      );
      if (decodedMeta != null) {
        unawaited(settingsNotifier.activateRecentScript(decodedMeta));
      }
    } catch (e, stack) {
      LightweightDiagnostics.instance.recordError(
        e,
        stack,
        source: 'gallery.recentOpenRecovery',
        data: {
          'title': title,
          'sourceType': type,
          'sessionId': sessionId,
          'hasSecureRecord':
              secureRecordId != null && secureRecordId!.isNotEmpty,
        },
      );
      if (kDebugMode) debugPrint('Session Recovery Error: $e');
      scriptNotifier.loadText(
        fullText,
        title: title,
        sourceType: type,
        sourcePath: decodedMeta?['sourcePath'] as String?,
        sessionId: sessionId,
        tokenize: false,
      );
    }

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScriptEditorScreen()),
      );
    }
  }

  String? _findRecentMetadata(List<String> recentScripts) {
    for (final entry in recentScripts) {
      final decodedJson = jsonDecode(entry);
      if (sessionId != null && decodedJson['sessionId'] == sessionId) {
        return entry;
      }
      if (sessionId == null &&
          decodedJson['title'] == title &&
          decodedJson['fullText'] == fullText) {
        return entry;
      }
    }
    return null;
  }

  Future<String> _loadPreviewText() async {
    String text = fullText;
    if (secureRecordId != null && secureRecordId!.isNotEmpty) {
      final data = await SecureScriptStore().read(secureRecordId);
      text = data?.text ?? '';
    }
    return StylingService.recentScriptPreviewText(
      fullText: text,
      snippet: null,
    );
  }

  _ScriptTypeLabelStyle _labelStyleForType(String type) {
    switch (type.toUpperCase()) {
      case 'PRO':
        return const _ScriptTypeLabelStyle(
          color: Colors.black,
          backgroundColor: Color(0xFFFFBF00),
          borderColor: Colors.transparent,
        );
      case 'TEMP':
        return _scriptTypeStyle(const Color(0xFF64B5F6));
      case 'RTF':
      case 'DOCX':
      case 'DOC':
      case 'ODT':
      case 'PAGES':
        return _scriptTypeStyle(const Color(0xFF81C784));
      case 'PDF':
        return _scriptTypeStyle(const Color(0xFFE57373));
      case 'TXT':
      case 'MD':
      case 'LOG':
        return const _ScriptTypeLabelStyle(
          color: Colors.white70,
          backgroundColor: Colors.white10,
          borderColor: Colors.white24,
        );
      default:
        return _scriptTypeStyle(const Color(0xFFCE93D8));
    }
  }

  _ScriptTypeLabelStyle _scriptTypeStyle(Color color) {
    return _ScriptTypeLabelStyle(
      color: color,
      backgroundColor: color.withValues(alpha: 0.15),
      borderColor: color.withValues(alpha: 0.3),
    );
  }
}

class _ScriptTypePill extends StatelessWidget {
  final String type;
  final _ScriptTypeLabelStyle style;

  const _ScriptTypePill({
    required this.type,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.borderColor),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: style.color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ScriptTypeLabelStyle {
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _ScriptTypeLabelStyle({
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });
}
