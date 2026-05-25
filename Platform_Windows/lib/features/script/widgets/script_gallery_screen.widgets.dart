part of 'script_gallery_screen.dart';

class _GalleryActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GalleryActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.black, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _ProDashboard extends StatelessWidget {
  final AuthState auth;

  const _ProDashboard({required this.auth});

  @override
  Widget build(BuildContext context) {
    final isActive = auth.isPro || auth.isAdmin;
    final title = isActive ? 'Pro access active' : 'Beta Pro access';
    final subtitle = isActive
        ? auth.isAdmin
            ? 'Admin workspace unlocked'
            : 'Professional tools are unlocked on this device'
        : 'Activate a license when premium publishing tools are ready';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFBF00).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFBF00).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isActive
                  ? Icons.verified_rounded
                  : Icons.workspace_premium_outlined,
              color: const Color(0xFFFFBF00),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text('Activate'),
            ),
        ],
      ),
    );
  }
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
                onTap: () => _openRecentScript(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
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
                onPressed: () {
                  if (sessionId != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .removeFromRecent(sessionId!);
                  }
                },
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

    try {
      final recentScripts = ref.read(settingsProvider).recentScripts;
      final targetMeta = _findRecentMetadata(recentScripts);

      Map<String, dynamic>? decodedMeta;
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
    } catch (e) {
      if (kDebugMode) debugPrint('Session Recovery Error: $e');
      scriptNotifier.loadText(
        fullText,
        title: title,
        sourceType: type,
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

class _AutoSaveCard extends StatefulWidget {
  const _AutoSaveCard();

  @override
  State<_AutoSaveCard> createState() => _AutoSaveCardState();
}

class _AutoSaveCardState extends State<_AutoSaveCard> {
  String? _lastContent;

  @override
  void initState() {
    super.initState();
    _checkAutoSave();
  }

  Future<void> _checkAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    var content = prefs.getString('autosave_script');
    final secureId = prefs.getString('autosave_secure_record_id');
    if ((content == null || content.trim().isEmpty) &&
        secureId != null &&
        secureId.isNotEmpty) {
      content = (await SecureScriptStore().read(secureId))?.text;
    }
    final title = prefs.getString('autosave_title') ?? 'Untitled';
    if (mounted && content != null && content.trim().isNotEmpty) {
      setState(() => _lastContent = '$title: $content');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastContent == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: Colors.blue, size: 18),
              const SizedBox(width: 10),
              const Text(
                'RECOVERY AVAILABLE',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ScriptEditorScreen(),
                    ),
                  );
                },
                child: const Text(
                  'RESTORE SESSION',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Last Session',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _lastContent!.length > 100
                ? '${_lastContent!.substring(0, 100)}...'
                : _lastContent!,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyStatePlaceholder extends StatelessWidget {
  const _EmptyStatePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        children: [
          SizedBox(height: 48),
          Icon(Icons.description_outlined, color: Colors.white10, size: 64),
          SizedBox(height: 16),
          Text(
            'Work on you first script now and Choose "New Script"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
