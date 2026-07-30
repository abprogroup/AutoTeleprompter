part of 'app_settings_screen.dart';

/// Remote Control settings tab. Ported from Windows' `_remoteTab` +
/// `app_settings_screen.remote_profiles.dart`/`.tiles.dart` (the
/// `_RemoteControlTile`/`_RemoteProfilesTile`/`_RemoteProfileRow` pieces).
/// Windows gates this whole feature behind `Platform.isWindows` (always true
/// there) - Android doesn't need that gate at all, the feature works the
/// same way over the local network on any platform, so it's always shown.
/// The only real adaptation: opening a remote's URL uses `url_launcher`
/// instead of Windows' `Process.run('cmd', ['/c', 'start', url])`.
extension _RemoteProfileSettingsActions on _AppSettingsScreenState {
  List<Widget> _remoteTab(RemoteControlService remote) {
    final profiles = remote.controllerProfiles;
    final selectedProfile = _selectedRemoteProfile(remote, profiles);
    final selectedUrl = _remoteUrlProfileId == selectedProfile.id
        ? _remoteUrl ?? remote.remoteUrlForProfile(selectedProfile.id)
        : remote.remoteUrlForProfile(selectedProfile.id);

    return [
      const _SectionHeader(title: 'REMOTE CONTROL'),
      const SizedBox(height: 8),
      _RemoteControlTile(
        title: selectedProfile.name,
        isRunning: selectedProfile.isRunning,
        isBusy: _remoteBusy,
        url: selectedUrl,
        pairingPin: selectedProfile.pairingPin,
        connectedClientCount: selectedProfile.connectedClientCount,
        sessionExpiresAt: selectedProfile.sessionTokenExpiresAt,
        error: _remoteError,
        onStart: () => _startRemote(selectedProfile.id),
        onStop: () => _stopRemote(selectedProfile.id),
        onRename: () => _renameRemoteProfile(selectedProfile),
        onRevoke: () => _revokeRemoteProfile(selectedProfile),
        onCopy: () => _copyRemoteProfileUrl(selectedProfile),
        onOpen: () => _openRemoteProfileUrl(selectedProfile),
      ),
      const SizedBox(height: 8),
      _RemoteProfilesTile(
        profiles: profiles,
        selectedProfileId: selectedProfile.id,
        onSelect: _selectRemoteProfile,
        onAdd: _addRemoteProfile,
        onRename: _renameRemoteProfile,
        onStart: _startRemoteProfile,
        onStop: _stopRemoteProfile,
        onRemove: _removeRemoteProfile,
        onRevoke: _revokeRemoteProfile,
        onCopy: _copyRemoteProfileUrl,
        onOpen: _openRemoteProfileUrl,
      ),
    ];
  }

  RemoteControllerProfile _selectedRemoteProfile(
    RemoteControlService remote,
    List<RemoteControllerProfile> profiles,
  ) {
    if (profiles.isEmpty) {
      remote.createControllerProfile();
      return remote.controllerProfiles.first;
    }
    final selectedId = _selectedRemoteProfileId;
    if (selectedId != null) {
      for (final profile in profiles) {
        if (profile.id == selectedId) return profile;
      }
    }
    final fallbackId = remote.hasControllerProfile(remote.defaultProfileId)
        ? remote.defaultProfileId
        : profiles.first.id;
    _selectedRemoteProfileId = fallbackId;
    return profiles.firstWhere(
      (profile) => profile.id == fallbackId,
      orElse: () => profiles.first,
    );
  }

  void _selectRemoteProfile(RemoteControllerProfile profile) {
    _setSelectedRemoteProfile(profile.id, clearError: true);
    unawaited(_refreshRemoteUrl(profile.id));
  }

  void _setSelectedRemoteProfile(String? profileId, {bool clearError = false}) {
    setState(() {
      _selectedRemoteProfileId = profileId;
      _remoteUrl = null;
      _remoteUrlProfileId = null;
      if (clearError) _remoteError = null;
    });
  }

  Future<void> _refreshRemoteUrl([String? profileId]) async {
    if (!mounted) return;
    final remote = ref.read(remoteControlProvider);
    final selectedId = profileId ??
        _selectedRemoteProfileId ??
        (remote.controllerProfiles.isEmpty
            ? remote.defaultProfileId
            : remote.controllerProfiles.first.id);
    final selectedProfile = remote.controllerProfiles.firstWhere(
      (profile) => profile.id == selectedId,
      orElse: () => remote.controllerProfiles.first,
    );
    final url = selectedProfile.isRunning
        ? await remote.preferredUrlForProfile(selectedId)
        : remote.remoteUrlForProfile(selectedId);
    if (!mounted) return;
    setState(() {
      _remoteUrl = url;
      _remoteUrlProfileId = selectedId;
      _remoteError = null;
    });
  }

  Future<void> _startRemote([String? profileId]) async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    final remote = ref.read(remoteControlProvider);
    final selectedId =
        profileId ?? _selectedRemoteProfileId ?? remote.defaultProfileId;
    try {
      await remote.startControllerProfile(selectedId);
      final url = await remote.preferredUrlForProfile(selectedId);
      if (!mounted) return;
      setState(() {
        _remoteUrl = url;
        _remoteUrlProfileId = selectedId;
      });
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.remoteStart',
      );
      if (!mounted) return;
      setState(() {
        _remoteError = 'Remote control could not start. Ports 8080-8090 may '
            'already be in use.';
      });
    } finally {
      if (mounted) setState(() => _remoteBusy = false);
    }
  }

  Future<void> _stopRemote([String? profileId]) async {
    if (_remoteBusy) return;
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
    });
    final remote = ref.read(remoteControlProvider);
    final selectedId =
        profileId ?? _selectedRemoteProfileId ?? remote.defaultProfileId;
    await remote.stopControllerProfile(selectedId);
    if (!mounted) return;
    setState(() {
      _remoteBusy = false;
      _remoteUrl = remote.remoteUrlForProfile(selectedId);
      _remoteUrlProfileId = selectedId;
    });
  }

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
        title: Text('Remove ${profile.name}?',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'This removes this remote profile and disconnects only its paired '
          'controllers. Other remotes keep working.',
          style: TextStyle(color: Colors.white70),
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
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.remoteProfileOpenUrl',
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
        title: Text(title, style: const TextStyle(color: Colors.white)),
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

class _RemoteControlTile extends StatelessWidget {
  final String title;
  final bool isRunning;
  final bool isBusy;
  final String url;
  final String pairingPin;
  final int connectedClientCount;
  final DateTime? sessionExpiresAt;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRename;
  final VoidCallback onRevoke;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  const _RemoteControlTile({
    required this.title,
    required this.isRunning,
    required this.isBusy,
    required this.url,
    required this.pairingPin,
    required this.connectedClientCount,
    required this.sessionExpiresAt,
    required this.error,
    required this.onStart,
    required this.onStop,
    required this.onRename,
    required this.onRevoke,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final status = isRunning ? 'Running at $url' : 'Stopped';
    final statusColor = isRunning ? const Color(0xFFFFBF00) : Colors.white38;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRunning
                    ? Icons.settings_remote_rounded
                    : Icons.settings_remote_outlined,
                color: Colors.white54,
                size: 22,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Phone/browser controller for Present mode',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Rename selected remote',
                visualDensity: VisualDensity.compact,
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFFBF00),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(status, style: TextStyle(color: statusColor, fontSize: 12)),
          if (isRunning && pairingPin.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Pairing PIN: $pairingPin',
              style: const TextStyle(
                color: Color(0xFFFFBF00),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Only devices with this session PIN can control the prompter.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Connected remotes: $connectedClientCount',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (sessionExpiresAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Session token expires: ${_formatRemoteExpiry(sessionExpiresAt!)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 8),
          const Text(
            'Use only on a trusted local network. Stop remote control when the '
            'phone/browser controller is no longer needed.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isBusy ? null : (isRunning ? onStop : onStart),
                icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow),
                label: Text(isRunning ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
              ),
              OutlinedButton.icon(
                onPressed: isRunning ? onCopy : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy URL'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFBF00),
                  side: const BorderSide(color: Color(0xFFFFBF00)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: isRunning && !isBusy ? onRevoke : null,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('New PIN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRemoteExpiry(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
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
        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                ? const Color(0xFFFFBF00).withOpacity(.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFBF00).withOpacity(.32)
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
                  color: const Color(0xFFFFBF00).withOpacity(.12),
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
