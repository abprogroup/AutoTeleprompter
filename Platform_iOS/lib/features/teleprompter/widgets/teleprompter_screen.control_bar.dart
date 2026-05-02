part of 'teleprompter_screen.dart';

class _ControlBar extends ConsumerWidget {
  final bool isListening;
  final bool isManualMode;
  final bool isManualScrolling;
  final bool isScrollingBackward;
  final Color accentColor;
  final VoidCallback onStart;
  final VoidCallback onStartBackward;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onAddBookmark;
  final VoidCallback onRemoveBookmark;
  final VoidCallback onPreviousBookmark;
  final VoidCallback onNextBookmark;
  final VoidCallback onSearch;

  const _ControlBar({
    required this.isListening,
    required this.isManualMode,
    required this.isManualScrolling,
    required this.isScrollingBackward,
    required this.accentColor,
    required this.onStart,
    required this.onStartBackward,
    required this.onStop,
    required this.onReset,
    required this.onBack,
    required this.onSettings,
    required this.onAddBookmark,
    required this.onRemoveBookmark,
    required this.onPreviousBookmark,
    required this.onNextBookmark,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Forward scroll is active when scrolling but NOT backward
    final isActive = isManualMode
        ? (isManualScrolling && settings.scrollSpeed != 0)
        : isListening;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.95), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: onBack,
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
                FocusManager.instance.primaryFocus?.unfocus();
                final newSize = (settings.fontSize - 4).clamp(10.0, 80.0);
                ref.read(settingsProvider.notifier).setFontSize(newSize);
              },
            ),
            // Backward button removed in favor of bidirectional slider
            GestureDetector(
              onTap: isActive ? onStop : onStart,
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
                      : (isListening ? Icons.stop : Icons.mic),
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
                FocusManager.instance.primaryFocus?.unfocus();
                final newSize = (settings.fontSize + 4).clamp(10.0, 80.0);
                ref.read(settingsProvider.notifier).setFontSize(newSize);
              },
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70),
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                onSettings();
              },
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
              onPressed: onRemoveBookmark,
              tooltip: 'Remove bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white70),
              onPressed: onNextBookmark,
              tooltip: 'Next bookmark',
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white70),
              onPressed: onSearch,
              tooltip: 'Search script',
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white70),
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}
