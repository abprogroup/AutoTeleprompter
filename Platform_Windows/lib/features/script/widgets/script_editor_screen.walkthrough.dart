part of 'script_editor_screen.dart';

const String _editorWindowsOnboardingVersion = 'windows-onboarding-v1';

class _EditorWalkthroughStep {
  final IconData icon;
  final String title;
  final String body;

  const _EditorWalkthroughStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}

final List<_EditorWalkthroughStep> _editorSampleWalkthroughSteps = [
  const _EditorWalkthroughStep(
    icon: Icons.edit_note_rounded,
    title: 'Edit the sample',
    body:
        'Click directly into the sample text and make a small change. The sample stays temporary until you save it.',
  ),
  const _EditorWalkthroughStep(
    icon: Icons.drive_file_rename_outline_rounded,
    title: 'Name the script',
    body:
        'This pencil is where you rename a production. Use clear names so Recents stays easy to scan later.',
  ),
  const _EditorWalkthroughStep(
    icon: Icons.save_alt_rounded,
    title: 'Save when ready',
    body:
        'This Save button chooses the file name and format. After saving, the sample becomes a real recent script.',
  ),
  const _EditorWalkthroughStep(
    icon: Icons.bookmarks_rounded,
    title: 'Bookmarks live here',
    body:
        'Bookmarks are in the top toolbar: add, remove, and jump between markers right next to Save.',
  ),
  const _EditorWalkthroughStep(
    icon: Icons.play_circle_fill_rounded,
    title: 'Run Present mode',
    body:
        'Use this Present button to start a live reading session and tune the script over the real text.',
  ),
];

extension _ScriptEditorWalkthroughParts on _ScriptEditorScreenState {
  Widget _buildSampleWalkthroughOverlay() {
    final step = _editorSampleWalkthroughSteps[_walkthroughSampleGuideStep];
    final isFirst = _walkthroughSampleGuideStep == 0;
    final isLast =
        _walkthroughSampleGuideStep == _editorSampleWalkthroughSteps.length - 1;

    return StableWalkthroughOverlay(
      stepId: 'editor.sample.${_walkthroughSampleGuideStep + 1}',
      target: _walkthroughTarget(),
      onClose: _closeSampleWalkthrough,
      cardBuilder: (context, targetRect, constraints) {
        final cardWidth =
            constraints.maxWidth < 700 ? constraints.maxWidth - 32 : 640.0;
        final cardLeft = _walkthroughCardLeft(
          targetRect: targetRect,
          cardWidth: cardWidth,
          maxWidth: constraints.maxWidth,
        );
        final cardTop = _walkthroughCardTop(
          targetRect: targetRect,
          maxHeight: constraints.maxHeight,
        );
        return Positioned(
          top: cardTop,
          left: cardLeft,
          width: cardWidth,
          child: Material(
            color: Colors.transparent,
            child: _walkthroughCard(step, isFirst, isLast),
          ),
        );
      },
    );
  }

  Widget _walkthroughCard(
    _EditorWalkthroughStep step,
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
                child: Icon(
                  step.icon,
                  color: const Color(0xFFFFBF00),
                  size: 22,
                ),
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
                      'editor.sample.${_walkthroughSampleGuideStep + 1}  •  ${_walkthroughSampleGuideStep + 1}/${_editorSampleWalkthroughSteps.length}',
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
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                ),
                onPressed: _closeSampleWalkthrough,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            step.body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: (_walkthroughSampleGuideStep + 1) /
                _editorSampleWalkthroughSteps.length,
            backgroundColor: Colors.white10,
            color: const Color(0xFFFFBF00),
            minHeight: 3,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: _closeSampleWalkthrough,
                child: const Text('Skip'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: isFirst
                    ? null
                    : () => _setEditorState(
                          () => _walkthroughSampleGuideStep--,
                        ),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    _setEditorState(
                      () => _walkthroughSampleGuideVisible = false,
                    );
                    _startPresenting(continueWalkthrough: true);
                    return;
                  }
                  _setEditorState(() => _walkthroughSampleGuideStep++);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  StableWalkthroughTarget? _walkthroughTarget() {
    switch (_walkthroughSampleGuideStep) {
      case 0:
        return StableWalkthroughTarget(
          resolver: _sampleTextWalkthroughTargetRect,
          borderRadius: BorderRadius.circular(18),
        );
      case 1:
        return StableWalkthroughTarget(
          key: _walkthroughRenameKey,
          padding: 10,
          borderRadius: BorderRadius.circular(16),
        );
      case 2:
        return StableWalkthroughTarget(
          key: _walkthroughSaveKey,
          padding: 10,
          borderRadius: BorderRadius.circular(16),
        );
      case 3:
        return StableWalkthroughTarget(
          resolver: (overlayContext) {
            return StableWalkthroughTarget.rectForKey(
                  overlayContext: overlayContext,
                  targetKey: _walkthroughBookmarksKey,
                  padding: 10,
                ) ??
                StableWalkthroughTarget.rectForKey(
                  overlayContext: overlayContext,
                  targetKey: _formattingToolbarKey,
                  padding: 8,
                );
          },
          borderRadius: BorderRadius.circular(16),
        );
      case 4:
        return StableWalkthroughTarget(
          key: _walkthroughPresentKey,
          padding: 8,
          borderRadius: BorderRadius.circular(18),
        );
      default:
        return null;
    }
  }

  Rect? _sampleTextWalkthroughTargetRect(BuildContext overlayContext) {
    final editorSurface = StableWalkthroughTarget.rectForKey(
      overlayContext: overlayContext,
      targetKey: _editorArrowTraceBoundaryKey,
    );
    if (editorSurface == null) return null;
    final firstBlock = _blockKeys.isEmpty
        ? null
        : StableWalkthroughTarget.rectForKey(
            overlayContext: overlayContext,
            targetKey: _blockKeys.first,
          );
    const listHorizontalPadding = 24.0;
    const blockBookmarkGutter = 30.0;
    const listTopPadding = 24.0;
    final targetLeft =
        (firstBlock?.left ?? editorSurface.left + listHorizontalPadding) +
            blockBookmarkGutter;
    final targetTop = firstBlock?.top ?? editorSurface.top + listTopPadding;
    final availableWidth = (firstBlock?.width ??
            editorSurface.width - (listHorizontalPadding * 2)) -
        blockBookmarkGutter;
    final targetWidth = availableWidth.clamp(280.0, 980.0).toDouble();
    return Rect.fromLTWH(
      targetLeft,
      targetTop,
      targetWidth,
      112.0,
    ).inflate(8);
  }

  double _walkthroughCardLeft({
    required Rect? targetRect,
    required double cardWidth,
    required double maxWidth,
  }) {
    final preferred =
        targetRect == null ? 20.0 : targetRect.center.dx - cardWidth / 2;
    return preferred.clamp(16.0, maxWidth - cardWidth - 16).toDouble();
  }

  double _walkthroughCardTop({
    required Rect? targetRect,
    required double maxHeight,
  }) {
    if (targetRect == null) return 126.0;
    final topHalf = targetRect.center.dy < maxHeight * 0.52;
    final preferred = topHalf ? targetRect.bottom + 24 : targetRect.top - 280;
    final maxTop = (maxHeight - 300).clamp(20.0, 260.0).toDouble();
    return preferred.clamp(20.0, maxTop).toDouble();
  }

  void _closeSampleWalkthrough() {
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .setWindowsOnboardingVersionSeen(_editorWindowsOnboardingVersion),
    );
    _setEditorState(() => _walkthroughSampleGuideVisible = false);
  }
}
