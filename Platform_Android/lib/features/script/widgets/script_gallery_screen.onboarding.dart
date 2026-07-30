part of 'script_gallery_screen.dart';

const String _androidOnboardingVersion = 'android-onboarding-v1';
const String _walkthroughTempSourceTypeForGallery = 'WALKTHROUGH_TEMP';

const String _walkthroughSampleScript = '''
Welcome to AutoTeleprompter

This is a temporary practice script for your first walkthrough.

Try editing this paragraph, then use Save to give the script a real name. Once
you save it, AutoTeleprompter adds it to Recents so it is ready for your next
session.

When you are ready, press Present and test your reading settings.
''';

class _AndroidOnboardingStep {
  final String id;
  final IconData icon;
  final String title;
  final String body;
  final bool showsSampleAction;

  const _AndroidOnboardingStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.body,
    this.showsSampleAction = false,
  });
}

const List<_AndroidOnboardingStep> _androidOnboardingSteps = [
  _AndroidOnboardingStep(
    id: 'lobby.new_or_load',
    icon: Icons.add_rounded,
    title: 'Start or load a script',
    body:
        'Use New Script for a fresh production, or Load Script to import a document. Recents keeps saved work close for quick access.',
  ),
  _AndroidOnboardingStep(
    id: 'lobby.recents',
    icon: Icons.history_rounded,
    title: 'Saved scripts return here',
    body:
        'After a script is saved, it appears in Recent Activity for fast access. The temporary walkthrough sample will stay out of this list until you save it.',
  ),
  _AndroidOnboardingStep(
    id: 'editor.temporary_sample',
    icon: Icons.description_outlined,
    title: 'Practice with a temporary script',
    body:
        'Open the sample script, edit it, rename it, and save it. It stays out of Recents until you save, so the walkthrough stays clean.',
    showsSampleAction: true,
  ),
];

/// Ported from Windows' `script_gallery_screen.onboarding.dart`. Windows'
/// version chains into a 5-step continuation inside the editor
/// (`script_editor_screen.walkthrough.dart`, renaming/saving/bookmarks/
/// present-mode targets) - that continuation was deliberately NOT ported in
/// this pass (it touches many existing toolbar elements across the already
/// large editor screen family and deserves its own dedicated pass rather
/// than being rushed alongside this). "Open sample script" here simply opens
/// the sample normally; the gallery-level introduction below is a complete,
/// self-contained, non-dead-ending experience on its own.
extension _ScriptGalleryOnboardingParts on _ScriptGalleryScreenState {
  void _scheduleOnboardingIfNeeded(AppSettings settings) {
    // Wait for the real persisted value: settingsProvider starts out with
    // defaults (including an empty "seen version") while its async
    // SharedPreferences load is still in flight, so checking too early on a
    // cold start would show onboarding again even though it was seen before.
    if (!settings.settingsLoaded) return;
    if (_onboardingVisible ||
        _onboardingScheduled ||
        settings.androidOnboardingVersionSeen == _androidOnboardingVersion) {
      return;
    }
    _onboardingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _onboardingVisible = true;
        _onboardingStep = 0;
        _onboardingScheduled = false;
      });
    });
  }

  Future<void> _finishOnboarding() async {
    await ref
        .read(settingsProvider.notifier)
        .setAndroidOnboardingVersionSeen(_androidOnboardingVersion);
    if (!mounted) return;
    setState(() => _onboardingVisible = false);
  }

  void _openWalkthroughSampleScript() {
    unawaited(_openWalkthroughSampleScriptAfterLobbyHandoff());
  }

  Future<void> _openWalkthroughSampleScriptAfterLobbyHandoff() async {
    LightweightDiagnostics.instance.record(
      'gallery',
      'walkthrough sample opened',
    );
    setState(() {
      _onboardingVisible = false;
      _onboardingScheduled = false;
    });
    await ref
        .read(settingsProvider.notifier)
        .setAndroidOnboardingVersionSeen(_androidOnboardingVersion);
    ref.read(scriptProvider.notifier).clear();
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

  Widget _buildOnboardingOverlay(AppSettings settings, bool hasProAccess) {
    final step = _androidOnboardingSteps[_onboardingStep];
    final isFirst = _onboardingStep == 0;
    final isLast = _onboardingStep == _androidOnboardingSteps.length - 1;
    return StableWalkthroughOverlay(
      stepId: step.id,
      target: _onboardingTarget(step),
      onClose: () => unawaited(_finishOnboarding()),
      cardBuilder: (context, targetRect, constraints) {
        final cardWidth =
            constraints.maxWidth < 760 ? constraints.maxWidth - 32 : 680.0;
        final left = _onboardingCardLeft(
          targetRect: targetRect,
          cardWidth: cardWidth,
          maxWidth: constraints.maxWidth,
        );
        final top = _onboardingCardTop(
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

  StableWalkthroughTarget? _onboardingTarget(_AndroidOnboardingStep step) {
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

  double _onboardingCardLeft({
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

  double _onboardingCardTop({
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

  Widget _onboardingHeader(_AndroidOnboardingStep step, bool hasProAccess) {
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
                  '${step.id}  •  ${_onboardingStep + 1}/${_androidOnboardingSteps.length}'
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
            onPressed: () => unawaited(_finishOnboarding()),
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
              value: (_onboardingStep + 1) / _androidOnboardingSteps.length,
              backgroundColor: Colors.white10,
              color: const Color(0xFFFFBF00),
              minHeight: 3,
            ),
          ),
          const SizedBox(width: 18),
          TextButton(
            onPressed: () => unawaited(_finishOnboarding()),
            child: const Text('Skip'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: isFirst ? null : () => setState(() => _onboardingStep--),
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              if (isLast) {
                _openWalkthroughSampleScript();
              } else {
                setState(() => _onboardingStep++);
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

  Widget _onboardingPanel({
    required IconData icon,
    required String title,
    required Widget child,
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
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
