part of 'app_settings_screen.dart';

extension _AccountDangerSettings on _AppSettingsScreenState {
  List<Widget> _accountDangerSection(AuthState auth) {
    return [
      const SizedBox(height: 22),
      const _SectionHeader(title: 'DANGER'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.delete_forever_outlined,
        title: 'Delete account and data',
        subtitle: 'Permanently removes the backend account and signs out',
        onTap: () => _showDeleteAccountDialog(auth),
      ),
    ];
  }

  void _showDeleteAccountDialog(AuthState auth) {
    final confirmationController = TextEditingController();
    final email = auth.email?.trim() ?? '';
    var busy = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Delete account and data',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes the backend account, account profile, '
                'entitlement rows, device sessions, and local login session. '
                'Local scripts on this PC are preserved.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Text(
                email.isEmpty
                    ? 'Type DELETE to confirm.'
                    : 'Type your account email or DELETE to confirm.',
                style: const TextStyle(color: Color(0xFFFFBF00)),
              ),
              const SizedBox(height: 10),
              _AccountDialogTextField(
                controller: confirmationController,
                label: email.isEmpty ? 'DELETE' : email,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final confirmation = confirmationController.text.trim();
                      final confirmed = confirmation == 'DELETE' ||
                          (email.isNotEmpty &&
                              confirmation.toLowerCase() ==
                                  email.toLowerCase());
                      if (!confirmed) {
                        _showAccountSnack('Confirmation does not match.');
                        return;
                      }
                      final dialogNavigator = Navigator.of(ctx);
                      setDialogState(() => busy = true);
                      try {
                        await ref
                            .read(authProvider.notifier)
                            .deleteBackendAccount(
                              confirmation: confirmation,
                            );
                        await ref
                            .read(settingsProvider.notifier)
                            .resetDisplayNameToGuest();
                        if (!mounted) return;
                        dialogNavigator.pop();
                        _showAccountSnack('Account deleted and signed out.');
                      } catch (error) {
                        if (mounted) {
                          setDialogState(() => busy = false);
                          _showAccountSnack(_accountBackendMessage(error));
                        }
                      }
                    },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
