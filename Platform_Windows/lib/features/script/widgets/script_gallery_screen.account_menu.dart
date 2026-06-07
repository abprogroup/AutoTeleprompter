part of 'script_gallery_screen.dart';

class _AccountMenuButton extends ConsumerWidget {
  final AuthState auth;

  const _AccountMenuButton({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (auth.email == null || auth.email!.isEmpty) {
      return IconButton(
        tooltip: 'Activate Pro access',
        icon: const Icon(Icons.login_rounded, color: Colors.white54),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
      );
    }

    final email = auth.email!.trim();
    final settings = ref.watch(settingsProvider);
    final displayName = _accountDisplayName(settings.displayName, email);
    final initial =
        displayName.isEmpty ? 'A' : displayName.characters.first.toUpperCase();
    final badge = auth.isAdmin && auth.hasPremiumAccess
        ? 'Admin'
        : auth.hasPremiumAccess
            ? 'Pro'
            : 'Free';

    return PopupMenuButton<String>(
      tooltip: 'Account',
      color: const Color(0xFF1A1A1A),
      offset: const Offset(0, 46),
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFFFFBF00),
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      onSelected: (value) async {
        if (value == 'settings') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AppSettingsScreen(
                initialTab: AppSettingsTab.account,
              ),
            ),
          );
        } else if (value == 'logout') {
          await ref.read(authProvider.notifier).logout();
          await ref.read(settingsProvider.notifier).resetDisplayNameToGuest();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Signed out from this device.')),
            );
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$badge access',
                style: const TextStyle(
                  color: Color(0xFFFFBF00),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          child: _AccountMenuItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: _AccountMenuItem(
            icon: Icons.logout_rounded,
            label: 'Sign out',
          ),
        ),
      ],
    );
  }

  String _accountDisplayName(String savedName, String email) {
    final name = savedName.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'guest') return name;
    final prefix = email.split('@').first.trim();
    return prefix.isEmpty ? 'Guest' : prefix;
  }
}

class _AccountMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AccountMenuItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
