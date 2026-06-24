part of 'script_editor_screen.dart';

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

const List<_EditorWalkthroughStep> _editorSampleWalkthroughSteps = [
  _EditorWalkthroughStep(
    icon: Icons.edit_note_rounded,
    title: 'Edit the sample',
    body:
        'Tap into the saved sample text and make a small change. It appears in Recents so you can keep testing from the lobby.',
  ),
  _EditorWalkthroughStep(
    icon: Icons.drive_file_rename_outline_rounded,
    title: 'Rename the project',
    body:
        'Tap the highlighted title pencil when you want the script name to match the production.',
  ),
  _EditorWalkthroughStep(
    icon: Icons.save_alt_rounded,
    title: 'Save when ready',
    body:
        'Use Save to choose the file and format. After saving, the sample becomes a real recent script.',
  ),
  _EditorWalkthroughStep(
    icon: Icons.bookmarks_rounded,
    title: 'Bookmarks live in the suite',
    body:
        'Open the Bookmarks suite in the editor toolbar. Free accounts see the locked suite; Pro accounts can add, remove, and jump.',
  ),
  _EditorWalkthroughStep(
    icon: Icons.play_circle_fill_rounded,
    title: 'Run Present mode',
    body:
        'Use Present to test reading, speech control, camera, recording, and presenter settings.',
  ),
];

extension _ScriptEditorWalkthroughParts on _ScriptEditorScreenState {
  Widget _buildSampleWalkthroughOverlay() {
    final step = _editorSampleWalkthroughSteps[_walkthroughSampleGuideStep];
    final isFirst = _walkthroughSampleGuideStep == 0;
    final isLast =
        _walkthroughSampleGuideStep == _editorSampleWalkthroughSteps.length - 1;
    return StableWalkthroughOverlay(
      stepId: 'editor.sample.$_walkthroughSampleGuideStep',
      target: _editorWalkthroughTarget(),
      onClose: _closeSampleWalkthrough,
      cardBuilder: (context, targetRect, constraints) {
        final width =
            constraints.maxWidth < 620 ? constraints.maxWidth - 28 : 560.0;
        final preferredTop = targetRect == null
            ? constraints.maxHeight * 0.18
            : isFirst
                ? targetRect.top + 20
                : targetRect.bottom + 16;
        return Positioned(
          left: ((constraints.maxWidth - width) / 2).clamp(14.0, 40.0),
          top: preferredTop.clamp(24.0, constraints.maxHeight - 330).toDouble(),
          width: width,
          child: Material(
            color: Colors.transparent,
            child: _walkthroughCard(step, isFirst, isLast),
          ),
        );
      },
    );
  }

  StableWalkthroughTarget _editorWalkthroughTarget() {
    switch (_walkthroughSampleGuideStep) {
      case 0:
        return StableWalkthroughTarget(
          key: _walkthroughEditorViewportKey,
          padding: 10,
          borderRadius: BorderRadius.circular(18),
        );
      case 1:
        return StableWalkthroughTarget(
          key: _walkthroughRenameKey,
          padding: 10,
          borderRadius: BorderRadius.circular(14),
        );
      case 2:
        return StableWalkthroughTarget(
          key: _walkthroughSaveKey,
          padding: 10,
          borderRadius: BorderRadius.circular(14),
        );
      case 3:
        return StableWalkthroughTarget(
          key: _walkthroughBookmarksKey,
          padding: 10,
          borderRadius: BorderRadius.circular(14),
        );
      default:
        return StableWalkthroughTarget(
          key: _walkthroughPresentKey,
          padding: 8,
          borderRadius: BorderRadius.circular(14),
        );
    }
  }

  Widget _walkthroughCard(
    _EditorWalkthroughStep step,
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
              color: Colors.black87, blurRadius: 24, offset: Offset(0, 14)),
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
                onPressed: _closeSampleWalkthrough,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.body,
            style: const TextStyle(
                color: Colors.white70, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: (_walkthroughSampleGuideStep + 1) /
                _editorSampleWalkthroughSteps.length,
            backgroundColor: Colors.white10,
            color: const Color(0xFFFFBF00),
            minHeight: 3,
          ),
          const SizedBox(height: 14),
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
                    : () =>
                        _setEditorState(() => _walkthroughSampleGuideStep--),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    _closeSampleWalkthrough();
                    unawaited(_startPresenting(continueWalkthrough: true));
                    return;
                  }
                  _setEditorState(() => _walkthroughSampleGuideStep++);
                },
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

  void _scheduleSampleWalkthroughStart() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      _setEditorState(() {
        _walkthroughSampleGuideStep = 0;
        _walkthroughSampleGuideVisible = true;
      });
    });
  }

  void _closeSampleWalkthrough() {
    _setEditorState(() => _walkthroughSampleGuideVisible = false);
  }
}
