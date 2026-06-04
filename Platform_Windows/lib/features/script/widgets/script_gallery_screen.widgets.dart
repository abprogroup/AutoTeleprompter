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
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onOpenRemote;
  final VoidCallback onOpenCloud;
  final VoidCallback onLockedFeature;

  const _ProDashboard({
    required this.auth,
    required this.onTap,
    required this.onOpenCloud,
    required this.onLockedFeature,
    this.onOpenRemote,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = auth.hasPremiumAccess;
    final title = isActive ? 'Pro access active' : 'Free plan';
    final subtitle = isActive
        ? 'Premium tools: cloud, remote, content creation, audio recorder.'
        : 'Pro tools locked: cloud, remote, content creation, audio recorder.';

    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return _buildCompact(
            title: title,
            subtitle: subtitle,
            isActive: isActive,
          );
        },
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFBF00).withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                      size: 24,
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
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.35),
                        ),
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
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white24,
                    ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (Platform.isWindows)
                      Expanded(
                        child: _ProFeaturePill(
                          icon: Icons.settings_remote_outlined,
                          label: 'Remote',
                          active: isActive && onOpenRemote != null,
                          onTap: isActive && onOpenRemote != null
                              ? onOpenRemote!
                              : onLockedFeature,
                        ),
                      ),
                    if (Platform.isWindows) const SizedBox(width: 8),
                    Expanded(
                      child: _ProFeaturePill(
                        icon: Icons.cloud_outlined,
                        label: 'Cloud',
                        active: isActive,
                        onTap: isActive ? onOpenCloud : onLockedFeature,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact({
    required String title,
    required String subtitle,
    required bool isActive,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFFBF00).withValues(alpha: 0.36),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFBF00).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isActive
                      ? Icons.verified_rounded
                      : Icons.workspace_premium_outlined,
                  color: const Color(0xFFFFBF00),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFBF00),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Platform.isWindows)
                    SizedBox(
                      width: 94,
                      child: _ProFeaturePill(
                        icon: Icons.settings_remote_outlined,
                        label: 'Remote',
                        active: isActive && onOpenRemote != null,
                        dense: true,
                        onTap: isActive && onOpenRemote != null
                            ? onOpenRemote!
                            : onLockedFeature,
                      ),
                    ),
                  if (Platform.isWindows) const SizedBox(height: 4),
                  SizedBox(
                    width: 94,
                    child: _ProFeaturePill(
                      icon: Icons.cloud_outlined,
                      label: 'Cloud',
                      active: isActive,
                      dense: true,
                      onTap: isActive ? onOpenCloud : onLockedFeature,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProFeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool dense;

  const _ProFeaturePill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFFFBF00) : Colors.white30;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(dense ? 8 : 10),
        child: Container(
          height: dense ? 28 : 36,
          padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 10),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFFFBF00).withValues(alpha: .10)
                : Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(dense ? 8 : 10),
            border: Border.all(
              color: active
                  ? const Color(0xFFFFBF00).withValues(alpha: .24)
                  : Colors.white.withValues(alpha: .08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? icon : Icons.lock_outline_rounded,
                  color: color, size: dense ? 14 : 17),
              SizedBox(width: dense ? 4 : 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white70 : Colors.white38,
                    fontSize: dense ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
