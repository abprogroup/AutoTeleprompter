part of 'content_creator_screen.dart';

extension _ContentCreatorCameraSettings on _ContentCreatorScreenState {
  void _showContentCreatorSettings() {
    var sheetActive = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
          return StatefulBuilder(
            builder: (context, setSheetState) {
              void refreshSheet() {
                if (sheetActive) setSheetState(() {});
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Recording',
                          style: TextStyle(
                            color: Color(0xFFFFBF00),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Camera feed source',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        _buildCameraSourceModeSelector(onChanged: refreshSheet),
                        const SizedBox(height: 10),
                        _buildCameraSelector(onChanged: refreshSheet),
                        const SizedBox(height: 10),
                        const Text(
                          'If a camera or microphone is blocked, open Windows '
                          'Settings > Privacy & security and allow camera and '
                          'microphone access for desktop apps.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildWifiIpFutureNote(),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _isRecording
                                ? null
                                : () {
                                    final future = _initializeCamera();
                                    refreshSheet();
                                    unawaited(
                                        future.whenComplete(refreshSheet));
                                  },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Refresh cameras'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFFBF00),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Video quality',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['480p', '720p', '1080p'].map((resolution) {
                            final selected =
                                settings.videoResolution == resolution;
                            return ChoiceChip(
                              label: Text(resolution),
                              selected: selected,
                              onSelected: (_) =>
                                  _setVideoResolution(resolution),
                              selectedColor: const Color(0xFFFFBF00),
                              labelStyle: TextStyle(
                                color: selected ? Colors.black : Colors.white70,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              backgroundColor: const Color(0xFF1E1E1E),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Recording output',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        _buildRecordingOutputSelector(settings),
                        const SizedBox(height: 8),
                        const Text(
                          'This beta records MP4 directly, with or without '
                          'camera audio. Extra native formats are planned for '
                          'v6 research.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Feed mode',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        _buildContentFeedModeSelector(settings),
                        const SizedBox(height: 12),
                        _buildContentFeedControls(settings),
                        const SizedBox(height: 18),
                        if (settings.contentCreatorFeedMode ==
                            AppSettings.contentCreatorFeedFull) ...[
                          const Text(
                            'Layout readability',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          _buildContentCreatorLayoutSelector(settings),
                          const SizedBox(height: 18),
                        ],
                        const Text(
                          'Recording folder',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        _buildRecordingFolderControls(settings),
                        const SizedBox(height: 8),
                        const Text(
                          'Recordings are normal video/audio files saved in '
                          'this folder. They are not encrypted after export, '
                          'so move or delete them like any other recording.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ).whenComplete(() => sheetActive = false);
  }

  void _showPrompterSettings() {
    final lockBackground = ref.read(settingsProvider).contentCreatorFeedMode ==
        AppSettings.contentCreatorFeedFull;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TeleprompterSettingsPanel(
        scriptBackgroundLocked: lockBackground,
      ),
    );
  }
}
