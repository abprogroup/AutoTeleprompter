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
  final Key? sttKey;
  final Key? settingsKey;
  final Key? bookmarksKey;
  final Key? resetKey;

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
    this.sttKey,
    this.settingsKey,
    this.bookmarksKey,
    this.resetKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final bookmarksEnabled = ref.watch(authProvider).hasPremiumAccess;
    final bookmarkIconColor =
        bookmarksEnabled ? Colors.white70 : Colors.white24;
    final bookmarkTooltip =
        bookmarksEnabled ? null : 'Bookmarks are included with Pro';
    // Forward scroll is active when scrolling but NOT backward
    final isActive = isManualMode
        ? (isManualScrolling && settings.scrollSpeed != 0)
        : isListening;
    void applyPresenterFontSize(double size) {
      final clamped = size.clamp(14.0, 120.0).toDouble();
      unawaited(ref.read(settingsProvider.notifier).setFontSize(clamped));
      unawaited(
        ref.read(scriptProvider.notifier).updateStyleMetadata(
              fontSize: clamped,
            ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.98),
            Colors.black.withValues(alpha: 0.88),
            Colors.black.withValues(alpha: 0.36),
          ],
          stops: const [0.0, 0.62, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: onBack,
                ),
                KeyedSubtree(
                  key: bookmarksKey,
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            Icon(Icons.skip_previous, color: bookmarkIconColor),
                        onPressed: onPreviousBookmark,
                        tooltip: bookmarkTooltip ?? 'Previous bookmark',
                      ),
                      IconButton(
                        icon: Icon(Icons.bookmark_add_outlined,
                            color: bookmarkIconColor),
                        onPressed: onAddBookmark,
                        tooltip: bookmarkTooltip ?? 'Add bookmark',
                      ),
                      IconButton(
                        icon: Icon(Icons.bookmark_remove_outlined,
                            color: bookmarkIconColor),
                        onPressed: onRemoveBookmark,
                        tooltip: bookmarkTooltip ?? 'Remove bookmark',
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, color: bookmarkIconColor),
                        onPressed: onNextBookmark,
                        tooltip: bookmarkTooltip ?? 'Next bookmark',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white70),
                  onPressed: onSearch,
                  tooltip: 'Search script',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  key: settingsKey,
                  icon: const Icon(Icons.tune, color: Colors.white70),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    onSettings();
                  },
                ),
                IconButton(
                  icon: const Text('A',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    applyPresenterFontSize(settings.fontSize - 4);
                  },
                ),
                // Backward button removed in favor of bidirectional slider
                GestureDetector(
                  key: sttKey,
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
                    applyPresenterFontSize(settings.fontSize + 4);
                  },
                ),
                IconButton(
                  key: resetKey,
                  icon: const Icon(Icons.replay, color: Colors.white70),
                  onPressed: onReset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
