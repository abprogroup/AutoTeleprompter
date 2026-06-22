import 'package:flutter/material.dart';

import '../../auth/providers/auth_provider.dart';

class ScriptGalleryPremiumPanel extends StatelessWidget {
  final AuthState auth;
  final VoidCallback onSignIn;
  final VoidCallback onOpenCloud;
  final Future<void> Function() onLogout;

  const ScriptGalleryPremiumPanel({
    super.key,
    required this.auth,
    required this.onSignIn,
    required this.onOpenCloud,
    required this.onLogout,
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
        ? 'Local backup, remote control, content creation, and recording are unlocked.'
        : 'Connect a Pro account to unlock backup, remote, creator tools, and recording.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFBF00).withValues(alpha: .32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFBF00).withValues(alpha: .16),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
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
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PremiumPanelButton(
                icon: hasPro ? Icons.cloud_outlined : Icons.lock_outline,
                label: 'Cloud',
                onPressed: hasPro ? onOpenCloud : onSignIn,
              ),
              _PremiumPanelButton(
                icon: hasPro
                    ? Icons.settings_remote_outlined
                    : Icons.lock_outline,
                label: 'Remote',
                onPressed: hasPro ? _showRemoteHint(context) : onSignIn,
              ),
              if (hasPro)
                _PremiumPanelButton(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  secondary: true,
                  onPressed: () => _confirmLogout(context),
                )
              else
                _PremiumPanelButton(
                  icon: Icons.login_rounded,
                  label: 'Sign in',
                  onPressed: onSignIn,
                ),
            ],
          ),
        ],
      ),
    );
  }

  VoidCallback _showRemoteHint(BuildContext context) {
    return () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remote control starts from Present mode.'),
        ),
      );
    };
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your scripts and local settings stay on this device.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onLogout();
    }
  }
}

class _PremiumPanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool secondary;

  const _PremiumPanelButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor:
            secondary ? const Color(0xFF1D1D1D) : const Color(0xFFFFBF00),
        foregroundColor: secondary ? Colors.white70 : Colors.black,
        minimumSize: const Size(110, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
