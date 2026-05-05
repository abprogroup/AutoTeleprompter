import 'dart:io';

/// Platform-aware file import configuration.
///
/// Android and Windows use the standard import formats.
/// iOS and macOS also support .pages.
class PlatformFileImport {
  const PlatformFileImport._();

  /// File extensions the app can import on the current platform.
  static List<String> get supportedExtensions => [
        'rtf',
        'pdf',
        'docx',
        'doc',
        'odt',
        'txt',
        'md',
        'log',
        'text',
        if (Platform.isIOS || Platform.isMacOS) 'pages',
      ];

  /// Human-readable formats string shown in the "not supported" error dialog.
  static String get formatsLabel {
    const base = 'DOCX, DOC, RTF, PDF, TXT, ODT, MD';
    return (Platform.isIOS || Platform.isMacOS) ? '$base, PAGES' : base;
  }
}
