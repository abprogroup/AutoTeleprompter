part of 'content_creator_screen.dart';

extension _ContentCreatorCameraWidgets on _ContentCreatorScreenState {
  bool get _cameraPreviewReady {
    return _isActiveCameraInitialized() && _activeCameraPreviewSize() != null;
  }

  Widget _buildCameraFallback({bool compact = false}) {
    if (_isCameraInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
      );
    }
    return Center(
      child: Container(
        margin: compact
            ? const EdgeInsets.all(12)
            : const EdgeInsets.fromLTRB(24, 18, 24, 96),
        padding: EdgeInsets.all(compact ? 12 : 18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(compact ? 6 : 14),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white54, size: 34),
            SizedBox(height: compact ? 8 : 10),
            Text(
              _cameraError ?? 'Camera is unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            SizedBox(height: compact ? 8 : 12),
            if (_availableCameras.isNotEmpty && !compact) ...[
              _buildCameraSourceModeSelector(),
              const SizedBox(height: 10),
              _buildCameraSelector(),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () => _initializeCamera(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFBF00),
                side: const BorderSide(color: Color(0xFFFFBF00)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraSelector({VoidCallback? onChanged}) {
    final sourceCameras =
        _camerasForSourceMode(_availableCameras, _cameraSourceMode);
    if (_availableCameras.isEmpty || sourceCameras.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _isCameraInitializing
            ? null
            : _availableCameras.isEmpty
                ? () => _initializeCamera()
                : () {
                    final future =
                        _setCameraSourceMode(_ContentCameraSourceMode.all);
                    onChanged?.call();
                    unawaited(future.whenComplete(() => onChanged?.call()));
                  },
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(_availableCameras.isEmpty
            ? 'Find cameras'
            : 'No ${_cameraSourceModeLabel(_cameraSourceMode)} cameras - show all'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFFBF00),
          side: const BorderSide(color: Color(0xFFFFBF00)),
        ),
      );
    }

    var selectedIndex =
        sourceCameras.indexWhere((c) => c.name == _selectedCameraName);
    if (selectedIndex < 0) selectedIndex = 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedIndex,
          isExpanded: true,
          dropdownColor: const Color(0xFF181818),
          iconEnabledColor: const Color(0xFFFFBF00),
          style: const TextStyle(color: Colors.white),
          items: [
            for (var i = 0; i < sourceCameras.length; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Text(
                  _cameraLabel(sourceCameras[i], i),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _isRecording
              ? null
              : (index) {
                  if (index == null) return;
                  final future = _selectCamera(sourceCameras[index]);
                  onChanged?.call();
                  unawaited(future.whenComplete(() => onChanged?.call()));
                },
        ),
      ),
    );
  }

  Widget _buildCameraSourceModeSelector({VoidCallback? onChanged}) {
    const modes = _ContentCameraSourceMode.values;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in modes)
          Tooltip(
            message: _cameraSourceModeHelp(mode),
            child: ChoiceChip(
              label: Text(_cameraSourceModeLabel(mode)),
              selected: _cameraSourceMode == mode,
              onSelected: _isRecording
                  ? null
                  : (_) {
                      final future = _setCameraSourceMode(mode);
                      onChanged?.call();
                      unawaited(future.whenComplete(() => onChanged?.call()));
                    },
              selectedColor: const Color(0xFFFFBF00),
              backgroundColor: const Color(0xFF1E1E1E),
              labelStyle: TextStyle(
                color: _cameraSourceMode == mode ? Colors.black : Colors.white,
                fontWeight: _cameraSourceMode == mode
                    ? FontWeight.bold
                    : FontWeight.w600,
              ),
              side: BorderSide(
                color: _cameraSourceMode == mode
                    ? const Color(0xFFFFBF00)
                    : Colors.white24,
              ),
            ),
          ),
      ],
    );
  }
}
