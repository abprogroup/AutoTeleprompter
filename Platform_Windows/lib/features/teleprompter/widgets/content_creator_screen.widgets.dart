part of 'content_creator_screen.dart';

extension _ContentCreatorScreenWidgets on _ContentCreatorScreenState {
  Widget _buildReadingSurfaceLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.99),
                Colors.black.withValues(alpha: 0.99),
                Colors.black.withValues(alpha: 0.96),
                Colors.black.withValues(alpha: 0.76),
                Colors.black.withValues(alpha: 0.36),
                Colors.transparent,
              ],
              stops: const [0.0, 0.44, 0.62, 0.74, 0.86, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraBackgroundLayer() {
    final height = MediaQuery.sizeOf(context).height;
    final feedHeight = (height * 0.42).clamp(280.0, height * 0.50);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: feedHeight,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x33FFBF00), width: 1),
              ),
            ),
            child: _isInit
                ? _buildFadedCameraPreviewLayer()
                : _buildCameraFallback(),
          ),
        ),
      ],
    );
  }

  Widget _buildFadedCameraPreviewLayer() {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.72,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 1.0),
                  Colors.black.withValues(alpha: 0.58),
                  Colors.black.withValues(alpha: 0.24),
                  Colors.black.withValues(alpha: 0.26),
                  Colors.black.withValues(alpha: 0.72),
                ],
                stops: const [0.0, 0.16, 0.42, 0.72, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.92,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.30),
                  Colors.black.withValues(alpha: 0.78),
                ],
                stops: const [0.35, 0.74, 1.0],
              ),
            ),
          ),
          CustomPaint(
            painter: _LensHUDPainter(),
            child: Container(),
          ),
          if (_isRecording) _buildRecordingTimerHud(),
          if (_countdown > 0) _buildCountdownOverlay(),
        ],
      ),
    );
  }

  Widget _buildRecordingTimerHud() {
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.circle, color: Colors.white, size: 8),
            const SizedBox(width: 6),
            Text(
              _formatTimer(_recordSeconds),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Text(
          '$_countdown',
          style: const TextStyle(
            color: Color(0xFFFFBF00),
            fontSize: 80,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCameraFallback() {
    if (_isCameraInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
      );
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 18, 24, 92),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white54, size: 34),
            const SizedBox(height: 10),
            Text(
              _cameraError ?? 'Camera is unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (_availableCameras.isNotEmpty) ...[
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

  Widget _buildCameraSelector() {
    final sourceCameras =
        _camerasForSourceMode(_availableCameras, _cameraSourceMode);
    if (_availableCameras.isEmpty || sourceCameras.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _isCameraInitializing
            ? null
            : _availableCameras.isEmpty
                ? () => _initializeCamera()
                : () => _setCameraSourceMode(_ContentCameraSourceMode.all),
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
                  _selectCamera(sourceCameras[index]);
                },
        ),
      ),
    );
  }

  Widget _buildCameraSourceModeSelector() {
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
              onSelected:
                  _isRecording ? null : (_) => _setCameraSourceMode(mode),
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

  void _showContentCreatorSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
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
                    _buildCameraSourceModeSelector(),
                    const SizedBox(height: 10),
                    _buildCameraSelector(),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed:
                            _isRecording ? null : () => _initializeCamera(),
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
                        final selected = settings.videoResolution == resolution;
                        return ChoiceChip(
                          label: Text(resolution),
                          selected: selected,
                          onSelected: (_) => _setVideoResolution(resolution),
                          selectedColor: const Color(0xFFFFBF00),
                          labelStyle: TextStyle(
                            color: selected ? Colors.black : Colors.white70,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                          ),
                          backgroundColor: const Color(0xFF1E1E1E),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showPrompterSettings();
                      },
                      icon: const Icon(Icons.tune),
                      label: const Text('Prompter settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPrompterSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TeleprompterSettingsPanel(),
    );
  }
}

class _LensHUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFBF00).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const radius = 60.0;
    const bracketSize = 12.0;

    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius + bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY - radius),
        Offset(centerX - radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius - bracketSize, centerY - radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY - radius),
        Offset(centerX + radius, centerY - radius + bracketSize), paint);

    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius + bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX - radius, centerY + radius),
        Offset(centerX - radius, centerY + radius - bracketSize), paint);

    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius - bracketSize, centerY + radius), paint);
    canvas.drawLine(Offset(centerX + radius, centerY + radius),
        Offset(centerX + radius, centerY + radius - bracketSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
