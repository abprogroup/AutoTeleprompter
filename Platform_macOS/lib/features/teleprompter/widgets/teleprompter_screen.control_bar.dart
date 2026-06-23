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
  final Key? settingsKey;
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
    this.settingsKey,
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
    final hasBookmarkAccess = ref.watch(authProvider).hasPremiumAccess;
    // Forward scroll is active when scrolling but NOT backward
    final speechActive = isListening || isStarting;
    final showSpeechControl = speechActive || !isManualMode;
    final isBooting = showSpeechControl && isStarting;
    final isActive = showSpeechControl
        ? isListening && !isBooting
        : (isManualScrolling && settings.scrollSpeed != 0);
    final VoidCallback? primaryAction =
        isBooting ? null : (isActive ? onStop : onStart);
    final IconData primaryIcon = showSpeechControl
        ? (isBooting
            ? Icons.hourglass_top
            : (isListening ? Icons.stop : Icons.mic))
        : (isManualScrolling && settings.scrollSpeed != 0
            ? Icons.pause
            : Icons.play_arrow);
    final Color primaryColor = isActive
        ? Colors.red
        : (isBooting ? accentColor.withValues(alpha: 0.74) : accentColor);
    final String primaryTooltip = showSpeechControl
        ? (isBooting
            ? 'Starting speech-to-text'
            : (isListening ? 'Stop speech-to-text' : 'Start speech-to-text'))
        : (isManualScrolling && settings.scrollSpeed != 0
            ? 'Pause manual scroll'
            : 'Start manual scroll');
    final effectiveFontSize =
        ref.read(scriptProvider.notifier).effectiveFontSize(settings.fontSize);
    void applyPresenterFontSize(double size) {
      final clamped = size.clamp(14.0, 120.0).toDouble();
      ref.read(teleprompterProvider.notifier).setVisibleWordWindow(null, null);
      unawaited(ref.read(scriptProvider.notifier).applyBaseFontSize(clamped));
      onFontSizeChanged(clamped);
    }

    void showLockedBookmarks() {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Bookmarks are included with Pro.'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Connect',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.0, 0.58, 1.0],
          colors: [
            Colors.black.withValues(alpha: 0.98),
            Colors.black.withValues(alpha: 0.68),
            Colors.black.withValues(alpha: 0.0),
          ],
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
              icon: Icon(
                hasBookmarkAccess
                    ? Icons.skip_previous_rounded
                    : Icons.lock_outline_rounded,
                color: hasBookmarkAccess ? Colors.white70 : Colors.white38,
              ),
              onPressed:
                  hasBookmarkAccess ? onPreviousBookmark : showLockedBookmarks,
              tooltip: hasBookmarkAccess
                  ? 'Previous bookmark'
                  : 'Bookmarks are included with Pro',
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
            Tooltip(
              message: primaryTooltip,
              child: Material(
                color: primaryColor,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkResponse(
                  onTap: primaryAction,
                  customBorder: const CircleBorder(),
                  containedInkWell: true,
                  hoverColor: Colors.white.withValues(alpha: 0.18),
                  highlightColor: Colors.white.withValues(alpha: 0.24),
                  splashColor: Colors.white.withValues(alpha: 0.22),
                  mouseCursor: primaryAction == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(
                      primaryIcon,
                      color: isActive ? Colors.white : Colors.black,
                      size: 30,
                    ),
                  ),
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
              icon: Icon(
                hasBookmarkAccess
                    ? Icons.bookmark_add_outlined
                    : Icons.lock_outline_rounded,
                color: hasBookmarkAccess ? Colors.white70 : Colors.white38,
              ),
              onPressed:
                  hasBookmarkAccess ? onAddBookmark : showLockedBookmarks,
              tooltip: hasBookmarkAccess
                  ? 'Add bookmark'
                  : 'Bookmarks are included with Pro',
            ),
            IconButton(
              icon: Icon(
                hasBookmarkAccess
                    ? Icons.bookmark_remove_outlined
                    : Icons.lock_outline_rounded,
                color: hasBookmarkAccess ? Colors.white70 : Colors.white38,
              ),
              onPressed: !hasBookmarkAccess
                  ? showLockedBookmarks
                  : (isListening || isStarting ? null : onRemoveBookmark),
              tooltip: hasBookmarkAccess
                  ? 'Remove bookmark'
                  : 'Bookmarks are included with Pro',
            ),
            IconButton(
              key: settingsKey,
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
              icon: Icon(
                hasBookmarkAccess
                    ? Icons.skip_next_rounded
                    : Icons.lock_outline_rounded,
                color: hasBookmarkAccess ? Colors.white70 : Colors.white38,
              ),
              onPressed:
                  hasBookmarkAccess ? onNextBookmark : showLockedBookmarks,
              tooltip: hasBookmarkAccess
                  ? 'Next bookmark'
                  : 'Bookmarks are included with Pro',
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
