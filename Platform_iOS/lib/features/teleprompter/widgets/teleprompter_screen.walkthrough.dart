part of 'teleprompter_screen.dart';

class _PresenterWalkthroughStep {
  final IconData icon;
  final String title;
  final String body;

  const _PresenterWalkthroughStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}

const List<_PresenterWalkthroughStep> _presenterWalkthroughSteps = [
  _PresenterWalkthroughStep(
    icon: Icons.mic_rounded,
    title: 'Speech follows your reading',
    body:
        'Tap the highlighted mic to start or stop STT. The same controller is used by the remote and recording flows.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.tune_rounded,
    title: 'Presenter settings',
    body:
        'Open settings for STT profiles, manual-scroll behavior, colors, mirroring, and recording options.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.psychology_alt_rounded,
    title: 'Choose the STT profile',
    body:
        'Use the Speech/Profile section to choose default or manual thresholds: how many small/big words confirm reading, recover safely, or allow a visible skip.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.bookmarks_rounded,
    title: 'Bookmarks stay close',
    body:
        'Use these controls to add, remove, and jump between marked script moments without leaving Present mode.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.replay_rounded,
    title: 'Reset position',
    body:
        'Reset returns the script and read progress to the beginning, including remote-visible reading state.',
  ),
  _PresenterWalkthroughStep(
    icon: Icons.settings_remote_rounded,
    title: 'Remote is gated here',
    body:
        'Remote buttons unlock only when Present mode is active, so connected controllers cannot drive the editor by mistake.',
  ),
];

extension _TeleprompterWalkthroughParts on _TeleprompterScreenState {
  Widget _buildPresenterWalkthroughOverlay() {
    final step = _presenterWalkthroughSteps[_presenterWalkthroughStep];
    final isFirst = _presenterWalkthroughStep == 0;
    final isLast =
        _presenterWalkthroughStep == _presenterWalkthroughSteps.length - 1;
    return StableWalkthroughOverlay(
      stepId: 'present.ios.$_presenterWalkthroughStep',
      target: _presenterWalkthroughTarget(),
      onClose: _closePresenterWalkthrough,
      cardBuilder: (context, targetRect, constraints) {
        final width =
            constraints.maxWidth < 620 ? constraints.maxWidth - 28 : 520.0;
        final top = targetRect == null
            ? constraints.maxHeight * 0.16
            : (targetRect.top - 260).clamp(24.0, constraints.maxHeight - 300);
        return Positioned(
          left: ((constraints.maxWidth - width) / 2).clamp(14.0, 40.0),
          top: top.toDouble(),
          width: width,
          child: Material(
            color: Colors.transparent,
            child: _presenterWalkthroughCard(step, isFirst, isLast),
          ),
        );
      },
    );
  }

  StableWalkthroughTarget _presenterWalkthroughTarget() {
    switch (_presenterWalkthroughStep) {
      case 0:
        return StableWalkthroughTarget(
          key: _presenterSttKey,
          padding: 10,
          borderRadius: BorderRadius.circular(999),
        );
      case 1:
      case 2:
        return StableWalkthroughTarget(
          key: _presenterSettingsKey,
          padding: 10,
          borderRadius: BorderRadius.circular(14),
        );
      case 3:
        return StableWalkthroughTarget(
          key: _presenterBookmarksKey,
          padding: 8,
          borderRadius: BorderRadius.circular(14),
        );
      case 4:
        return StableWalkthroughTarget(
          key: _presenterResetKey,
          padding: 10,
          borderRadius: BorderRadius.circular(14),
        );
      default:
        return StableWalkthroughTarget(
          resolver: (overlayContext) {
            final settingsRect = StableWalkthroughTarget.rectForKey(
              overlayContext,
              _presenterSettingsKey,
              padding: 8,
            );
            final sttRect = StableWalkthroughTarget.rectForKey(
              overlayContext,
              _presenterSttKey,
              padding: 8,
            );
            if (settingsRect == null) return sttRect;
            if (sttRect == null) return settingsRect;
            return settingsRect.expandToInclude(sttRect).inflate(6);
          },
          borderRadius: BorderRadius.circular(16),
        );
    }
  }

  Widget _presenterWalkthroughCard(
    _PresenterWalkthroughStep step,
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
                onPressed: _closePresenterWalkthrough,
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
            value: (_presenterWalkthroughStep + 1) /
                _presenterWalkthroughSteps.length,
            backgroundColor: Colors.white10,
            color: const Color(0xFFFFBF00),
            minHeight: 3,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: _closePresenterWalkthrough,
                child: const Text('Skip'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: isFirst
                    ? null
                    : () => _setTeleprompterState(
                        () => _presenterWalkthroughStep--),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isLast
                    ? _closePresenterWalkthrough
                    : () => _setTeleprompterState(
                        () => _presenterWalkthroughStep++),
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

  void _closePresenterWalkthrough() {
    _setTeleprompterState(() => _presenterWalkthroughVisible = false);
  }
}
