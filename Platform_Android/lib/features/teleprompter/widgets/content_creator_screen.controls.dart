part of 'content_creator_screen.dart';

final RegExp _creatorTagStripRe = RegExp(
    r'\[\/?(y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg)\]|\[\/?(size|color|bg|font|align)(?:=[^\]]+)?\]|\*\*');

extension _ContentCreatorControls on _ContentCreatorScreenState {
  // ---------------------------------------------------------------------------
  // Bottom control bars: a fixed lower row (most-needed, present-mode style)
  // and a draggable (horizontally scrollable) upper row holding the overflow.
  // ---------------------------------------------------------------------------

  Widget _buildCreatorControls(
    AppSettings settings,
    dynamic tState,
    bool audioOnly,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // UPPER: draggable overflow row.
        _buildCreatorOverflowBar(settings, tState, audioOnly),
        if (_creatorSearchToolbarVisible) ...[
          const SizedBox(height: 8),
          _buildCreatorSearchToolbar(),
        ],
        const SizedBox(height: 14),
        // LOWER: fixed, most-needed controls — the record button sits between
        // the mic (speech) and settings buttons to save vertical space.
        _buildCreatorFixedBar(settings, tState, audioOnly),
      ],
    );
  }

  Widget _buildCreatorFixedBar(
    AppSettings settings,
    dynamic tState,
    bool audioOnly,
  ) {
    final speechLinked = settings.contentCreatorRecordingControlsSpeech;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _creatorBarIcon(Icons.close, 'Back to editor', _exitContentCreator),
          // Separate, prominent STT button only when record is NOT linked to
          // speech — shows starting (hourglass) / listening (stop) clearly.
          if (!speechLinked) _buildCreatorSpeechButton(tState),
          _buildCreatorRecordButton(audioOnly, speechLinked),
          _creatorBarIcon(
              Icons.tune, 'Prompter settings', _showPrompterSettings,
              key: _creatorSettingsKey),
          _creatorBarIcon(
              Icons.replay, 'Restart script', _resetCreatorPosition),
        ],
      ),
    );
  }

  Widget _buildCreatorSpeechButton(dynamic tState) {
    final starting = tState.isStarting == true;
    final active = tState.isListening == true;
    final icon = starting
        ? Icons.hourglass_top_rounded
        : (active ? Icons.stop : Icons.mic);
    final bg = active
        ? Colors.red
        : (starting
            ? const Color(0xFFFFBF00).withValues(alpha: 0.72)
            : const Color(0xFFFFBF00));
    final tooltip = starting
        ? 'Starting speech…'
        : (active ? 'Stop speech' : 'Start speech');
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: _creatorSpeechKey,
        onTap: starting ? null : _toggleSpeechSession,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: Icon(
            icon,
            color: active ? Colors.white : Colors.black,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorRecordButton(bool audioOnly, bool speechLinked) {
    final busy = _isRecording || _recordStartInFlight;
    // Amber ring when the record button also drives speech (combined mode).
    final ringColor =
        speechLinked && !busy ? const Color(0xFFFFBF00) : Colors.white;
    return GestureDetector(
      key: _creatorRecordKey,
      onTap: _recordStartInFlight ? null : _toggleRecording,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: 3),
        ),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording
                ? Colors.red
                : _recordStartInFlight
                    ? const Color(0xFFFFBF00)
                    : Colors.red.withValues(alpha: 0.55),
          ),
          child: Icon(
            _isRecording
                ? Icons.stop
                : _recordStartInFlight
                    ? Icons.hourglass_top_rounded
                    : (audioOnly ? Icons.mic : Icons.videocam),
            color: _recordStartInFlight ? Colors.black : Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorOverflowBar(
    AppSettings settings,
    dynamic tState,
    bool audioOnly,
  ) {
    final hasBookmarkAccess = ref.watch(authProvider).hasPremiumAccess;
    final bookmarkColor = hasBookmarkAccess ? Colors.white70 : Colors.white24;
    const lockTip = 'Bookmarks are included with Pro';

    final busy = _isRecording || _recordStartInFlight;
    final buttons = <Widget>[
      _creatorBarIcon(
        Icons.edit_note,
        'Edit at current position',
        busy ? null : () => unawaited(_editContentAtCurrentPosition()),
      ),
      // Switch the feed on/off both ways: audio mode → add video; video mode →
      // stop the feed (audio only).
      _creatorBarIcon(
        audioOnly ? Icons.videocam_outlined : Icons.videocam_off_outlined,
        audioOnly
            ? 'Turn camera feed on (video)'
            : 'Turn camera feed off (audio)',
        busy ? null : _toggleCreatorFeed,
      ),
      if (!audioOnly && _availableCameras.length > 1)
        _creatorBarIcon(
          Icons.flip_camera_ios_outlined,
          'Switch front/back camera',
          busy ? null : _flipCreatorCamera,
        ),
      if (!audioOnly)
        _creatorBarIcon(
          Icons.photo_camera_outlined,
          'Camera & feed settings',
          busy ? null : _showCreatorSettings,
        ),
      _creatorBarText('A', 'Smaller font', () => _applyCreatorFontDelta(-2)),
      _creatorBarText('A', 'Larger font', () => _applyCreatorFontDelta(2),
          large: true),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.skip_previous_rounded : Icons.lock_outline,
        hasBookmarkAccess ? 'Previous bookmark' : lockTip,
        () => _jumpCreatorBookmark(-1),
        color: bookmarkColor,
      ),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.bookmark_add_outlined : Icons.lock_outline,
        hasBookmarkAccess ? 'Add bookmark' : lockTip,
        _addCreatorBookmark,
        color: bookmarkColor,
      ),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.bookmark_remove_outlined : Icons.lock_outline,
        hasBookmarkAccess ? 'Remove bookmark' : lockTip,
        _isRecording ? null : _deleteCreatorBookmarkAtCurrentPosition,
        color: bookmarkColor,
      ),
      _creatorBarIcon(
        hasBookmarkAccess ? Icons.skip_next_rounded : Icons.lock_outline,
        hasBookmarkAccess ? 'Next bookmark' : lockTip,
        () => _jumpCreatorBookmark(1),
        color: bookmarkColor,
      ),
      _creatorBarIcon(Icons.search, 'Search script', _showCreatorSearchDialog),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _overflowBarController,
        physics: const BouncingScrollPhysics(),
        child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }

  Widget _creatorBarIcon(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    Key? key,
    Color color = Colors.white70,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, color: onPressed == null ? Colors.white24 : color),
    );
  }

  Widget _creatorBarText(String text, String tooltip, VoidCallback onPressed,
      {bool large = false}) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Text(
        text,
        style: TextStyle(
          color: Colors.white70,
          fontSize: large ? 22 : 15,
          fontWeight: large ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera + font
  // ---------------------------------------------------------------------------

  Future<void> _flipCreatorCamera() async {
    if (_availableCameras.length < 2) return;
    final current = _selectedCameraIndex < 0 ? 0 : _selectedCameraIndex;
    final currentDir = _availableCameras[current].lensDirection;
    final wantFront = currentDir != CameraLensDirection.front;
    final nextIndex = _availableCameras.indexWhere(
      (c) =>
          c.lensDirection ==
          (wantFront ? CameraLensDirection.front : CameraLensDirection.back),
    );
    if (nextIndex < 0 || nextIndex == current) return;
    _selectedCameraIndex = nextIndex;
    await _initializeCamera();
  }

  void _applyCreatorFontDelta(double delta) {
    final settings = ref.read(settingsProvider);
    final clamped = (settings.fontSize + delta).clamp(14.0, 120.0).toDouble();
    if (clamped == settings.fontSize) return;
    unawaited(ref.read(settingsProvider.notifier).setFontSize(clamped));
  }

  /// Return to the editor with the caret placed at the word currently on the
  /// reading line ("Edit current position").
  Future<void> _editContentAtCurrentPosition() async {
    if (_isRecording || _recordStartInFlight) {
      _showContentSnack('Stop recording before editing.');
      return;
    }
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) {
      await _exitContentCreator();
      return;
    }
    final index = _snapCreatorBookmarkIndex(
      script,
      ref
          .read(teleprompterProvider)
          .confirmedWordIndex
          .clamp(0, script.words.length - 1)
          .toInt(),
    );
    final pos = _editorPositionForCreatorWord(script, index);
    ref.read(pendingEditorCursorProvider.notifier).state =
        EditorCursorTarget(pos.block, pos.offset);
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(ref.read(teleprompterProvider.notifier).stopSession());
  }

  /// Open the full present-mode settings (same panel the present screen uses)
  /// so every prompter setting is available in the creator modes too.
  void _showPrompterSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TeleprompterSettingsPanel(),
    );
  }

  /// Toggle the camera feed on/off (switch between video and audio-only),
  /// available from both modes.
  Future<void> _toggleCreatorFeed() async {
    if (_isRecording || _recordStartInFlight) return;
    final audioOnly = _contentAudioOnlyMode(ref.read(settingsProvider));
    final next = audioOnly
        ? AppSettings.contentCreatorRecordingFormatMp4
        : AppSettings.contentCreatorRecordingFormatAudio;
    await ref
        .read(settingsProvider.notifier)
        .setContentCreatorRecordingFormat(next);
    if (!mounted) return;
    if (next == AppSettings.contentCreatorRecordingFormatAudio) {
      // Tear the camera down for audio-only.
      _cameraInitGeneration++;
      final controller = _cameraController;
      _cameraController = null;
      unawaited(controller?.dispose());
      _setContentCreatorState(() => _isInit = true);
    } else {
      await _initializeCamera();
    }
  }

  // ---------------------------------------------------------------------------
  // Position jump shared by bookmarks + search
  // ---------------------------------------------------------------------------

  void _jumpCreatorToWordIndex(int index, Script script) {
    final clamped = index.clamp(0, script.words.length - 1).toInt();
    _lastFollowedWordIndex = clamped;
    ref
        .read(teleprompterProvider.notifier)
        .jumpToPosition(clamped, script: script);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToWordIndex(clamped);
    });
  }

  // ---------------------------------------------------------------------------
  // Bookmarks (Pro) — same model/scope as present mode.
  // ---------------------------------------------------------------------------

  bool _creatorBookmarksAllowed() {
    if (ref.read(authProvider).hasPremiumAccess) return true;
    _showContentSnack('Bookmarks are included with Pro');
    return false;
  }

  Future<void> _loadCreatorBookmarks(Script script,
      {bool force = false}) async {
    final key = ScriptBookmarkService.scopeKey(script.sessionId, script.title);
    if (!force &&
        _bookmarkScopeKey == key &&
        (_bookmarksLoaded || _bookmarkLoadingKey == key)) {
      return;
    }
    _bookmarkScopeKey = key;
    _bookmarkLoadingKey = key;
    _bookmarksLoaded = false;
    final loaded = await ScriptBookmarkService.load(key);
    if (!mounted || _bookmarkScopeKey != key) return;
    _setContentCreatorState(() {
      _bookmarks = loaded;
      _bookmarksLoaded = true;
      _bookmarkLoadingKey = null;
    });
  }

  Future<void> _saveCreatorBookmarks(Script script) async {
    final key = ScriptBookmarkService.scopeKey(script.sessionId, script.title);
    _bookmarkScopeKey = key;
    _bookmarksLoaded = true;
    await ScriptBookmarkService.save(key, _bookmarks);
  }

  String _bookmarkLabelForCreatorWord(Script script, int wordIndex) {
    final buffer = StringBuffer();
    for (var i = wordIndex; i < script.words.length && i < wordIndex + 8; i++) {
      final word = script.words[i];
      if (word.isNewline) continue;
      final text = word.raw
          .replaceAll(_creatorTagStripRe, '')
          .replaceAll(RegExp(r'\[\/?align=[^\]]+\]'), '')
          .trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }
    final label = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (label.isEmpty) return 'Position ${wordIndex + 1}';
    return label.length <= 44 ? label : '${label.substring(0, 44)}...';
  }

  ({int block, int offset}) _editorPositionForCreatorWord(
    Script script,
    int wordIndex,
  ) {
    final words = script.words;
    final rawText = script.rawText;
    if (rawText.isEmpty || words.isEmpty) return (block: 0, offset: 0);
    final target = _snapCreatorBookmarkIndex(script, wordIndex);
    final blocks = rawText.split('\n');
    var cursor = 0;
    for (var block = 0; block < blocks.length; block++) {
      final text = blocks[block];
      final matches = RegExp(r'\S+').allMatches(text).toList();
      if (matches.isNotEmpty &&
          target >= cursor &&
          target < cursor + matches.length) {
        final local = (target - cursor).clamp(0, matches.length - 1).toInt();
        return (block: block, offset: matches[local].start);
      }
      cursor += _creatorBlockTokenLength(
        text,
        includeSoftBreak: block < blocks.length - 1,
      );
    }
    return (block: 0, offset: 0);
  }

  int _creatorBlockTokenLength(String text, {required bool includeSoftBreak}) {
    if (text.trim().isEmpty) return 1;
    final wordCount = RegExp(r'\S+').allMatches(text).length;
    return wordCount + (includeSoftBreak ? 1 : 0);
  }

  int _snapCreatorBookmarkIndex(Script script, int index) {
    if (script.words.isEmpty) return 0;
    final start = index.clamp(0, script.words.length - 1).toInt();
    for (var i = start; i < script.words.length; i++) {
      final word = script.words[i];
      if (!word.isNewline && word.normalized.isNotEmpty) return i;
    }
    for (var i = start; i >= 0; i--) {
      final word = script.words[i];
      if (!word.isNewline && word.normalized.isNotEmpty) return i;
    }
    return start;
  }

  Future<void> _addCreatorBookmark() async {
    if (!_creatorBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadCreatorBookmarks(script, force: true);
    final index = _snapCreatorBookmarkIndex(
      script,
      ref
          .read(teleprompterProvider)
          .confirmedWordIndex
          .clamp(0, script.words.length - 1)
          .toInt(),
    );
    final editorPosition = _editorPositionForCreatorWord(script, index);
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForCreatorWord(script, index),
      wordIndex: index,
      blockIndex: editorPosition.block,
      offset: editorPosition.offset,
      createdAt: DateTime.now(),
    );
    _setContentCreatorState(() {
      _bookmarks = ScriptBookmarkService.upsert(_bookmarks, bookmark);
    });
    await _saveCreatorBookmarks(script);
    _showContentSnack('Bookmark saved: ${bookmark.label}');
  }

  Future<void> _jumpCreatorBookmark(int direction) async {
    if (!_creatorBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadCreatorBookmarks(script, force: true);
    if (!mounted) return;
    if (_bookmarks.isEmpty) {
      _showContentSnack('No bookmarks saved for this script yet');
      return;
    }
    final current = ref.read(teleprompterProvider).confirmedWordIndex;
    int target;
    if (direction >= 0) {
      target = _bookmarks.indexWhere((b) => b.wordIndex > current);
      if (target == -1) target = 0;
    } else {
      target = _bookmarks.lastIndexWhere((b) => b.wordIndex < current);
      if (target == -1) target = _bookmarks.length - 1;
    }
    final bookmark = _bookmarks[target];
    _jumpCreatorToWordIndex(bookmark.wordIndex, script);
    _showContentSnack('Bookmark: ${bookmark.label}');
  }

  Future<void> _deleteCreatorBookmarkAtCurrentPosition() async {
    if (!_creatorBookmarksAllowed()) return;
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    await _loadCreatorBookmarks(script, force: true);
    if (!mounted) return;
    if (_bookmarks.isEmpty) {
      _showContentSnack('No bookmarks saved for this script yet');
      return;
    }
    final current = ref
        .read(teleprompterProvider)
        .confirmedWordIndex
        .clamp(0, script.words.length - 1)
        .toInt();
    final next =
        _bookmarks.where((b) => b.wordIndex != current).toList(growable: false);
    if (next.length == _bookmarks.length) {
      _showContentSnack('No bookmark at the current position');
      return;
    }
    _setContentCreatorState(() => _bookmarks = next);
    await _saveCreatorBookmarks(script);
    _showContentSnack('Bookmark deleted');
  }
}
