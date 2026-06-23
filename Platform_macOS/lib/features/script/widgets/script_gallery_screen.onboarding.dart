part of 'script_gallery_screen.dart';

const String _macPremiumFeedbackOnboardingVersion = 'mac-premium-feedback-v1';
const String _walkthroughTempSourceTypeForGallery = 'WALKTHROUGH_TEMP';

const String _walkthroughSampleScript = '''
Welcome to AutoTeleprompter

This is a temporary practice script for your first walkthrough.

Try editing this paragraph, then use Save to give the script a real name. Once
you save it, AutoTeleprompter adds it to Recents so it is ready for your next
session.

When you are ready, press Present and test your reading settings.
''';

class _MacOnboardingStep {
  final String id;
  final IconData icon;
  final String title;
  final String body;
  final bool showsSampleAction;

  const _MacOnboardingStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.body,
    this.showsSampleAction = false,
  });
}

const List<_MacOnboardingStep> _macOnboardingSteps = [
  _MacOnboardingStep(
    id: 'lobby.new_or_load',
    icon: Icons.add_rounded,
    title: 'Start or load a script',
    body:
        'Use New Script for a fresh production, or Load Script to import a document. Recents keeps saved work close for quick access.',
  ),
  _MacOnboardingStep(
    id: 'lobby.recents',
    icon: Icons.history_rounded,
    title: 'Saved scripts return here',
    body:
        'After a script is saved, it appears in Recent Activity for fast access. The temporary walkthrough sample will stay out of this list until you save it.',
  ),
  _MacOnboardingStep(
    id: 'editor.temporary_sample',
    icon: Icons.description_outlined,
    title: 'Practice with a temporary script',
    body:
        'Open the sample script, edit it, rename it, and save it. It stays out of Recents until you save, so the walkthrough stays clean.',
    showsSampleAction: true,
  ),
];

extension _ScriptGalleryOnboardingParts on _ScriptGalleryScreenState {
  void _scheduleMacOnboardingIfNeeded(AppSettings settings) {
    if (!Platform.isMacOS ||
        _macOnboardingVisible ||
        _macOnboardingScheduled ||
        settings.macOnboardingVersionSeen ==
            _macPremiumFeedbackOnboardingVersion) {
      return;
    }
    _macOnboardingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setGalleryState(() {
        _macOnboardingVisible = true;
        _macOnboardingStep = 0;
        _macOnboardingScheduled = false;
      });
    });
  }

  Future<void> _finishMacOnboarding() async {
    await ref
        .read(settingsProvider.notifier)
        .setMacOnboardingVersionSeen(_macPremiumFeedbackOnboardingVersion);
    if (!mounted) return;
    _setGalleryState(() => _macOnboardingVisible = false);
  }

  void _openWalkthroughSampleScript() {
    unawaited(_openWalkthroughSampleScriptAfterLobbyHandoff());
  }

  Future<void> _openWalkthroughSampleScriptAfterLobbyHandoff() async {
    LightweightDiagnostics.instance.record(
      'gallery',
      'walkthrough sample opened',
    );
    _setGalleryState(() {
      _macOnboardingVisible = false;
      _macOnboardingScheduled = false;
    });
    ref.read(scriptProvider.notifier).clear();
    await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
    if (!mounted) return;
    ref.read(scriptProvider.notifier).loadText(
          _walkthroughSampleScript,
          title: 'Welcome to AutoTeleprompter',
          sourceType: _walkthroughTempSourceTypeForGallery,
          persist: false,
        );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ScriptEditorScreen(
          showWalkthroughSampleGuide: true,
        ),
      ),
    );
  }

  Widget _buildMacOnboardingOverlay(AppSettings settings, bool hasProAccess) {
    final step = _macOnboardingSteps[_macOnboardingStep];
    final isFirst = _macOnboardingStep == 0;
    final isLast = _macOnboardingStep == _macOnboardingSteps.length - 1;
    return StableWalkthroughOverlay(
      stepId: step.id,
      target: _macOnboardingTarget(step),
      onClose: () => unawaited(_finishMacOnboarding()),
      cardBuilder: (context, targetRect, constraints) {
        final cardWidth =
            constraints.maxWidth < 760 ? constraints.maxWidth - 32 : 680.0;
        final left = _macOnboardingCardLeft(
          targetRect: targetRect,
          cardWidth: cardWidth,
          maxWidth: constraints.maxWidth,
        );
        final top = _macOnboardingCardTop(
          targetRect: targetRect,
          maxHeight: constraints.maxHeight,
        );
        final bodyMaxHeight =
            (constraints.maxHeight - 230).clamp(120.0, 360.0).toDouble();
        return Positioned(
          left: left,
          top: top,
          width: cardWidth,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight - 40,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xF21A1A1A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 32,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _onboardingHeader(step, hasProAccess),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: bodyMaxHeight,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.body,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                            if (step.showsSampleAction) ...[
                              const SizedBox(height: 18),
                              _sampleScriptPanel(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _onboardingFooter(isFirst: isFirst, isLast: isLast),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  StableWalkthroughTarget? _macOnboardingTarget(_MacOnboardingStep step) {
    switch (step.id) {
      case 'lobby.new_or_load':
        return StableWalkthroughTarget(
          key: _walkthroughScriptActionsKey,
          padding: 10,
          borderRadius: BorderRadius.circular(18),
        );
      case 'lobby.recents':
        return StableWalkthroughTarget(
          key: _walkthroughRecentsKey,
          padding: 10,
          borderRadius: BorderRadius.circular(18),
        );
      default:
        return null;
    }
  }

  double _macOnboardingCardLeft({
    required Rect? targetRect,
    required double cardWidth,
    required double maxWidth,
  }) {
    final target = targetRect;
    if (target == null) return ((maxWidth - cardWidth) / 2).clamp(16.0, 48.0);
    final rightSide = target.right + 24;
    if (rightSide + cardWidth <= maxWidth - 16) return rightSide;
    final leftSide = target.left - cardWidth - 24;
    if (leftSide >= 16) return leftSide;
    return (target.center.dx - cardWidth / 2)
        .clamp(16.0, maxWidth - cardWidth - 16)
        .toDouble();
  }

  double _macOnboardingCardTop({
    required Rect? targetRect,
    required double maxHeight,
  }) {
    if (targetRect == null) {
      return ((maxHeight - 520) / 2).clamp(20.0, 96.0).toDouble();
    }
    final preferred = targetRect.center.dy - 180;
    final maxTop = (maxHeight - 420).clamp(20.0, 160.0).toDouble();
    return preferred.clamp(20.0, maxTop).toDouble();
  }

  Widget _onboardingHeader(_MacOnboardingStep step, bool hasProAccess) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFBF00).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x66FFBF00)),
            ),
            child: Icon(step.icon, color: const Color(0xFFFFBF00), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${step.id}  •  ${_macOnboardingStep + 1}/${_macOnboardingSteps.length}'
                  '${hasProAccess ? '' : '  •  Free mode'}',
                  style: const TextStyle(
                    color: Color(0xFFFFBF00),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Skip walkthrough',
            icon: const Icon(Icons.close_rounded, color: Colors.white54),
            onPressed: () => unawaited(_finishMacOnboarding()),
          ),
        ],
      ),
    );
  }

  Widget _onboardingFooter({required bool isFirst, required bool isLast}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: (_macOnboardingStep + 1) / _macOnboardingSteps.length,
              backgroundColor: Colors.white10,
              color: const Color(0xFFFFBF00),
              minHeight: 3,
            ),
          ),
          const SizedBox(width: 18),
          TextButton(
            onPressed: () => unawaited(_finishMacOnboarding()),
            child: const Text('Skip'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: isFirst
                ? null
                : () => _setGalleryState(() => _macOnboardingStep--),
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              if (isLast) {
                _openWalkthroughSampleScript();
              } else {
                _setGalleryState(() => _macOnboardingStep++);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
            ),
            child: Text(isLast ? 'Open sample' : 'Next'),
          ),
        ],
      ),
    );
  }

  Widget _sampleScriptPanel() {
    return _onboardingPanel(
      icon: Icons.edit_document,
      title: 'Temporary sample',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The sample opens as a temporary editor session. Use Save to choose a file name; after that it appears in Recent Activity.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openWalkthroughSampleScript,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open sample script'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // Retained for the next guided-setup route segment after the lobby/editor
  // walkthrough was split into a continuous cross-screen flow.
  // ignore: unused_element
  Widget _sttSetupPanel(AppSettings settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return _onboardingPanel(
      icon: Icons.tune_rounded,
      title: 'Speech control profile',
      action: TextButton.icon(
        onPressed: () => unawaited(_applyRecommendedSttProfile()),
        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
        label: const Text('Recommended'),
      ),
      child: Column(
        children: [
          _setupSwitch(
            title: 'Use custom speech thresholds',
            value: settings.sttManualProfileEnabled,
            onChanged: notifier.setSttManualProfileEnabled,
          ),
          _setupIntSlider(
            title: 'Long word length',
            subtitle:
                'What word length should count as a long word for speech control?',
            value: settings.sttManualBigWordMinLetters,
            min: 3,
            max: 10,
            onChanged: notifier.setSttManualBigWordMinLetters,
          ),
          _setupIntSlider(
            title: 'Short words before scrolling',
            subtitle:
                'How many recognized short words should AutoTeleprompter hear before it starts scrolling?',
            value: settings.sttManualStartAdvanceSmallWords,
            min: 2,
            max: 8,
            onChanged: notifier.setSttManualStartAdvanceSmallWords,
          ),
          _setupIntSlider(
            title: 'Long words before scrolling',
            subtitle:
                'How many recognized long words should be enough to start scrolling?',
            value: settings.sttManualStartAdvanceBigWords,
            min: 1,
            max: 8,
            onChanged: notifier.setSttManualStartAdvanceBigWords,
          ),
          _setupIntSlider(
            title: 'Missed short words before pause',
            subtitle:
                'If recognition drifts away, how many missed short words should it tolerate?',
            value: settings.sttManualSafetySmallWords,
            min: 1,
            max: 5,
            onChanged: notifier.setSttManualSafetySmallWords,
          ),
          _setupIntSlider(
            title: 'Missed long words before pause',
            subtitle:
                'How many missed long words should it tolerate before pausing?',
            value: settings.sttManualSafetyBigWords,
            min: 1,
            max: 5,
            onChanged: notifier.setSttManualSafetyBigWords,
          ),
          _setupSwitch(
            title: 'Jump to visible text',
            subtitle:
                'Let speech control jump forward when you skip to text already visible on screen.',
            value: settings.sttVisibleSkipEnabled,
            onChanged: notifier.setSttVisibleSkipEnabled,
          ),
          if (settings.sttVisibleSkipEnabled) ...[
            _setupIntSlider(
              title: 'Visible jump short-word match',
              subtitle: 'How many matching short words should confirm a jump?',
              value: settings.sttManualVisibleSkipSmallWords == 0
                  ? 4
                  : settings.sttManualVisibleSkipSmallWords,
              min: 2,
              max: 8,
              onChanged: notifier.setSttManualVisibleSkipSmallWords,
            ),
            _setupIntSlider(
              title: 'Visible jump long-word match',
              subtitle: 'How many matching long words should confirm a jump?',
              value: settings.sttManualVisibleSkipBigWords == 0
                  ? 3
                  : settings.sttManualVisibleSkipBigWords,
              min: 1,
              max: 8,
              onChanged: notifier.setSttManualVisibleSkipBigWords,
            ),
          ],
          _setupSwitch(
            title: 'Allow manual scrolling during STT',
            subtitle:
                'Keep trackpad or mouse scrolling available while speech control is active.',
            value: settings.allowScrollDuringActiveSession,
            onChanged: notifier.setAllowScrollDuringActiveSession,
          ),
        ],
      ),
    );
  }

  // Retained for the next guided-setup route segment after the lobby/editor
  // walkthrough was split into a continuous cross-screen flow.
  // ignore: unused_element
  Widget _contentCreatorSetupPanel(AppSettings settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return _onboardingPanel(
      icon: Icons.video_settings_outlined,
      title: 'Content Creator defaults',
      action: TextButton.icon(
        onPressed: () => unawaited(_applyRecommendedCreatorProfile()),
        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
        label: const Text('Recommended'),
      ),
      child: Column(
        children: [
          _setupChoice<String>(
            title: 'Camera source',
            value: settings.contentCreatorCameraSourceMode,
            choices: const {
              AppSettings.contentCreatorSourceNative: 'Native',
              AppSettings.contentCreatorSourceAll: 'All',
              AppSettings.contentCreatorSourceUsb: 'USB',
              AppSettings.contentCreatorSourceVirtual: 'Virtual',
            },
            onChanged: notifier.setContentCreatorCameraSourceMode,
          ),
          _setupChoice<String>(
            title: 'Layout',
            value: settings.contentCreatorLayoutPreset,
            choices: const {
              AppSettings.contentCreatorLayoutReading: 'Reading',
              AppSettings.contentCreatorLayoutBalanced: 'Balanced',
              AppSettings.contentCreatorLayoutCamera: 'Camera',
            },
            onChanged: notifier.setContentCreatorLayoutPreset,
          ),
          _setupChoice<String>(
            title: 'Feed mode',
            value: settings.contentCreatorFeedMode,
            choices: const {
              AppSettings.contentCreatorFeedBubble: 'Bubble',
              AppSettings.contentCreatorFeedFull: 'Full',
            },
            onChanged: notifier.setContentCreatorFeedMode,
          ),
          _setupChoice<String>(
            title: 'Bubble position',
            value: settings.contentCreatorBubblePosition,
            choices: const {
              AppSettings.contentCreatorBubbleBottomRight: 'Bottom right',
              AppSettings.contentCreatorBubbleBottomLeft: 'Bottom left',
              AppSettings.contentCreatorBubbleTopRight: 'Top right',
              AppSettings.contentCreatorBubbleTopLeft: 'Top left',
            },
            onChanged: notifier.setContentCreatorBubblePosition,
          ),
          _setupChoice<String>(
            title: 'Bubble shape',
            value: settings.contentCreatorBubbleShape,
            choices: const {
              AppSettings.contentCreatorBubbleShapeRounded: 'Rounded',
              AppSettings.contentCreatorBubbleShapeRectangle: 'Rectangle',
              AppSettings.contentCreatorBubbleShapeCircle: 'Circle',
            },
            onChanged: notifier.setContentCreatorBubbleShape,
          ),
          _setupDoubleSlider(
            title: 'Bubble size',
            value: settings.contentCreatorBubbleSize,
            min: 0.04,
            max: 0.60,
            label: '${(settings.contentCreatorBubbleSize * 100).round()}%',
            onChanged: notifier.setContentCreatorBubbleSize,
          ),
          _setupDoubleSlider(
            title: 'Bubble opacity',
            value: settings.contentCreatorBubbleOpacity,
            min: 0.25,
            max: 1.0,
            label: '${(settings.contentCreatorBubbleOpacity * 100).round()}%',
            onChanged: notifier.setContentCreatorBubbleOpacity,
          ),
          _setupDoubleSlider(
            title: 'Text scrim',
            value: settings.contentCreatorTextScrim,
            min: 0.0,
            max: 0.9,
            label: '${(settings.contentCreatorTextScrim * 100).round()}%',
            onChanged: notifier.setContentCreatorTextScrim,
          ),
          _setupDoubleSlider(
            title: 'Background blur',
            value: settings.contentCreatorFeedBlur,
            min: 0.0,
            max: 30.0,
            label: settings.contentCreatorFeedBlur.toStringAsFixed(0),
            onChanged: notifier.setContentCreatorFeedBlur,
          ),
          _setupChoice<String>(
            title: 'Recording format',
            value: settings.contentCreatorRecordingFormat,
            choices: const {
              AppSettings.contentCreatorRecordingFormatMp4: 'MP4',
              AppSettings.contentCreatorRecordingFormatWav: 'Audio',
            },
            onChanged: notifier.setContentCreatorRecordingFormat,
          ),
          _setupChoice<String>(
            title: 'Resolution',
            value: settings.videoResolution,
            choices: const {
              '480p': '480p',
              '720p': '720p',
              '1080p': '1080p',
            },
            onChanged: notifier.setVideoResolution,
          ),
          _setupSwitch(
            title: 'Record starts speech control',
            value: settings.contentCreatorRecordingControlsSpeech,
            onChanged: notifier.setContentCreatorRecordingControlsSpeech,
          ),
          _setupSwitch(
            title: 'Auto-backup recordings',
            value: settings.recordingAutoBackup,
            onChanged: notifier.setRecordingAutoBackup,
          ),
        ],
      ),
    );
  }

  Future<void> _applyRecommendedSttProfile() async {
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setSttManualProfileEnabled(true);
    await notifier.setSttManualBigWordMinLetters(5);
    await notifier.setSttManualStartAdvanceSmallWords(4);
    await notifier.setSttManualStartAdvanceBigWords(3);
    await notifier.setSttManualSafetySmallWords(2);
    await notifier.setSttManualSafetyBigWords(1);
    await notifier.setSttVisibleSkipEnabled(true);
    await notifier.setSttManualVisibleSkipSmallWords(4);
    await notifier.setSttManualVisibleSkipBigWords(3);
    await notifier.setAllowScrollDuringActiveSession(false);
  }

  Future<void> _applyRecommendedCreatorProfile() async {
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setContentCreatorCameraSourceMode(
      AppSettings.contentCreatorSourceNative,
    );
    await notifier.setContentCreatorLayoutPreset(
      AppSettings.contentCreatorLayoutReading,
    );
    await notifier.setContentCreatorFeedMode(
      AppSettings.contentCreatorFeedBubble,
    );
    await notifier.setContentCreatorBubblePosition(
      AppSettings.contentCreatorBubbleBottomRight,
    );
    await notifier.setContentCreatorBubbleShape(
      AppSettings.contentCreatorBubbleShapeRounded,
    );
    await notifier.setContentCreatorBubbleSize(0.24);
    await notifier.setContentCreatorBubbleOpacity(1.0);
    await notifier.setContentCreatorTextScrim(0.55);
    await notifier.setContentCreatorFeedBlur(14.0);
    await notifier.setVideoResolution('720p');
    await notifier.setContentCreatorRecordingFormat(
      AppSettings.contentCreatorRecordingFormatMp4,
    );
    await notifier.setContentCreatorRecordingControlsSpeech(true);
    await notifier.setRecordingAutoBackup(false);
  }

  Widget _onboardingPanel({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFFBF00), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _setupSwitch({
    required String title,
    String? subtitle,
    required bool value,
    required FutureOr<void> Function(bool) onChanged,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      activeColor: const Color(0xFFFFBF00),
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: Colors.white54)),
      onChanged: (next) => _runOnboardingWrite(() => onChanged(next)),
    );
  }

  Widget _setupIntSlider({
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required FutureOr<void> Function(int) onChanged,
  }) {
    return _setupDoubleSlider(
      title: title,
      subtitle: subtitle,
      value: value.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: max - min,
      label: value.toString(),
      onChanged: (next) => onChanged(next.round()),
    );
  }

  Widget _setupDoubleSlider({
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String label,
    required FutureOr<void> Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFFFBF00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: Colors.white54)),
          ],
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: const Color(0xFFFFBF00),
            inactiveColor: Colors.white12,
            onChanged: (next) => _runOnboardingWrite(() => onChanged(next)),
          ),
        ],
      ),
    );
  }

  Widget _setupChoice<T>({
    required String title,
    required T value,
    required Map<T, String> choices,
    required FutureOr<void> Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.entries.map((entry) {
              final selected = entry.key == value;
              return ChoiceChip(
                label: Text(entry.value),
                selected: selected,
                selectedColor: const Color(0xFFFFBF00),
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) =>
                    _runOnboardingWrite(() => onChanged(entry.key)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _runOnboardingWrite(FutureOr<void> Function() action) {
    final result = action();
    if (result is Future<void>) {
      unawaited(result);
    }
  }
}
