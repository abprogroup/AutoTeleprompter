part of 'content_creator_screen.dart';

const String _contentCreatorWalkthroughVersion =
    'android-content-creator-onboarding-v1';

class _CreatorWalkthroughStep {
  final IconData icon;
  final String title;
  final String body;

  const _CreatorWalkthroughStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}

const List<_CreatorWalkthroughStep> _creatorWalkthroughSteps = [
  _CreatorWalkthroughStep(
    icon: Icons.video_camera_front_rounded,
    title: 'Camera and prompter share the screen',
    body:
        'The lower creator surface holds camera or audio-only recording while your script remains readable above it.',
  ),
  _CreatorWalkthroughStep(
    icon: Icons.fiber_manual_record_rounded,
    title: 'Record from one button',
    body:
        'Use the highlighted record button to start and stop video or audio capture with countdown feedback.',
  ),
  _CreatorWalkthroughStep(
    icon: Icons.mic_none_rounded,
    title: 'Speech can be separate or linked',
    body:
        'When Start speech with recording is off, this mic controls STT independently. When on, recording owns STT.',
  ),
  _CreatorWalkthroughStep(
    icon: Icons.tune_rounded,
    title: 'Creator settings',
    body:
        'Choose video/audio mode, camera, recording-plus-speech behavior, and reader settings from here.',
  ),
];

extension _ContentCreatorWalkthroughParts on _ContentCreatorScreenState {
  void _scheduleCreatorWalkthroughIfNeeded() {
    if (!mounted) return;
    final seen =
        ref.read(settingsProvider).contentCreatorWalkthroughVersionSeen;
    if (seen == _contentCreatorWalkthroughVersion) return;
    _setContentCreatorState(() {
      _creatorWalkthroughVisible = true;
      _creatorWalkthroughStep = 0;
    });
  }

  Widget _buildCreatorWalkthroughOverlay() {
    final step = _creatorWalkthroughSteps[_creatorWalkthroughStep];
    final isFirst = _creatorWalkthroughStep == 0;
    final isLast =
        _creatorWalkthroughStep == _creatorWalkthroughSteps.length - 1;
    return StableWalkthroughOverlay(
      stepId: 'creator.android.$_creatorWalkthroughStep',
      target: _creatorWalkthroughTarget(),
      onClose: _closeCreatorWalkthrough,
      cardBuilder: (context, targetRect, constraints) {
        final width =
            constraints.maxWidth < 620 ? constraints.maxWidth - 28 : 520.0;
        final top = targetRect == null
            ? constraints.maxHeight * 0.18
            : (targetRect.top - 250).clamp(24.0, constraints.maxHeight - 300);
        return Positioned(
          left: ((constraints.maxWidth - width) / 2).clamp(14.0, 40.0),
          top: top.toDouble(),
          width: width,
          child: Material(
            color: Colors.transparent,
            child: _creatorWalkthroughCard(step, isFirst, isLast),
          ),
        );
      },
    );
  }

  StableWalkthroughTarget _creatorWalkthroughTarget() {
    switch (_creatorWalkthroughStep) {
      case 0:
        return StableWalkthroughTarget(
          key: _creatorSurfaceKey,
          padding: 8,
          borderRadius: BorderRadius.circular(18),
        );
      case 1:
        return StableWalkthroughTarget(
          key: _creatorRecordKey,
          padding: 10,
          borderRadius: BorderRadius.circular(999),
        );
      case 2:
        return StableWalkthroughTarget(
          resolver: (overlayContext) =>
              StableWalkthroughTarget.rectForKey(
                overlayContext: overlayContext,
                targetKey: _creatorSpeechKey,
                padding: 10,
              ) ??
              StableWalkthroughTarget.rectForKey(
                overlayContext: overlayContext,
                targetKey: _creatorRecordKey,
                padding: 10,
              ),
          borderRadius: BorderRadius.circular(16),
        );
      default:
        return StableWalkthroughTarget(
          key: _creatorSettingsKey,
          padding: 10,
          borderRadius: BorderRadius.circular(16),
        );
    }
  }

  Widget _creatorWalkthroughCard(
    _CreatorWalkthroughStep step,
    bool isFirst,
    bool isLast,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xF21A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(step.icon, color: const Color(0xFFFFBF00), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close guide',
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: _closeCreatorWalkthrough,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value:
                (_creatorWalkthroughStep + 1) / _creatorWalkthroughSteps.length,
            backgroundColor: Colors.white10,
            color: const Color(0xFFFFBF00),
            minHeight: 3,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: _closeCreatorWalkthrough,
                child: const Text('Skip'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: isFirst
                    ? null
                    : () => _setContentCreatorState(
                        () => _creatorWalkthroughStep--),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isLast
                    ? _closeCreatorWalkthrough
                    : () => _setContentCreatorState(
                        () => _creatorWalkthroughStep++),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
                child: Text(isLast ? 'Finish' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _closeCreatorWalkthrough() {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .setContentCreatorWalkthroughVersionSeen(
              _contentCreatorWalkthroughVersion),
    );
    _setContentCreatorState(() => _creatorWalkthroughVisible = false);
  }
}
