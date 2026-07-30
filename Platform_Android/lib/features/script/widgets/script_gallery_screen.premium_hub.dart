part of 'script_gallery_screen.dart';

class _PremiumShortcutIcon extends StatelessWidget {
  final bool enabled;
  final String tooltip;
  final String lockedTooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback onLockedPressed;

  const _PremiumShortcutIcon({
    required this.enabled,
    required this.tooltip,
    required this.lockedTooltip,
    required this.icon,
    required this.onPressed,
    required this.onLockedPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white54 : Colors.white24;
    return Tooltip(
      message: enabled ? tooltip : lockedTooltip,
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: enabled ? onPressed : onLockedPressed,
      ),
    );
  }
}

class _ProDashboard extends StatelessWidget {
  final AuthState auth;
  final VoidCallback onOpenRemote;
  final VoidCallback onOpenCloud;
  final VoidCallback onSignIn;

  const _ProDashboard({
    required this.auth,
    required this.onOpenRemote,
    required this.onOpenCloud,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final hasPro = auth.hasPremiumAccess;
    final checking = auth.isCheckingBackendAccess;
    final title = hasPro
        ? 'Pro access active'
        : checking
            ? 'Checking account'
            : 'Free plan';
    final subtitle = hasPro
        ? 'Remote control, cloud storage, content creation, and recording are unlocked.'
        : checking
            ? 'Verifying subscription and admin access with the account service.'
            : 'Connect a Pro account to unlock remote control and cloud storage.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFBF00).withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFBF00).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasPro
                  ? Icons.verified_rounded
                  : checking
                      ? Icons.sync_rounded
                      : Icons.workspace_premium_outlined,
              color: const Color(0xFFFFBF00),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ProFeaturePill(
                icon: hasPro ? Icons.cloud_outlined : Icons.lock_outline,
                label: 'Cloud',
                onTap: hasPro ? onOpenCloud : onSignIn,
              ),
              const SizedBox(height: 8),
              _ProFeaturePill(
                icon: hasPro
                    ? Icons.settings_remote_outlined
                    : Icons.lock_outline,
                label: 'Remote',
                onTap: hasPro ? onOpenRemote : onSignIn,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProFeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProFeaturePill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFBF00),
        foregroundColor: Colors.black,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
