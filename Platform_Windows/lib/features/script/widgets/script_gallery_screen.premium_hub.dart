part of 'script_gallery_screen.dart';

const _upgradeWebsiteUrl =
    String.fromEnvironment('AUTOTELEPROMPTER_UPGRADE_URL');

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

class _PremiumHubSheet extends StatelessWidget {
  final AuthState auth;
  final VoidCallback? onOpenRemote;
  final VoidCallback onOpenCloud;
  final VoidCallback onSignIn;
  final VoidCallback onOpenAccount;

  const _PremiumHubSheet({
    required this.auth,
    required this.onOpenRemote,
    required this.onOpenCloud,
    required this.onSignIn,
    required this.onOpenAccount,
  });

  bool get _hasProAccess => auth.isPro || auth.isAdmin;

  @override
  Widget build(BuildContext context) {
    final title = _hasProAccess ? 'Pro access active' : 'Free plan';
    final subtitle = _hasProAccess
        ? 'Remote control, cloud and backup storage, creator tools, and recording '
            'features are unlocked for this account.'
        : 'Local scripts and local app storage are available. Connect a Pro '
            'account to unlock remote control and cloud backup tools.';

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 760),
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFBF00).withValues(alpha: .32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .5),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFBF00).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _hasProAccess
                          ? Icons.verified_rounded
                          : Icons.workspace_premium_outlined,
                      color: const Color(0xFFFFBF00),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _PremiumFeatureTile(
                icon: Icons.settings_remote_outlined,
                title: 'Remote Control',
                subtitle:
                    'Use phone, tablet, or operator remotes for Present mode.',
                locked: !_hasProAccess || onOpenRemote == null,
                onTap: onOpenRemote,
              ),
              const SizedBox(height: 10),
              _PremiumFeatureTile(
                icon: Icons.cloud_outlined,
                title: 'Cloud And Backup Storage',
                subtitle:
                    'Connect Google Drive or Dropbox accounts, or use Local '
                    'Backup storage.',
                locked: !_hasProAccess,
                onTap: onOpenCloud,
              ),
              const SizedBox(height: 10),
              _PremiumFeatureTile(
                icon: Icons.video_camera_front_outlined,
                title: 'Creator And Recording Tools',
                subtitle:
                    'Record video/audio and use Content Creator workflows.',
                locked: !_hasProAccess,
                onTap: null,
              ),
              const SizedBox(height: 16),
              if (_hasProAccess)
                _PremiumActionButton(
                  icon: Icons.manage_accounts_outlined,
                  label: 'Manage account',
                  onPressed: onOpenAccount,
                )
              else ...[
                _PremiumActionButton(
                  icon: Icons.login_rounded,
                  label: 'Sign in with Pro account',
                  onPressed: onSignIn,
                ),
                const SizedBox(height: 8),
                _PremiumActionButton(
                  icon: Icons.open_in_new_rounded,
                  label: 'Upgrade account',
                  onPressed: () => _openUpgradeWebsite(context),
                  secondary: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUpgradeWebsite(BuildContext context) async {
    final url = _upgradeWebsiteUrl.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Upgrade website is not configured on this installation.',
          ),
        ),
      );
      return;
    }
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
      return;
    }
    await Process.run('open', [url]);
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool locked;
  final VoidCallback? onTap;

  const _PremiumFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = !locked && onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFFFBF00).withValues(alpha: .28)
                  : Colors.white.withValues(alpha: .08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_outline_rounded : icon,
                color: enabled ? const Color(0xFFFFBF00) : Colors.white30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled ? Colors.white54 : Colors.white30,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (locked)
                const Text(
                  'PRO',
                  style: TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white24,
                )
              else
                const Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool secondary;

  const _PremiumActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: secondary
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black,
              ),
            ),
    );
  }
}
