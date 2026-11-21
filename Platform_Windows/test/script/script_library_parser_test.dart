import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/script/services/script_library_parser.dart';
import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('atp_parser_test_');
    SharedPreferences.setMockInitialValues({'script_bg_color': 123, 'last_script_title': 'Active'});
  });
  tearDown(() async { await folder.delete(recursive: true); });

  test('folder DOCX import honors color preference without persisting or activating it', () async {
    const xml = '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:background w:color="ABCDEF"/><w:body><w:p><w:r><w:t>Opening speech</w:t>'
        '</w:r></w:p></w:body></w:document>';
    final bytes = utf8.encode(xml);
    final archive = Archive()..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
    final file = File('${folder.path}/Opening.docx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);
    final sourceBytes = await file.readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    final beforePrefs = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    const preference = AppSettings(importColorMode: AppSettings.importColorModeDocument,
        scriptBgColor: 0xFF102030, fontSize: 32, lineSpacing: 1.8,
        lastScriptSessionId: 'active-user-record', lastScriptTitle: 'Active');
    final document = await parseScriptForLibrary(file, preferences: preference);
    final contrast = await parseScriptForLibrary(file, preferences:
        preference.copyWith(importColorMode: AppSettings.importColorModePrompter));
    expect(document.text, contains('Opening speech'));
    expect(document.style['scriptBgColor'], 0xFFABCDEF);
    expect(document.style['futureWordColor'], 0xFF000000);
    expect(document.style['lineSpacing'], 1.8);
    expect(contrast.style['scriptBgColor'], 0xFF000000);
    expect(contrast.style['futureWordColor'], 0xFFFFFFFF);
    expect(contrast.style['lineSpacing'], 1.2);
    expect(preference.lastScriptSessionId, 'active-user-record');
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, beforePrefs);
    expect(await file.readAsBytes(), sourceBytes);
  });
}
