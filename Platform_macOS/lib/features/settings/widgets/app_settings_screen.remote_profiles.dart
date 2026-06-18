part of 'app_settings_screen.dart';

extension _RemoteProfileSettingsActions on _AppSettingsScreenState {
  Future<void> _addRemoteProfile() async {
    final name = await _askRemoteProfileName(
      title: 'Add remote',
      initialValue: ref.read(remoteControlProvider).nextAvailableProfileName(),
    );
    if (name == null) return;
    final remote = ref.read(remoteControlProvider);
    if (!remote.isProfileNameAvailable(name)) {
      _showRemoteNameDuplicate(name);
      return;
    }
    final id = remote.createControllerProfile(name);
    _setSelectedRemoteProfile(id);
    await _refreshRemoteUrl(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Created ${remote.controllerProfiles.firstWhere((p) => p.id == id).name}.')),
    );
  }

  Future<void> _renameRemoteProfile(RemoteControllerProfile profile) async {
    final name = await _askRemoteProfileName(
      title: 'Rename remote',
      initialValue: profile.name,
    );
    if (name == null) return;
    final renamed = ref
        .read(remoteControlProvider)
        .renameControllerProfile(profile.id, name);
    if (!renamed) {
      _showRemoteNameDuplicate(name);
      return;
    }
    await _refreshRemoteUrl(profile.id);
  }

  Future<void> _startRemoteProfile(RemoteControllerProfile profile) async {
    _setSelectedRemoteProfile(profile.id, clearError: true);
    await _startRemote(profile.id);
  }

  Future<void> _stopRemoteProfile(RemoteControllerProfile profile) async {
    _setSelectedRemoteProfile(profile.id, clearError: true);
    await _stopRemote(profile.id);
  }

  Future<void> _removeRemoteProfile(RemoteControllerProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: Text('Remove ${profile.name}?'),
        content: const Text(
          'This removes this remote profile and disconnects only its paired '
          'controllers. Other remotes keep working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(remoteControlProvider).removeControllerProfile(profile.id);
    final remote = ref.read(remoteControlProvider);
    if (_selectedRemoteProfileId == profile.id) {
      _setSelectedRemoteProfile(remote.defaultProfileId);
    }
    await _refreshRemoteUrl(_selectedRemoteProfileId);
  }

  Future<void> _revokeRemoteProfile(RemoteControllerProfile profile) async {
    await ref.read(remoteControlProvider).revokeControllerProfile(profile.id);
    await _refreshRemoteUrl();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${profile.name} received a new PIN.')),
    );
  }

  Future<void> _copyRemoteProfileUrl(RemoteControllerProfile profile) async {
    final url = await ref
        .read(remoteControlProvider)
        .preferredUrlForProfile(profile.id);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${profile.name} link copied.')),
    );
  }

  Future<void> _openRemoteProfileUrl(RemoteControllerProfile profile) async {
    final url = await ref
        .read(remoteControlProvider)
        .preferredUrlForProfile(profile.id);
    try {
      final opened = await ExternalUrlLauncher.openUrl(url);
      if (!opened) {
        throw StateError('External launcher reported failure for $url');
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.remoteProfileOpenUrl',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remote link could not be opened.')),
      );
    }
  }

  Future<String?> _askRemoteProfileName({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Remote name',
            hintText: 'Director phone',
          ),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final clean = result?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  void _showRemoteNameDuplicate(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('A remote named "$name" already exists.')),
    );
  }
}

class _RemoteProfilesTile extends StatelessWidget {
  final List<RemoteControllerProfile> profiles;
  final String selectedProfileId;
  final ValueChanged<RemoteControllerProfile> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<RemoteControllerProfile> onRename;
  final ValueChanged<RemoteControllerProfile> onStart;
  final ValueChanged<RemoteControllerProfile> onStop;
  final ValueChanged<RemoteControllerProfile> onRemove;
  final ValueChanged<RemoteControllerProfile> onRevoke;
  final ValueChanged<RemoteControllerProfile> onCopy;
  final ValueChanged<RemoteControllerProfile> onOpen;

  const _RemoteProfilesTile({
    required this.profiles,
    required this.selectedProfileId,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onStart,
    required this.onStop,
    required this.onRemove,
    required this.onRevoke,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.devices_other_outlined,
                color: Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Named remotes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Create separate PINs for phones, tablets, or operators.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final profile in profiles) ...[
            _RemoteProfileRow(
              profile: profile,
              selected: profile.id == selectedProfileId,
              canRemove: profiles.length > 1,
              onSelect: () => onSelect(profile),
              onRename: () => onRename(profile),
              onStart: () => onStart(profile),
              onStop: () => onStop(profile),
              onRemove: () => onRemove(profile),
              onRevoke: () => onRevoke(profile),
              onCopy: () => onCopy(profile),
              onOpen: () => onOpen(profile),
            ),
            if (profile != profiles.last) const Divider(color: Colors.white12),
          ],
        ],
      ),
    );
  }
}

class _RemoteProfileRow extends StatelessWidget {
  final bool selected;
  final bool canRemove;
  final RemoteControllerProfile profile;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRemove;
  final VoidCallback onRevoke;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  const _RemoteProfileRow({
    required this.selected,
    required this.canRemove,
    required this.profile,
    required this.onSelect,
    required this.onRename,
    required this.onStart,
    required this.onStop,
    required this.onRemove,
    required this.onRevoke,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFFBF00).withValues(alpha: .08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFBF00).withValues(alpha: .32)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFBF00).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.settings_remote_rounded,
                  color: Color(0xFFFFBF00),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.isRunning
                          ? 'PIN ${profile.pairingPin} - '
                              '${profile.connectedClientCount} connected'
                          : 'Stopped. Start this remote when needed.',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: profile.isRunning
                        ? 'Stop this remote'
                        : 'Start this remote',
                    visualDensity: VisualDensity.compact,
                    onPressed: profile.isRunning ? onStop : onStart,
                    icon: Icon(
                      profile.isRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename remote',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Copy this remote link',
                    visualDensity: VisualDensity.compact,
                    onPressed: profile.isRunning ? onCopy : null,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Open this remote',
                    visualDensity: VisualDensity.compact,
                    onPressed: profile.isRunning ? onOpen : null,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'New PIN for this remote',
                    visualDensity: VisualDensity.compact,
                    onPressed: profile.isRunning ? onRevoke : null,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Remove remote',
                    visualDensity: VisualDensity.compact,
                    onPressed: canRemove ? onRemove : null,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
