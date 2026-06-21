import 'dart:io';
import 'dart:convert';

import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/services/docx_service.dart';
import 'package:autoteleprompter/features/script/services/rtf_service.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ios-import-test-');
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('DOCX import preserves rich inline styles and highlights', () async {
    final file = File('${tempDir.path}/styled.docx');
    await file.writeAsBytes(DocxService.generate(
      '[bg=#FFFF00][i][u][font=Lora]Styled[/font][/u][/i][/bg]',
    ));

    final parsed =
        await container.read(scriptProvider.notifier).parseFile(file);

    expect(parsed.isError, isFalse);
    expect(parsed.text, contains('[bg=#FFFF00]'));
    expect(parsed.text, contains('[i]'));
    expect(parsed.text, contains('[u]'));
    expect(parsed.text, contains('[font=Lora]'));
    expect(parsed.text, contains('Styled'));
  });

  test('RTF import preserves Hebrew text, color, font, and highlight',
      () async {
    final file = File('${tempDir.path}/styled.rtf');
    await file.writeAsBytes(RtfService.generate(
      '[bg=#FFFF00][color=#FF4444][font=Lora][u][i]שלום[/i][/u][/font][/color][/bg]',
      defaultRtl: true,
    ));

    final parsed =
        await container.read(scriptProvider.notifier).parseFile(file);

    expect(parsed.isError, isFalse);
    expect(parsed.text, contains('שלום'));
    expect(parsed.text, contains('[bg=#FFFF00]'));
    expect(parsed.text, contains('[color=#FF4444]'));
    expect(parsed.text, contains('[font=Lora]'));
    expect(parsed.text, contains('[u]'));
    expect(parsed.text, contains('[i]'));
  });

  test('invalid archive import returns an error result', () async {
    final file = File('${tempDir.path}/broken.docx');
    await file.writeAsString('not a zip');

    final parsed =
        await container.read(scriptProvider.notifier).parseFile(file);

    expect(parsed.isError, isTrue);
    expect(parsed.errorMessage, contains('corrupted'));
    expect(parsed.errorMessage, contains('DOCX'));
  });

  test('script persistence stores sourcePath metadata for cloud sync',
      () async {
    const sourcePath = '/private/var/mobile/Containers/script.docx';

    await container.read(settingsProvider.notifier).saveScript(
          'Saved text',
          title: 'script.docx',
          type: 'DOCX',
          sourcePath: sourcePath,
          sessionId: 'session-source-path',
        );

    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList('recentScripts') ?? const [];
    expect(recents, isNotEmpty);

    final recent = jsonDecode(recents.first) as Map<String, dynamic>;
    expect(recent['sourcePath'], sourcePath);
  });
}
