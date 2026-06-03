part of 'app_settings_screen.dart';

extension _AppSettingsMediaDefaults on _AppSettingsScreenState {
  List<Widget> _mediaDefaultsSection(AppSettings settings) {
    final tState = ref.watch(teleprompterProvider);
    return [
      const _SectionHeader(title: 'MEDIA DEFAULTS'),
      const SizedBox(height: 8),
      _SettingsActionsTile(
        icon: Icons.videocam_outlined,
        title: 'Default video camera',
        subtitle: _defaultCameraLabel(settings),
        actions: [
          _SettingsAction(
            icon: Icons.videocam_outlined,
            label: 'Choose camera',
            onPressed: _chooseDefaultCamera,
          ),
          _SettingsAction(
            icon: Icons.restart_alt_rounded,
            label: 'Use automatic',
            onPressed: () => _setDefaultCamera(''),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _SettingsActionsTile(
        icon: Icons.mic_external_on_outlined,
        title: 'Default microphone',
        subtitle: _defaultMicLabel(settings),
        actions: [
          _SettingsAction(
            icon: Icons.mic_external_on_outlined,
            label: 'Choose mic',
            onPressed: () => _chooseDefaultMic(tState.audioInputDevices),
          ),
          _SettingsAction(
            icon: Icons.refresh_rounded,
            label: 'Refresh',
            onPressed: _refreshMicDevices,
          ),
          _SettingsAction(
            icon: Icons.restart_alt_rounded,
            label: 'Use system default',
            onPressed: () => _setDefaultMic('', 'System default microphone'),
          ),
        ],
      ),
    ];
  }

  String _defaultCameraLabel(AppSettings settings) {
    final name = settings.defaultCameraDeviceName.trim();
    return name.isEmpty
        ? 'Automatic: Content Creator chooses the best available camera'
        : _cameraDisplayName(name);
  }

  String _defaultMicLabel(AppSettings settings) {
    final label = settings.sttInputDeviceLabel.trim();
    return label.isEmpty ? 'System default microphone' : label;
  }

  Future<void> _chooseDefaultCamera() async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.defaultCamera.list',
      );
      _showSettingsSnack('Could not list Windows cameras.');
      return;
    }
    if (!mounted) return;
    final selectedName = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          'Default video camera',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 520,
          child: cameras.isEmpty
              ? const Text(
                  'No Windows cameras were found.',
                  style: TextStyle(color: Colors.white70),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _selectionTile(
                        selected: ref
                            .read(settingsProvider)
                            .defaultCameraDeviceName
                            .isEmpty,
                        title: 'Automatic',
                        subtitle: 'Let Content Creator choose the best camera.',
                        onTap: () => Navigator.pop(context, ''),
                      ),
                      for (final camera in cameras)
                        _selectionTile(
                          selected: ref
                                  .read(settingsProvider)
                                  .defaultCameraDeviceName ==
                              camera.name,
                          title: _cameraDisplayName(camera.name),
                          subtitle: camera.lensDirection.name,
                          onTap: () => Navigator.pop(context, camera.name),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selectedName == null) return;
    await _setDefaultCamera(selectedName);
  }

  Future<void> _setDefaultCamera(String cameraName) async {
    await ref
        .read(settingsProvider.notifier)
        .setDefaultCameraDeviceName(cameraName);
    _showSettingsSnack(
      cameraName.trim().isEmpty
          ? 'Default video camera set to automatic.'
          : 'Default video camera updated.',
    );
  }

  Future<void> _chooseDefaultMic(List<SttAudioInputDevice> knownDevices) async {
    var devices = knownDevices;
    if (devices.isEmpty) {
      await _refreshMicDevices(showSnack: false);
      devices = ref.read(teleprompterProvider).audioInputDevices;
    }
    if (!mounted) return;
    final selectedId = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          'Default microphone',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                _selectionTile(
                  selected: ref.read(settingsProvider).sttInputDeviceId.isEmpty,
                  title: 'System default microphone',
                  onTap: () => Navigator.pop(context, ''),
                ),
                for (final device in devices)
                  _selectionTile(
                    selected: ref.read(settingsProvider).sttInputDeviceId ==
                        device.id,
                    title: device.label,
                    onTap: () => Navigator.pop(context, device.id),
                  ),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No inputs discovered yet. Use Refresh, or start STT once.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selectedId == null) return;
    final label = selectedId.isEmpty
        ? 'System default microphone'
        : devices
            .firstWhere(
              (device) => device.id == selectedId,
              orElse: () => SttAudioInputDevice(
                id: selectedId,
                label: ref.read(settingsProvider).sttInputDeviceLabel,
              ),
            )
            .label;
    await _setDefaultMic(selectedId, label);
  }

  Future<void> _setDefaultMic(String deviceId, String label) async {
    await ref.read(settingsProvider.notifier).setSttInputDevice(
          deviceId,
          label,
        );
    ref.read(teleprompterProvider.notifier).setSttInputDevice(deviceId, label);
    _showSettingsSnack('Default microphone updated.');
  }

  Widget _selectionTile({
    required bool selected,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? const Color(0xFFFFBF00) : Colors.white38,
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white38),
            ),
    );
  }

  String _cameraDisplayName(String rawName) {
    var visible = rawName.replaceAll(RegExp(r'[\x00-\x1F]'), ' ');
    for (final marker in ['<', r'\\?\', r'\root#', r'\usb#', '#vid_']) {
      final index = visible.toLowerCase().indexOf(marker.toLowerCase());
      if (index > 0) visible = visible.substring(0, index);
    }
    final withoutMoniker = visible.replaceAll(RegExp(r'\s+'), ' ').trim();
    return withoutMoniker.isEmpty ? 'Unknown camera' : withoutMoniker;
  }

  Future<void> _refreshMicDevices({bool showSnack = true}) async {
    await ref.read(teleprompterProvider.notifier).refreshAudioInputDevices();
    if (showSnack) _showSettingsSnack('Microphone list refreshed.');
  }

  void _showSettingsSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
