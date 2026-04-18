import 'dart:io';

/// Platform-aware file import configuration.
///
/// Each platform supports a different set of import formats based on what
/// makes sense for that platform's ecosystem.
///
/// Platform → Extra formats:
/// ┌─────────────────┬────────────────────────────────────────────────┐
/// │ Android         │ Standard formats only                          │
/// │ iOS             │ + .pages  (Apple Pages — common on iPhone/iPad)│
/// │ macOS           │ + .pages  (Apple Pages — native Mac format)    │
/// │ Windows         │ Standard formats only                          │
/// └─────────────────┴────────────────────────────────────────────────┘
class PlatformFileImport {
  const PlatformFileImport._();

  /// File extensions the app can import on the current platform.
  static List<String> get supportedExtensions => [
    'rtf', 'pdf', 'docx', 'doc', 'odt', 'txt', 'md', 'log', 'text',
    if (Platform.isIOS || Platform.isMacOS) 'pages',
  ];

  /// Human-readable formats string shown in the "not supported" error dialog.
  static String get formatsLabel {
    const base = 'DOCX · DOC · RTF · PDF · TXT · ODT · MD';
    return (Platform.isIOS || Platform.isMacOS) ? '$base · PAGES' : base;
  }
}
