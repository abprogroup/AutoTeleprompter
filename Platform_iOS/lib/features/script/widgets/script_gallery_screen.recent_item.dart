part of 'script_gallery_screen.dart';

class _ScriptListItem extends ConsumerWidget {
  final String title, date, type, fullText;
  final String? snippet;
  final String? sessionId;
  final String? secureRecordId;

  const _ScriptListItem({
    super.key,
    required this.title,
    required this.date,
    required this.type,
    required this.fullText,
    this.snippet,
    this.sessionId,
    this.secureRecordId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = _labelStyle(type);
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
            Expanded(child: _buildOpenArea(context, ref, style)),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white24,
                  size: 20,
                ),
                onPressed: sessionId == null
                    ? null
                    : () => ref
                        .read(settingsProvider.notifier)
                        .removeFromRecent(sessionId!),
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

  Widget _buildOpenArea(
    BuildContext context,
    WidgetRef ref,
    _ScriptTypeLabelStyle style,
  ) {
    return InkWell(
      onTap: () => _openRecentScript(context, ref),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
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
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildTextBlock()),
          ],
        ),
      ),
    );
  }

  Widget _buildTextBlock() {
    return FutureBuilder<String>(
      future: _loadPreviewText(),
      initialData: StylingService.recentScriptPreviewText(
        fullText: fullText,
        snippet: snippet,
      ),
      builder: (context, snapshot) {
        final previewText = snapshot.data ?? '';
        return Column(
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
            Text(
              previewText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            Text(
              date,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRecentScript(BuildContext context, WidgetRef ref) async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final scriptNotifier = ref.read(scriptProvider.notifier);
    Map<String, dynamic>? decodedMeta;
    var resolvedText = fullText;
    String? resolvedHistoryJson;

    try {
      final targetMeta =
          _findRecentMetadata(ref.read(settingsProvider).recentScripts);
      if (targetMeta != null) {
        decodedMeta = jsonDecode(targetMeta) as Map<String, dynamic>;
        final secureData =
            await SecureScriptStore().readFromMetadata(decodedMeta);
        if (secureData != null) {
          resolvedText = secureData.text;
          resolvedHistoryJson = secureData.historyJson;
        }
        if (decodedMeta['style'] != null) {
          await settingsNotifier.applySessionStyles(decodedMeta['style']);
        }
      }
      scriptNotifier.loadText(
        resolvedText,
        title: title,
        sourceType: type,
        sessionId: sessionId,
        historyIndex: (decodedMeta?['historyIndex'] as num?)?.toInt(),
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
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Session Recovery Error: $e');
      scriptNotifier.loadText(
        fullText,
        title: title,
        sourceType: type,
        sessionId: sessionId,
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
      final decodedJson = jsonDecode(entry) as Map<String, dynamic>;
      if (sessionId != null && decodedJson['sessionId'] == sessionId) {
        return entry;
      }
      if (secureRecordId != null &&
          decodedJson[SecureScriptStore.recordIdKey] == secureRecordId) {
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
    var text = fullText;
    if (text.isEmpty && secureRecordId != null && secureRecordId!.isNotEmpty) {
      text = (await SecureScriptStore().read(secureRecordId))?.text ?? '';
    }
    return StylingService.recentScriptPreviewText(
      fullText: text,
      snippet: snippet,
    );
  }

  static _ScriptTypeLabelStyle _labelStyle(String type) {
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

  static _ScriptTypeLabelStyle _scriptTypeStyle(Color color) {
    return _ScriptTypeLabelStyle(
      color: color,
      backgroundColor: color.withValues(alpha: 0.15),
      borderColor: color.withValues(alpha: 0.3),
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
