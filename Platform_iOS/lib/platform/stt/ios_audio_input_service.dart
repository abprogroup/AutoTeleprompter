import 'package:flutter/services.dart';

import 'abstract_stt_service.dart';

class IosAudioInputService {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/ios_audio_input');

  const IosAudioInputService._();

  static Future<List<SttAudioInputDevice>> listInputs() async {
    final raw = await _channel.invokeListMethod<dynamic>('listInputs');
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          final id = item['id']?.toString() ?? '';
          final label = item['label']?.toString() ?? '';
          if (id.isEmpty || label.isEmpty) return null;
          return SttAudioInputDevice(id: id, label: label);
        })
        .whereType<SttAudioInputDevice>()
        .toList(growable: false);
  }

  static Future<String> setPreferredInput(String? deviceId) async {
    final selectedLabel = await _channel.invokeMethod<String>(
      'setPreferredInput',
      {'id': deviceId?.trim() ?? ''},
    );
    return selectedLabel ?? 'System default microphone';
  }
}
