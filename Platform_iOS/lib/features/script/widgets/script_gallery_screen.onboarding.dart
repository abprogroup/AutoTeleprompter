part of 'script_gallery_screen.dart';

const String _iosFeedbackOnboardingVersion = 'ios-feedback-parity-v2';
const String _iosFeedbackOnboardingSeenKey = 'iosFeedbackOnboardingVersionSeen';
const String _walkthroughSampleSourceTypeForGallery = 'WALKTHROUGH_SAMPLE';

const String _walkthroughSampleScript = '''
Welcome to AutoTeleprompter

This is a saved practice script for your first walkthrough.

Try editing this paragraph, then use Save to give the script a real name. Once
you save it, AutoTeleprompter adds it to Recents so it is ready for your next
session.

When you are ready, press Present and test your reading settings.
''';

class _IosOnboardingStep {
  final String id;
  final IconData icon;
  final String title;
  final String body;
  final bool opensSample;

  const _IosOnboardingStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.body,
    this.opensSample = false,
  });
}

const List<_IosOnboardingStep> _iosOnboardingSteps = [
  _IosOnboardingStep(
    id: 'lobby.new_script',
    icon: Icons.add_rounded,
    title: 'Start a new script',
    body:
        'Use New Script for a fresh production. The highlighted card opens a blank editor ready for typing or pasting.',
  ),
  _IosOnboardingStep(
    id: 'lobby.load_script',
    icon: Icons.file_open_outlined,
    title: 'Import a document',
    body:
        'Use Load Script to import DOCX, PDF, RTF, TXT, and other supported files from iOS document storage.',
  ),
  _IosOnboardingStep(
    id: 'lobby.recents',
    icon: Icons.history_rounded,
    title: 'Saved scripts return here',
    body:
        'Recent Activity keeps the sample and every saved/imported script ready for the next session.',
  ),
  _IosOnboardingStep(
    id: 'editor.temporary_sample',
    icon: Icons.description_outlined,
    title: 'Practice with a sample script',
    body:
        'Open the sample, edit it, save it under your own name if needed, and then test Present mode.',
    opensSample: true,
  ),
];

extension _ScriptGalleryOnboardingParts on _ScriptGalleryScreenState {
  void _scheduleIosOnboardingIfNeeded() {
    if (_iosOnboardingVisible || _iosOnboardingScheduled) return;
    _iosOnboardingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString(_iosFeedbackOnboardingSeenKey);
      if (!mounted) return;
      if (seen == _iosFeedbackOnboardingVersion) {
        _iosOnboardingScheduled = false;
        return;
      }
      _setGalleryState(() {
        _iosOnboardingVisible = true;
        _iosOnboardingStep = 0;
        _iosOnboardingScheduled = false;
      });
    });
  }

  Future<void> _finishIosOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _iosFeedbackOnboardingSeenKey,
      _iosFeedbackOnboardingVersion,
    );
    if (!mounted) return;
    _setGalleryState(() => _iosOnboardingVisible = false);
  }

  Widget _buildIosOnboardingOverlay(bool hasProAccess) {
    final step = _iosOnboardingSteps[_iosOnboardingStep];
    final isFirst = _iosOnboardingStep == 0;
    final isLast = _iosOnboardingStep == _iosOnboardingSteps.length - 1;
    return StableWalkthroughOverlay(
      stepId: step.id,
      target: _iosOnboardingTarget(step),
      onClose: () => unawaited(_finishIosOnboarding()),
      cardBuilder: (context, targetRect, constraints) {
        final width =
            constraints.maxWidth < 540 ? constraints.maxWidth - 28 : 500.0;
        final left = ((constraints.maxWidth - width) / 2).clamp(14.0, 32.0);
        final top = targetRect == null
            ? (constraints.maxHeight * 0.2).clamp(24.0, 120.0)
            : (targetRect.bottom + 16)
                .clamp(24.0, constraints.maxHeight - 320)
                .toDouble();
        return Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: Colors.transparent,
            child: _iosOnboardingCard(
              step,
              hasProAccess: hasProAccess,
              isFirst: isFirst,
              isLast: isLast,
            ),
          ),
        );
      },
    );
  }

  StableWalkthroughTarget? _iosOnboardingTarget(_IosOnboardingStep step) {
    switch (step.id) {
      case 'lobby.new_script':
        return StableWalkthroughTarget(
          key: _walkthroughNewScriptKey,
          padding: 8,
          borderRadius: BorderRadius.circular(18),
        );
      case 'lobby.load_script':
        return StableWalkthroughTarget(
          key: _walkthroughLoadScriptKey,
          padding: 8,
          borderRadius: BorderRadius.circular(18),
        );
      case 'lobby.recents':
        return StableWalkthroughTarget(
          key: _walkthroughRecentsKey,
          padding: 8,
          borderRadius: BorderRadius.circular(18),
        );
      default:
        return null;
    }
  }

  Widget _iosOnboardingCard(
    _IosOnboardingStep step, {
    required bool hasProAccess,
    required bool isFirst,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xF21A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
              color: Colors.black87, blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(step.icon, color: const Color(0xFFFFBF00), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${step.id}  •  ${_iosOnboardingStep + 1}/${_iosOnboardingSteps.length}'
                      '${hasProAccess ? '' : '  •  Free mode'}',
                      style: const TextStyle(
                        color: Color(0xFFFFBF00),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Skip walkthrough',
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => unawaited(_finishIosOnboarding()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.body,
            style: const TextStyle(
                color: Colors.white70, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: (_iosOnboardingStep + 1) / _iosOnboardingSteps.length,
            backgroundColor: Colors.white10,
            color: const Color(0xFFFFBF00),
            minHeight: 3,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => unawaited(_finishIosOnboarding()),
                child: const Text('Skip'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: isFirst
                    ? null
                    : () => _setGalleryState(() => _iosOnboardingStep--),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isLast
                    ? _openWalkthroughSampleScript
                    : () => _setGalleryState(() => _iosOnboardingStep++),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
                child: Text(step.opensSample ? 'Open sample' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openWalkthroughSampleScript() {
    unawaited(_openWalkthroughSampleScriptAfterHandoff());
  }

  Future<void> _openWalkthroughSampleScriptAfterHandoff() async {
    await _finishIosOnboarding();
    ref.read(scriptProvider.notifier).clear();
    await ref.read(settingsProvider.notifier).resetToDefaultAppearance();
    if (!mounted) return;
    ref.read(scriptProvider.notifier).loadText(
          _walkthroughSampleScript,
          title: 'Welcome to AutoTeleprompter',
          sourceType: _walkthroughSampleSourceTypeForGallery,
          persist: true,
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
}
