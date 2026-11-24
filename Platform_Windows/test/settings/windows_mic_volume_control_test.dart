import 'package:autoteleprompter/features/settings/widgets/windows_mic_volume_control.dart';
import 'package:autoteleprompter/platform/stt/windows_mic_volume_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWindowsMicVolumeService extends WindowsMicVolumeService {
  _FakeWindowsMicVolumeService({
    required this.volumePercent,
    this.muted = false,
  });

  int volumePercent;
  bool muted;
  final String deviceName = 'Microphone Array (Intel)';
  int setCalls = 0;

  @override
  Future<WindowsMicVolumeInfo> getMicVolume({String? preferredLabel}) async {
    return WindowsMicVolumeInfo(
      available: true,
      volumePercent: volumePercent,
      muted: muted,
      deviceName: deviceName,
    );
  }

  @override
  Future<WindowsMicVolumeInfo> setMicVolume({
    String? preferredLabel,
    required int volumePercent,
    bool? muted,
  }) async {
    setCalls++;
    this.volumePercent = volumePercent.clamp(0, 100);
    if (muted != null) {
      this.muted = muted;
    } else if (this.volumePercent > 0) {
      this.muted = false;
    }
    return WindowsMicVolumeInfo(
      available: true,
      volumePercent: this.volumePercent,
      muted: this.muted,
      deviceName: deviceName,
    );
  }
}

void main() {
  testWidgets('warns when Windows mic volume is low (50%) and boosts to 100%', (
    tester,
  ) async {
    final service = _FakeWindowsMicVolumeService(volumePercent: 50);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: WindowsMicVolumeControl(
            selectedDeviceLabel: 'System default microphone',
            accentColor: const Color(0xFFFFBF00),
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('works best at 80–100%'), findsOneWidget);

    await tester.tap(find.byKey(WindowsMicVolumeControl.boost100ButtonKey));
    await tester.pumpAndSettle();

    expect(service.volumePercent, 100);
    expect(service.setCalls, 1);
    expect(find.textContaining('works best at 80–100%'), findsNothing);
  });

  testWidgets('shows muted warning and unmutes when toggling mute', (
    tester,
  ) async {
    final service = _FakeWindowsMicVolumeService(
      volumePercent: 90,
      muted: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: WindowsMicVolumeControl(
            selectedDeviceLabel: 'System default microphone',
            accentColor: const Color(0xFFFFBF00),
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MUTED (90%)'), findsOneWidget);
    expect(find.textContaining('muted in Windows'), findsOneWidget);

    await tester.tap(find.byKey(WindowsMicVolumeControl.muteToggleKey));
    await tester.pumpAndSettle();

    expect(service.muted, isFalse);
    expect(find.text('90%'), findsOneWidget);
  });
}
