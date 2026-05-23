part of 'script_editor_screen.dart';

String _newEditorDebugSessionId() =>
    DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

enum _EditorDebugArtifactType {
  arrowTraces('arrow_traces'),
  highlightTraces('highlight_traces'),
  selectionTraces('selection_traces'),
  flutterRun('flutter_run'),
  manualQa('manual_qa'),
  sttLogs('stt_logs');

  final String folderName;

  const _EditorDebugArtifactType(this.folderName);
}

const _allEditorDebugArtifactTypes = <_EditorDebugArtifactType>[
  _EditorDebugArtifactType.arrowTraces,
  _EditorDebugArtifactType.highlightTraces,
  _EditorDebugArtifactType.selectionTraces,
  _EditorDebugArtifactType.flutterRun,
  _EditorDebugArtifactType.manualQa,
  _EditorDebugArtifactType.sttLogs,
];

extension _ScriptEditorDebugArtifactParts on _ScriptEditorScreenState {
  bool get _shouldWriteDebugArtifacts {
    if (!mounted) return false;
    return ref.read(settingsProvider).debugMode;
  }

  Directory _debugArtifactRootDirectory() {
    return Directory(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}debug',
    );
  }

  Future<Directory?> _ensureDebugArtifactDirectory(
    _EditorDebugArtifactType type,
    String sessionId,
  ) async {
    if (!_shouldWriteDebugArtifacts) return null;
    assert(_allEditorDebugArtifactTypes.contains(type));
    final directory = Directory(
      '${_debugArtifactRootDirectory().path}${Platform.pathSeparator}'
      '${type.folderName}${Platform.pathSeparator}session_$sessionId',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _debugArtifactPath({
    required Directory directory,
    required String prefix,
    required int sequence,
    required String extension,
  }) {
    final timestamp = _newEditorDebugSessionId();
    return '${directory.path}${Platform.pathSeparator}'
        '${prefix}_${sequence.toString().padLeft(4, "0")}_$timestamp.$extension';
  }

  Future<String?> _captureEditorDebugScreenshot({
    required Directory directory,
    required String prefix,
    required int sequence,
  }) async {
    if (!_shouldWriteDebugArtifacts) return null;
    try {
      final boundary = _editorArrowTraceBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final path = _debugArtifactPath(
        directory: directory,
        prefix: prefix,
        sequence: sequence,
        extension: 'png',
      );
      await File(path).writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return path;
    } catch (error) {
      return 'capture failed: $error';
    }
  }

  Future<String?> _writeDebugArtifactLog({
    required Directory directory,
    required String prefix,
    required int sequence,
    required String trace,
  }) async {
    if (!_shouldWriteDebugArtifacts) return null;
    final path = _debugArtifactPath(
      directory: directory,
      prefix: prefix,
      sequence: sequence,
      extension: 'txt',
    );
    await File(path).writeAsString(trace, flush: true);
    return path;
  }

  Future<void> _openDebugArtifactFolder(
    _EditorDebugArtifactType type,
    String sessionId,
  ) async {
    final directory = await _ensureDebugArtifactDirectory(type, sessionId);
    if (directory == null) return;
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [directory.path]);
      return;
    }
    await Process.start('open', [directory.path]);
  }

  void _resetDebugArtifactSessions(String reason) {
    _resetArrowTraceSession(reason);
    _resetHighlightTraceSession(reason);
    _resetSelectionTraceSession(reason);
  }
}
