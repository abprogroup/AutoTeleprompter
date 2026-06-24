part of 'app_settings_screen.dart';

extension _SettingsSections on _AppSettingsScreenState {
  List<Widget> _buildGeneralTab() {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return [
      const _SectionHeader(
        title: 'GENERAL',
        subtitle: 'Mobile-safe defaults for reading and editing.',
      ),
      _SettingsTile(
        icon: Icons.person_outline,
        title: 'Display Name',
        subtitle: settings.displayName,
        onTap: () => unawaited(_editDisplayName(context)),
      ),
      _SegmentTile<String>(
        icon: Icons.language_rounded,
        title: 'Language mode',
        subtitle: 'Default recognition/script language preference.',
        value: settings.languageMode,
        segments: const [
          ButtonSegment(value: 'auto', label: Text('Auto')),
          ButtonSegment(value: 'en', label: Text('EN')),
          ButtonSegment(value: 'he', label: Text('HE')),
        ],
        onChanged: ref.read(settingsProvider.notifier).setLanguageMode,
      ),
      _SettingsTile(
        icon: Icons.file_open_outlined,
        title: 'Import defaults',
        subtitle: settings.lastImportPath.trim().isEmpty
            ? 'iOS document picker opens in its last system location.'
            : 'Last import location remembered by iOS.',
      ),
      _SegmentTile<String>(
        icon: Icons.palette_outlined,
        title: 'Imported script colors',
        subtitle:
            settings.importColorMode == AppSettings.importColorModeDocument
                ? 'Keep document-style light page and dark text after import.'
                : 'Convert imported scripts to prompter contrast after import.',
        value: settings.importColorMode,
        segments: const [
          ButtonSegment(
            value: AppSettings.importColorModePrompter,
            label: Text('Prompter'),
          ),
          ButtonSegment(
            value: AppSettings.importColorModeDocument,
            label: Text('Document'),
          ),
        ],
        onChanged: notifier.setImportColorMode,
      ),
      _SettingsSwitchTile(
        icon: Icons.auto_awesome_rounded,
        title: 'Replay guided walkthrough',
        subtitle: 'Reset lobby, editor, present, and creator walkthrough keys.',
        value: false,
        onChanged: (_) => unawaited(_resetGuidedWalkthrough(context)),
      ),
      _SettingsSwitchTile(
        icon: Icons.bug_report_outlined,
        title: 'Debug Mode',
        subtitle: settings.debugMode
            ? 'Detailed logs and trace tools are visible.'
            : 'Normal mode: heavy debug traces stay off.',
        value: settings.debugMode,
        onChanged: (_) => notifier.toggleDebugMode(),
      ),
      _SettingsSwitchTile(
        icon: Icons.speed_outlined,
        title: 'Reduce motion',
        subtitle: settings.reduceMotion
            ? 'Nonessential animations are reduced for steadier live work.'
            : 'Uses full UI animations; turn on to reduce transitions.',
        value: settings.reduceMotion,
        onChanged: notifier.setReduceMotion,
      ),
      _SliderTile(
        icon: Icons.format_size_outlined,
        title: 'Interface text scale',
        subtitle: 'Affects this Settings screen, not script metadata.',
        value: settings.uiScale,
        min: 0.90,
        max: 1.25,
        divisions: 7,
        valueLabel: '${(settings.uiScale * 100).round()}%',
        onChanged: notifier.setUiScale,
      ),
      const SizedBox(height: 22),
      ..._buildUpdatesSection(),
      const SizedBox(height: 22),
      ..._buildMediaSection(),
      const SizedBox(height: 22),
      ..._buildSpeechSection(),
    ];
  }

  List<Widget> _buildUpdatesSection() {
    final result = _updateResult;
    final available = result?.status == UpdateCheckStatus.updateAvailable;
    return [
      const _SectionHeader(
        title: 'UPDATES',
        subtitle:
            'Updates arrive automatically through the App Store / TestFlight. '
            'You can also check here for a newer published version.',
      ),
      _SettingsTile(
        icon: _checkingForUpdate
            ? Icons.hourglass_empty_rounded
            : (available
                ? Icons.system_update_alt_rounded
                : Icons.update_rounded),
        iconColor: available ? const Color(0xFFFFBF00) : Colors.white54,
        title:
            _checkingForUpdate ? 'Checking for updates…' : 'Check for updates',
        subtitle: result == null
            ? 'Compares this build against the version on the App Store.'
            : '${result.message}'
                '${result.latestVersion != null ? '\nLatest: ${result.latestVersion} • Current: ${result.currentVersion}' : ''}',
        onTap: _checkingForUpdate ? null : () => unawaited(_checkForUpdates()),
      ),
      if (available && result!.hasStorePage)
        _SettingsTile(
          icon: Icons.shop_rounded,
          iconColor: const Color(0xFFFFBF00),
          title: 'Update in the App Store',
          subtitle: 'Opens the App Store so you can tap Update.',
          onTap: () => unawaited(_openAppStore(result.appStoreUrl!)),
        ),
    ];
  }

  List<Widget> _buildAccountTab() {
    final auth = ref.watch(authProvider);
    final signedIn = auth.isSignedIn;
    return [
      const _SectionHeader(
        title: 'ACCOUNT',
        subtitle: 'Connection, password, identity, and local sign-out.',
      ),
      _SettingsTile(
        icon: auth.hasPremiumAccess
            ? Icons.verified_rounded
            : Icons.workspace_premium_outlined,
        iconColor: const Color(0xFFFFBF00),
        title: auth.hasPremiumAccess ? 'Pro account' : 'Free account',
        subtitle: _accountSubtitle(auth),
        onTap: signedIn ? null : () => _openLogin(context),
      ),
      _SettingsSwitchTile(
        icon: Icons.remember_me_outlined,
        title: 'Remember this account',
        subtitle: 'Keep the backend session on this iPhone between launches.',
        value: auth.rememberMe,
        onChanged: ref.read(authProvider.notifier).setBackendRememberMe,
      ),
      if (!signedIn)
        _SettingsTile(
          icon: Icons.login_rounded,
          title: 'Sign in with password',
          subtitle: 'Use account email and password instead of email code.',
          onTap: () => _openLogin(context),
        )
      else ...[
        _SettingsTile(
          icon: Icons.password_rounded,
          title: 'Set or change password',
          subtitle: 'Update the password for ${auth.email ?? 'this account'}.',
          onTap: _setOrChangePassword,
        ),
        _SettingsTile(
          icon: Icons.alternate_email_rounded,
          title: 'Change email',
          subtitle: 'Requires current password and an email confirmation code.',
          onTap: _changeEmailWithCode,
        ),
        _SettingsTile(
          icon: Icons.logout_rounded,
          title: 'Sign out',
          subtitle: 'Local scripts and settings stay on this iPhone.',
          onTap: () => unawaited(_confirmSignOut(context)),
        ),
      ],
      _SettingsTile(
        icon: Icons.lock_reset_rounded,
        title: 'Reset password',
        subtitle: 'Request a reset code and set a new password.',
        onTap: _resetPasswordWithCode,
      ),
      if (signedIn)
        _SettingsTile(
          icon: Icons.delete_forever_outlined,
          iconColor: Colors.redAccent,
          title: 'Delete account',
          subtitle: 'Permanent backend account deletion. Local files remain.',
          onTap: _deleteAccount,
        ),
      const SizedBox(height: 22),
      ..._accountSubscriptionSection(auth),
      const SizedBox(height: 22),
      ..._buildPrivacySection(),
    ];
  }

  List<Widget> _buildRemoteTab() {
    final auth = ref.watch(authProvider);
    final remote = ref.watch(remoteControlProvider);
    final profiles = remote.controllerProfiles;
    if (!auth.hasPremiumAccess) {
      return [
        const _SectionHeader(title: 'REMOTE CONTROL'),
        _SettingsTile(
          icon: Icons.lock_outline_rounded,
          title: 'Remote requires Pro',
          subtitle:
              'Sign in with a Pro account to start iPhone remote control.',
          onTap: () => _openLogin(context),
        ),
      ];
    }
    final defaultUrl = _remoteUrlFor(remote, remote.defaultProfileId);
    return [
      const _SectionHeader(
        title: 'CONTROL ANOTHER DEVICE',
        subtitle:
            'Use this phone as the controller for another device running '
            'AutoTeleprompter on the same Wi-Fi.',
      ),
      _SettingsTile(
        icon: Icons.cast_connected_rounded,
        iconColor: const Color(0xFFFFBF00),
        title: 'Control another device',
        subtitle: 'Enter the host URL + PIN and drive its present mode in-app.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RemoteControllerScreen()),
        ),
      ),
      const SizedBox(height: 22),
      const _SectionHeader(
        title: 'HOST (BE CONTROLLED)',
        subtitle:
            'Host the link so a laptop or another phone on the same Wi-Fi can '
            'drive this device. Pick one role at a time.',
      ),
      _SettingsTile(
        icon: remote.isRunning
            ? Icons.stop_circle_outlined
            : Icons.play_circle_outline_rounded,
        iconColor:
            remote.isRunning ? const Color(0xFFFFBF00) : Colors.white54,
        title: remote.isRunning
            ? 'Stop hosting remote'
            : 'Host remote on this device',
        subtitle: remote.isRunning
            ? '$defaultUrl\n${remote.connectedClientCount} connected client(s)'
            : 'Starts the local Wi-Fi server so another device can control this one.',
        onTap: () async {
          if (remote.isRunning) {
            await remote.stop();
          } else {
            await remote.start();
            await _refreshRemoteUrl(remote.defaultProfileId);
          }
        },
      ),
      if (remote.isRunning)
        _SettingsTile(
          icon: Icons.copy_all_rounded,
          title: 'Copy control link',
          subtitle: 'Share $defaultUrl with the controlling device.',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: defaultUrl));
            _showSnack('Remote URL copied.');
          },
        ),
      _SettingsTile(
        icon: Icons.add_circle_outline_rounded,
        title: 'Add remote profile',
        subtitle: 'Create another controller link for a second device.',
        onTap: () {
          remote.createControllerProfile();
          _showSnack('Remote profile added.');
        },
      ),
      for (final profile in profiles) _remoteProfileTile(remote, profile),
      const _SettingsTile(
        icon: Icons.wifi_tethering_rounded,
        title: 'Local network note',
        subtitle:
            'iOS may ask for Local Network access the first time another device connects.',
      ),
    ];
  }

  Widget _remoteProfileTile(
    RemoteControlService remote,
    RemoteControllerProfile profile,
  ) {
    final url = _remoteUrlFor(remote, profile.id);
    final status = profile.isRunning
        ? '$url\nPIN ${profile.pairingPin} • ${profile.connectedClientCount} client(s)'
        : 'Stopped';
    return _SettingsTile(
      icon: profile.isRunning
          ? Icons.settings_remote_rounded
          : Icons.settings_remote_outlined,
      iconColor: profile.isRunning ? const Color(0xFFFFBF00) : Colors.white54,
      title: profile.name,
      subtitle: status,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
        color: const Color(0xFF1A1A1A),
        onSelected: (action) => unawaited(
          _handleRemoteProfileAction(remote, profile, url, action),
        ),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: profile.isRunning ? 'stop' : 'start',
            child: Text(profile.isRunning ? 'Stop' : 'Start'),
          ),
          const PopupMenuItem(value: 'copy', child: Text('Copy URL')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (profile.isRunning)
            const PopupMenuItem(value: 'revoke', child: Text('Revoke PIN')),
          if (remote.controllerProfiles.length > 1)
            const PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }

  Future<void> _handleRemoteProfileAction(
    RemoteControlService remote,
    RemoteControllerProfile profile,
    String url,
    String action,
  ) async {
    switch (action) {
      case 'start':
        await remote.startControllerProfile(profile.id);
        await _refreshRemoteUrl(profile.id);
        _showSnack('${profile.name} started.');
      case 'stop':
        await remote.stopControllerProfile(profile.id);
        _showSnack('${profile.name} stopped.');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
        _showSnack('Remote URL copied.');
      case 'rename':
        final name = await _textInputDialog(
          title: 'Rename remote',
          label: 'Profile name',
          initialValue: profile.name,
          actionLabel: 'Rename',
        );
        if (name == null) return;
        final ok = remote.renameControllerProfile(profile.id, name);
        _showSnack(ok ? 'Remote renamed.' : 'That name is already used.');
      case 'revoke':
        await remote.revokeControllerProfile(profile.id);
        _showSnack('PIN revoked and clients disconnected.');
      case 'remove':
        await remote.removeControllerProfile(profile.id);
        _showSnack('Remote profile removed.');
    }
  }

  List<Widget> _buildSpeechSection() {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return [
      const _SectionHeader(
        title: 'STT / SPEECH',
        subtitle: 'Same profile model used by present, recording, and remote.',
      ),
      _SettingsSwitchTile(
        icon: Icons.graphic_eq_rounded,
        title: 'Listening meter',
        subtitle: settings.showSoundLevelMeter
            ? 'Show microphone level while listening.'
            : 'Hidden unless debug tools are open.',
        value: settings.showSoundLevelMeter,
        onChanged: notifier.setShowSoundLevelMeter,
      ),
      _SettingsSwitchTile(
        icon: Icons.tune_rounded,
        title: 'Manual STT profile',
        subtitle: 'Use custom thresholds instead of the default profile.',
        value: settings.sttManualProfileEnabled,
        onChanged: notifier.setSttManualProfileEnabled,
      ),
      _SettingsSwitchTile(
        icon: Icons.format_list_bulleted_rounded,
        title: 'Strict bullet/header mode',
        subtitle: 'Require stronger matches around structured script text.',
        value: settings.sttStrictBulletMode,
        onChanged: notifier.setSttStrictBulletMode,
      ),
      _SettingsSwitchTile(
        icon: Icons.visibility_rounded,
        title: 'Visible skip detection',
        subtitle: 'Allow relock to strongly matched text in the visible area.',
        value: settings.sttVisibleSkipEnabled,
        onChanged: notifier.setSttVisibleSkipEnabled,
      ),
      _SettingsSwitchTile(
        icon: Icons.ads_click_rounded,
        title: 'Hard visible skip',
        subtitle: 'Use Windows-compatible hard skip when default profile runs.',
        value: settings.sttHardVisibleSkipEnabled,
        onChanged: notifier.setSttHardVisibleSkipEnabled,
      ),
      _StepperTile(
        icon: Icons.short_text_rounded,
        title: 'Start advance small words',
        subtitle: 'Words required before first normal advance.',
        value: settings.sttManualStartAdvanceSmallWords,
        min: 2,
        max: 8,
        onChanged: notifier.setSttManualStartAdvanceSmallWords,
      ),
      _StepperTile(
        icon: Icons.text_fields_rounded,
        title: 'Start advance big words',
        subtitle: 'Big words required before first normal advance.',
        value: settings.sttManualStartAdvanceBigWords,
        min: 1,
        max: 8,
        onChanged: notifier.setSttManualStartAdvanceBigWords,
      ),
      _StepperTile(
        icon: Icons.health_and_safety_outlined,
        title: 'Safety small words',
        subtitle: 'Small-word evidence for safety recovery.',
        value: settings.sttManualSafetySmallWords,
        min: 1,
        max: 5,
        onChanged: notifier.setSttManualSafetySmallWords,
      ),
      _StepperTile(
        icon: Icons.shield_outlined,
        title: 'Safety big words',
        subtitle: 'Big-word evidence for safety recovery.',
        value: settings.sttManualSafetyBigWords,
        min: 1,
        max: 5,
        onChanged: notifier.setSttManualSafetyBigWords,
      ),
      _StepperTile(
        icon: Icons.open_in_full_rounded,
        title: 'Visible skip small words',
        subtitle: 'Set 0 to disable manual visible skip.',
        value: settings.sttManualVisibleSkipSmallWords,
        min: 0,
        max: 8,
        onChanged: notifier.setSttManualVisibleSkipSmallWords,
      ),
      _StepperTile(
        icon: Icons.open_in_full_rounded,
        title: 'Visible skip big words',
        subtitle: 'Set 0 to disable manual visible skip.',
        value: settings.sttManualVisibleSkipBigWords,
        min: 0,
        max: 8,
        onChanged: notifier.setSttManualVisibleSkipBigWords,
      ),
      _StepperTile(
        icon: Icons.straighten_rounded,
        title: 'Big word length',
        subtitle: 'Minimum letters that count as a big word.',
        value: settings.sttManualBigWordMinLetters,
        min: 3,
        max: 10,
        onChanged: notifier.setSttManualBigWordMinLetters,
      ),
      _SettingsSwitchTile(
        icon: Icons.pan_tool_alt_outlined,
        title: 'Manual scroll while listening',
        subtitle: 'When enabled, releasing scroll relocks to the reading line.',
        value: settings.allowScrollDuringActiveSession,
        onChanged: notifier.setAllowScrollDuringActiveSession,
      ),
    ];
  }

  List<Widget> _buildMediaSection() {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return [
      const _SectionHeader(
        title: 'MEDIA / RECORDING',
        subtitle: 'Content Creator defaults for camera and audio workflows.',
      ),
      _SegmentTile<String>(
        icon: Icons.movie_creation_outlined,
        title: 'Creator recording format',
        subtitle: 'Default capture mode when opening creator tools.',
        value: settings.contentCreatorRecordingFormat,
        segments: const [
          ButtonSegment(value: 'mp4', label: Text('Video')),
          ButtonSegment(value: 'audio', label: Text('Audio')),
        ],
        onChanged: notifier.setContentCreatorRecordingFormat,
      ),
      _SettingsSwitchTile(
        icon: Icons.mic_external_on_outlined,
        title: 'Start speech with recording',
        subtitle: 'Use one clear action to begin recording and speech follow.',
        value: settings.contentCreatorRecordingControlsSpeech,
        onChanged: notifier.setContentCreatorRecordingControlsSpeech,
      ),
      _SegmentTile<String>(
        icon: Icons.high_quality_outlined,
        title: 'Video resolution',
        subtitle: 'Camera recording resolution preference where supported.',
        value: settings.videoResolution,
        segments: const [
          ButtonSegment(value: '480p', label: Text('480')),
          ButtonSegment(value: '720p', label: Text('720')),
          ButtonSegment(value: '1080p', label: Text('1080')),
        ],
        onChanged: notifier.setVideoResolution,
      ),
    ];
  }

  List<Widget> _buildPrivacySection() {
    return [
      const _SectionHeader(
        title: 'PRIVACY / FEEDBACK',
        subtitle: 'Consent details and diagnostic reports.',
      ),
      _SettingsTile(
        icon: Icons.privacy_tip_outlined,
        title: 'Consent details',
        subtitle: 'Review camera, microphone, script, cloud, and feedback use.',
        onTap: _showConsentDetails,
      ),
      _SettingsTile(
        icon: Icons.bug_report_outlined,
        title: 'Send feedback',
        subtitle: 'Send diagnostics with optional script attachment.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FeedbackReportScreen()),
        ),
      ),
    ];
  }
}
