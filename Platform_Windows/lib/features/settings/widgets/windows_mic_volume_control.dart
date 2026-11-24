import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/stt/windows_mic_volume_service.dart';

class WindowsMicVolumeControl extends StatefulWidget {
  static const Key sliderKey = Key('windows-mic-volume-slider');
  static const Key boost100ButtonKey = Key('windows-mic-volume-boost-100');
  static const Key muteToggleKey = Key('windows-mic-volume-mute-toggle');

  final String selectedDeviceLabel;
  final Color accentColor;
  final Color backgroundColor;
  final WindowsMicVolumeService service;

  const WindowsMicVolumeControl({
    super.key,
    required this.selectedDeviceLabel,
    required this.accentColor,
    this.backgroundColor = const Color(0xFF111111),
    this.service = const WindowsMicVolumeService(),
  });

  @override
  State<WindowsMicVolumeControl> createState() =>
      _WindowsMicVolumeControlState();
}

class _WindowsMicVolumeControlState extends State<WindowsMicVolumeControl> {
  WindowsMicVolumeInfo? _info;
  double? _draggingValue;
  bool _loading = true;
  bool _updating = false;
  DateTime _lastLiveSet = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant WindowsMicVolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDeviceLabel != widget.selectedDeviceLabel) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    final info = await widget.service.getMicVolume(
      preferredLabel: widget.selectedDeviceLabel,
    );
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  Future<void> _applyVolume(int percent, {bool? muted}) async {
    if (_updating) return;
    _updating = true;
    try {
      final updated = await widget.service.setMicVolume(
        preferredLabel: widget.selectedDeviceLabel,
        volumePercent: percent.clamp(0, 100),
        muted: muted,
      );
      if (!mounted) return;
      setState(() {
        _info = updated;
        _draggingValue = null;
      });
    } finally {
      _updating = false;
    }
  }

  void _onSliderChanged(double value) {
    setState(() => _draggingValue = value);
    final now = DateTime.now();
    if (now.difference(_lastLiveSet).inMilliseconds >= 80 && !_updating) {
      _lastLiveSet = now;
      unawaited(
        widget.service
            .setMicVolume(
              preferredLabel: widget.selectedDeviceLabel,
              volumePercent: value.round(),
              muted: value.round() > 0 ? false : null,
            )
            .then((updated) {
              if (!mounted || _draggingValue != null) return;
              setState(() => _info = updated);
            }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final available = info?.available == true;
    final displayPercent =
        (_draggingValue?.round() ?? info?.volumePercent ?? 0).clamp(0, 100);
    final isMuted = info?.muted == true;
    final isLow = available && (isMuted || displayPercent < 80);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isLow
                  ? Colors.orangeAccent.withValues(alpha: 0.65)
                  : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: WindowsMicVolumeControl.muteToggleKey,
                tooltip: isMuted ? 'Unmute microphone' : 'Mute microphone',
                onPressed:
                    available
                        ? () => unawaited(
                          _applyVolume(
                            displayPercent == 0 && isMuted
                                ? 100
                                : displayPercent,
                            muted: !isMuted,
                          ),
                        )
                        : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  isMuted || displayPercent == 0
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  color:
                      isMuted
                          ? Colors.redAccent
                          : isLow
                          ? Colors.orangeAccent
                          : widget.accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Windows Mic Volume',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (available)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isMuted
                                      ? Colors.redAccent.withValues(alpha: 0.22)
                                      : isLow
                                      ? Colors.orangeAccent.withValues(
                                        alpha: 0.22,
                                      )
                                      : Colors.green.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isMuted ? 'MUTED ($displayPercent%)' : '$displayPercent%',
                              style: TextStyle(
                                color:
                                    isMuted
                                        ? Colors.redAccent
                                        : isLow
                                        ? Colors.orangeAccent
                                        : Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _loading
                          ? 'Reading Windows microphone input level...'
                          : available
                          ? (info!.deviceName.isNotEmpty
                              ? info.deviceName
                              : 'Active Windows microphone')
                          : (info?.error ??
                              'Windows microphone volume unavailable.'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh Windows mic volume',
                onPressed: _loading ? null : () => unawaited(_refresh()),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          if (available) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      key: WindowsMicVolumeControl.sliderKey,
                      value: displayPercent.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      activeColor:
                          isLow ? Colors.orangeAccent : widget.accentColor,
                      inactiveColor: Colors.white12,
                      onChanged: _onSliderChanged,
                      onChangeEnd:
                          (value) => unawaited(
                            _applyVolume(
                              value.round(),
                              muted: value.round() > 0 ? false : null,
                            ),
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  key: WindowsMicVolumeControl.boost100ButtonKey,
                  onPressed:
                      (!isMuted && displayPercent >= 100)
                          ? null
                          : () => unawaited(_applyVolume(100, muted: false)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isLow ? Colors.orangeAccent : widget.accentColor,
                    side: BorderSide(
                      color:
                          isLow
                              ? Colors.orangeAccent.withValues(alpha: 0.75)
                              : Colors.white24,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('100%', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            if (isLow)
              Text(
                isMuted
                    ? 'Microphone is muted in Windows — tap 100% or unmute so speech recognition can hear you.'
                    : 'Windows mic volume is at $displayPercent%. Speech recognition works best at 80–100%.',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
