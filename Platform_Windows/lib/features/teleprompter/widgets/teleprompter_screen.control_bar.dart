part of 'teleprompter_screen.dart';

class _ControlBar extends ConsumerWidget {
  final bool isListening;
  final bool isStarting;
  final bool isManualMode;
  final bool isManualScrolling;
  final bool isScrollingBackward;
  final Color accentColor;
  final VoidCallback onStart;
  final VoidCallback onStartBackward;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onBack;
  final VoidCallback onEditCurrentPosition;
  final VoidCallback onSettings;
  final VoidCallback onAddBookmark;
  final VoidCallback onRemoveBookmark;
  final VoidCallback onPreviousBookmark;
  final VoidCallback onNextBookmark;
  final VoidCallback onSearch;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final ValueChanged<double> onFontSizeChanged;

  const _ControlBar({
    required this.isListening,
    required this.isStarting,
    required this.isManualMode,
    required this.isManualScrolling,
    required this.isScrollingBackward,
    required this.accentColor,
    required this.onStart,
    required this.onStartBackward,
    required this.onStop,
    required this.onReset,
    required this.onBack,
    required this.onEditCurrentPosition,
    required this.onSettings,
    required this.onAddBookmark,
    required this.onRemoveBookmark,
    required this.onPreviousBookmark,
    required this.onNextBookmark,
    required this.onSearch,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onFontSizeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Forward scroll is active when scrolling but NOT backward
    final isActive = isManualMode
        ? (isManualScrolling && settings.scrollSpeed != 0)
        : isListening;
    final isBooting = !isManualMode && isStarting;
    final effectiveFontSize =
        ref.read(scriptProvider.notifier).effectiveFontSize(settings.fontSize);
    void applyPresenterFontSize(double size) {
      final clamped = size.clamp(14.0, 120.0).toDouble();
      ref.read(teleprompterProvider.notifier).setVisibleWordWindow(null, null);
      unawaited(ref.read(scriptProvider.notifier).applyBaseFontSize(clamped));
      onFontSizeChanged(clamped);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.95), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: onBack,
              tooltip: 'Back to editor',
            ),
            IconButton(
              icon: const Icon(Icons.edit_note, color: Colors.white70),
              onPressed: onEditCurrentPosition,
              tooltip: 'Edit current position',
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white70),
              onPressed: onPreviousBookmark,
              tooltip: 'Previous bookmark',
            ),
            IconButton(
              icon: const Text('A',
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
              onPressed: () {
                applyPresenterFontSize(effectiveFontSize - 4);
              },
              tooltip: 'Smaller font',
            ),
            // Backward button removed in favor of bidirectional slider
            GestureDetector(
              onTap: isBooting ? null : (isActive ? onStop : onStart),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.red : accentColor,
                ),
                child: Icon(
                  isManualMode
                      ? (isManualScrolling && settings.scrollSpeed != 0
                          ? Icons.pause
                          : Icons.play_arrow)
                      : (isStarting
                          ? Icons.hourglass_top
                          : (isListening ? Icons.stop : Icons.mic)),
                  color: isActive ? Colors.white : Colors.black,
                  size: 30,
                ),
              ),
            ),
            IconButton(
              icon: const Text('A',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              onPressed: () {
                applyPresenterFontSize(effectiveFontSize + 4);
              },
              tooltip: 'Larger font',
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined,
                  color: Colors.white70),
              onPressed: onAddBookmark,
              tooltip: 'Add bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_remove_outlined,
                  color: Colors.white70),
              onPressed: isListening || isStarting ? null : onRemoveBookmark,
              tooltip: 'Remove bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70),
              onPressed: onSettings,
              tooltip: 'Presenter settings',
            ),
            IconButton(
              icon: Icon(
                isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white70,
              ),
              onPressed: onToggleFullscreen,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white70),
              onPressed: onNextBookmark,
              tooltip: 'Next bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white70),
              onPressed: onReset,
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white70),
              onPressed: onSearch,
              tooltip: 'Search (Ctrl+Shift+F)',
            ),
          ],
        ),
      ),
    );
  }
}

// Settings panel
