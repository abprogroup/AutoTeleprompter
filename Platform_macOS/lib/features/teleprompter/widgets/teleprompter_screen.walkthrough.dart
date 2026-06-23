part of 'teleprompter_screen.dart';

const String _presenterMacOnboardingVersion = 'mac-premium-feedback-v1';

class _PresenterWalkthroughStep {
  final IconData icon;
  final String id;
  final String title;
  final String body;
  final bool showsSttSetup;

  const _PresenterWalkthroughStep({
    required this.icon,
    required this.id,
    required this.title,
    required this.body,
    this.showsSttSetup = false,
  });
}

const List<_PresenterWalkthroughStep> _presenterWalkthroughSteps = [
  _PresenterWalkthroughStep(
    icon: Icons.play_circle_fill_rounded,
    id: 'present.start_session',
    title: 'This is the live reading surface',
    body:
        'Present mode shows the saved script at reading size. As you speak or scroll, this is the surface your eyes stay on.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.tune_rounded,
    id: 'present.controls',
    title: 'Controls stay at the bottom',
    body:
        'Use this toolbar to start speech/manual scrolling, search, change font size, jump bookmarks, return to the editor, and reset the session.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.settings_suggest_rounded,
    id: 'present.settings_toolbar',
    title: 'Tune Present settings here',
    body:
        'This settings button opens the live Present settings sheet. Use it during rehearsal to adjust scroll mode, speed, reading line, text size, spacing, colors, mirroring, and speech-control behavior while still seeing the script underneath.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.record_voice_over_outlined,
    id: 'settings.stt_profile',
    title: 'Personalize speech control',
    body:
        'Answer these once so AutoTeleprompter knows how confidently it should listen, scroll, pause, and recover when you skip ahead.',
    showsSttSetup: true,
  ),
];

extension _TeleprompterWalkthroughParts on _TeleprompterScreenState {
  Widget _buildPresenterWalkthroughOverlay() {
    final step = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    final isFirst = _presenterWalkthroughStep == 0;
    final isLast =
        _presenterWalkthroughStep == _presenterWalkthroughSteps.length - 1;

    return StableWalkthroughOverlay(
      stepId: step.id,
      target: _presenterWalkthroughTarget(),
      onClose: _finishPresenterWalkthrough,
      cardBuilder: (context, targetRect, constraints) {
        final cardWidth =
            constraints.maxWidth < 700 ? constraints.maxWidth - 32 : 620.0;
        final cardLeft = _presenterWalkthroughCardLeft(
          targetRect: targetRect,
          cardWidth: cardWidth,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        );
        final cardTop = _presenterWalkthroughCardTop(
          targetRect: targetRect,
          maxHeight: constraints.maxHeight,
        );
        return Positioned(
          top: cardTop,
          left: cardLeft,
          width: cardWidth,
          child: Material(
            color: Colors.transparent,
            child: _presenterWalkthroughCard(step, isFirst, isLast),
          ),
        );
      },
    );
  }

  Widget _presenterWalkthroughCard(
    _PresenterWalkthroughStep step,
    bool isFirst,
    bool isLast,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xF21A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - 80,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFBF00).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x66FFBF00)),
                    ),
                    child: Icon(step.icon, color: const Color(0xFFFFBF00)),
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
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${step.id}  •  ${_presenterWalkthroughStep + 1}/${_presenterWalkthroughSteps.length}',
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
                    tooltip: 'Close guide',
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: _finishPresenterWalkthrough,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!step.showsSttSetup)
                Text(
                  step.body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              if (step.showsSttSetup) ...[
                Text(
                  _presenterSttQuestionIntro,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _presenterSttSetupPanel(),
              ],
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: (_presenterWalkthroughStep + 1) /
                    _presenterWalkthroughSteps.length,
                backgroundColor: Colors.white10,
                color: const Color(0xFFFFBF00),
                minHeight: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _finishPresenterWalkthrough,
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _presenterWalkthroughBackEnabled(isFirst)
                        ? _presenterWalkthroughBack
                        : null,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _presenterWalkthroughNext(isLast),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black,
                    ),
                    child: Text(_presenterWalkthroughNextLabel(isLast)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _presenterSttQuestionIntro {
    if (_presenterSttQuestionIndex >= _presenterSttQuestionCount - 1) {
      return 'Here is the speech-control profile AutoTeleprompter will use for your sessions. You can change these later in settings.';
    }
    return 'Answer one setup question at a time. Recommended values are already selected, so you can keep pressing Continue if they feel right.';
  }

  int get _presenterSttQuestionCount => 8;

  bool _presenterWalkthroughBackEnabled(bool isFirst) {
    final step = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    if (step.showsSttSetup && _presenterSttQuestionIndex > 0) return true;
    return !isFirst;
  }

  void _presenterWalkthroughBack() {
    final step = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    if (step.showsSttSetup && _presenterSttQuestionIndex > 0) {
      _setTeleprompterState(() => _presenterSttQuestionIndex--);
      return;
    }
    _setTeleprompterState(() {
      _presenterWalkthroughStep--;
      _presenterSttQuestionIndex = 0;
    });
  }

  void _presenterWalkthroughNext(bool isLast) {
    final step = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    if (step.showsSttSetup &&
        _presenterSttQuestionIndex < _presenterSttQuestionCount - 1) {
      _setTeleprompterState(() => _presenterSttQuestionIndex++);
      return;
    }
    if (isLast) {
      _finishPresenterWalkthrough();
      return;
    }
    _setTeleprompterState(() {
      _presenterWalkthroughStep++;
      _presenterSttQuestionIndex = 0;
    });
    final nextStep = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    if (nextStep.showsSttSetup) {
      _applyPresenterSttGuideDefaults();
    }
  }

  String _presenterWalkthroughNextLabel(bool isLast) {
    final step = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    if (step.showsSttSetup &&
        _presenterSttQuestionIndex < _presenterSttQuestionCount - 1) {
      return 'Continue';
    }
    return isLast ? 'Finish' : 'Next';
  }

  StableWalkthroughTarget? _presenterWalkthroughTarget() {
    switch (_presenterWalkthroughStep) {
      case 0:
        return StableWalkthroughTarget(
          resolver: _presenterReadingSurfaceTargetRect,
          borderRadius: BorderRadius.circular(18),
        );
      case 1:
        return StableWalkthroughTarget(
          key: _presenterControlsKey,
          padding: 8,
          borderRadius: BorderRadius.circular(22),
        );
      case 2:
        return StableWalkthroughTarget(
          key: _presenterSettingsButtonKey,
          padding: 10,
          borderRadius: BorderRadius.circular(16),
        );
      case 3:
        return null;
      default:
        return null;
    }
  }

  Widget _presenterSttSetupPanel() {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final questionIndex = _presenterSttQuestionIndex
        .clamp(0, _presenterSttQuestionCount - 1)
        .toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questionIndex == _presenterSttQuestionCount - 1
                ? 'Speech profile summary'
                : 'Question ${questionIndex + 1} of ${_presenterSttQuestionCount - 1}',
            style: const TextStyle(
              color: Color(0xFFFFBF00),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _presenterSttQuestion(
            questionIndex,
            settings,
            notifier,
          ),
        ],
      ),
    );
  }

  Widget _presenterSttQuestion(
    int index,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    switch (index) {
      case 0:
        return _presenterSetupSwitch(
          title: 'Use a personal speech-control profile?',
          subtitle:
              'Turn this on so AutoTeleprompter uses the answers from this guide instead of generic defaults.',
          value: settings.sttManualProfileEnabled,
          onChanged: notifier.setSttManualProfileEnabled,
        );
      case 1:
        return _presenterSetupIntSlider(
          title: 'What counts as a long word?',
          subtitle:
              'Longer words are easier for speech control to trust. Recommended: 5 letters.',
          value: settings.sttManualBigWordMinLetters,
          min: 3,
          max: 10,
          onChanged: notifier.setSttManualBigWordMinLetters,
        );
      case 2:
        return Column(
          children: [
            _presenterSetupIntSlider(
              title: 'How many words should start scrolling?',
              subtitle:
                  'Short words need a little more confirmation. Recommended: 3 short words.',
              value: settings.sttManualStartAdvanceSmallWords,
              min: 2,
              max: 8,
              onChanged: notifier.setSttManualStartAdvanceSmallWords,
            ),
            _presenterSetupIntSlider(
              title: 'Long-word start threshold',
              subtitle:
                  'Long words are stronger signals, so fewer are needed. Recommended: 2 long words.',
              value: settings.sttManualStartAdvanceBigWords,
              min: 1,
              max: 8,
              onChanged: notifier.setSttManualStartAdvanceBigWords,
            ),
          ],
        );
      case 3:
        return Column(
          children: [
            _presenterSetupIntSlider(
              title: 'How many missed short words before pausing?',
              subtitle:
                  'If recognition drifts away, this decides how quickly speech control returns to standby. Recommended: 2.',
              value: settings.sttManualSafetySmallWords,
              min: 1,
              max: 5,
              onChanged: notifier.setSttManualSafetySmallWords,
            ),
            _presenterSetupIntSlider(
              title: 'How many missed long words before pausing?',
              subtitle:
                  'Long words are more reliable, so one missed long word can be enough to protect the run. Recommended: 1.',
              value: settings.sttManualSafetyBigWords,
              min: 1,
              max: 5,
              onChanged: notifier.setSttManualSafetyBigWords,
            ),
          ],
        );
      case 4:
        return _presenterSetupSwitch(
          title: 'Jump ahead when you skip to visible text?',
          subtitle:
              'Enable this if you sometimes skip lines while the next text is already visible on screen.',
          value: settings.sttVisibleSkipEnabled,
          onChanged: notifier.setSttVisibleSkipEnabled,
        );
      case 5:
        return Column(
          children: [
            _presenterSetupIntSlider(
              title: 'How many matching short words confirm a jump?',
              subtitle:
                  'Used only when visible-text jumps are enabled. Recommended: 4.',
              value: settings.sttManualVisibleSkipSmallWords == 0
                  ? 4
                  : settings.sttManualVisibleSkipSmallWords,
              min: 2,
              max: 8,
              onChanged: notifier.setSttManualVisibleSkipSmallWords,
            ),
            _presenterSetupIntSlider(
              title: 'How many matching long words confirm a jump?',
              subtitle:
                  'Long words need fewer matches to confirm the same jump. Recommended: 3.',
              value: settings.sttManualVisibleSkipBigWords == 0
                  ? 3
                  : settings.sttManualVisibleSkipBigWords,
              min: 1,
              max: 8,
              onChanged: notifier.setSttManualVisibleSkipBigWords,
            ),
          ],
        );
      case 6:
        return _presenterSetupSwitch(
          title: 'Allow trackpad or mouse scrolling during speech control?',
          subtitle:
              'Turn this on if someone may manually correct the scroll while speech control is listening.',
          value: settings.allowScrollDuringActiveSession,
          onChanged: notifier.setAllowScrollDuringActiveSession,
        );
      default:
        return _presenterSttSummary(settings);
    }
  }

  void _applyPresenterSttGuideDefaults() {
    if (_presenterSttGuideDefaultsApplied) return;
    _presenterSttGuideDefaultsApplied = true;
    final notifier = ref.read(settingsProvider.notifier);
    unawaited(notifier.setSttManualProfileEnabled(true));
    unawaited(notifier.setSttManualBigWordMinLetters(5));
    unawaited(notifier.setSttManualStartAdvanceSmallWords(3));
    unawaited(notifier.setSttManualStartAdvanceBigWords(2));
    unawaited(notifier.setSttManualSafetySmallWords(2));
    unawaited(notifier.setSttManualSafetyBigWords(1));
    unawaited(notifier.setSttVisibleSkipEnabled(true));
    unawaited(notifier.setSttManualVisibleSkipSmallWords(4));
    unawaited(notifier.setSttManualVisibleSkipBigWords(3));
  }

  Widget _presenterSttSummary(AppSettings settings) {
    return Column(
      children: [
        _presenterSummaryRow(
          'Profile',
          settings.sttManualProfileEnabled ? 'On' : 'Off',
        ),
        _presenterSummaryRow(
          'Start scrolling',
          '${settings.sttManualStartAdvanceSmallWords} short words or ${settings.sttManualStartAdvanceBigWords} long words',
        ),
        _presenterSummaryRow(
          'Pause protection',
          '${settings.sttManualSafetySmallWords} missed short / ${settings.sttManualSafetyBigWords} missed long',
        ),
        _presenterSummaryRow(
          'Visible-text jumps',
          settings.sttVisibleSkipEnabled
              ? '${settings.sttManualVisibleSkipSmallWords == 0 ? 4 : settings.sttManualVisibleSkipSmallWords} short / ${settings.sttManualVisibleSkipBigWords == 0 ? 3 : settings.sttManualVisibleSkipBigWords} long matches'
              : 'Off',
        ),
        _presenterSummaryRow(
          'Manual scrolling while listening',
          settings.allowScrollDuringActiveSession ? 'Allowed' : 'Protected',
        ),
      ],
    );
  }

  Widget _presenterSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presenterSetupSwitch({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
      value: value,
      activeColor: const Color(0xFFFFBF00),
      onChanged: onChanged,
    );
  }

  Widget _presenterSetupIntSlider({
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: Color(0xFFFFBF00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            activeColor: const Color(0xFFFFBF00),
            inactiveColor: Colors.white24,
            label: '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      ),
    );
  }

  Rect? _presenterReadingSurfaceTargetRect(BuildContext overlayContext) {
    final rect = StableWalkthroughTarget.rectForKey(
      overlayContext: overlayContext,
      targetKey: _presenterContentKey,
    );
    if (rect == null) return null;
    return Rect.fromLTWH(
      rect.left + 28,
      rect.top + 72,
      (rect.width - 56).clamp(260.0, 900.0).toDouble(),
      (rect.height * 0.42).clamp(160.0, 360.0).toDouble(),
    );
  }

  double _presenterWalkthroughCardLeft({
    required Rect? targetRect,
    required double cardWidth,
    required double maxWidth,
    required double maxHeight,
  }) {
    final target = targetRect;
    final targetIsLow = target != null && target.center.dy > maxHeight * 0.56;
    final preferred = target == null || targetIsLow
        ? (maxWidth - cardWidth) / 2
        : target.center.dx - cardWidth / 2;
    return preferred.clamp(16.0, maxWidth - cardWidth - 16).toDouble();
  }

  double _presenterWalkthroughCardTop({
    required Rect? targetRect,
    required double maxHeight,
  }) {
    if (targetRect == null) return 120.0;
    final targetIsLow = targetRect.center.dy > maxHeight * 0.56;
    final preferred =
        targetIsLow ? targetRect.top - 280 : targetRect.bottom + 24;
    final maxTop = (maxHeight - 300).clamp(20.0, 260.0).toDouble();
    return preferred.clamp(20.0, maxTop).toDouble();
  }

  void _finishPresenterWalkthrough() {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .setMacOnboardingVersionSeen(_presenterMacOnboardingVersion),
    );
    _setTeleprompterState(() => _presenterWalkthroughVisible = false);
    _scheduleHideControls();
  }
}
