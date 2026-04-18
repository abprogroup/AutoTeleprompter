/// Platform-aware file import configuration for Android.
///
/// Android supports standard document formats.
/// Apple Pages (.pages) is iOS/macOS only and is not included here.
class PlatformFileImport {
  const PlatformFileImport._();

  /// File extensions the app can import on Android.
  static const List<String> supportedExtensions = [
    'rtf', 'pdf', 'docx', 'doc', 'odt', 'txt', 'md', 'log', 'text',
  ];

  /// Human-readable formats string shown in the "not supported" error dialog.
  static const String formatsLabel = 'DOCX · DOC · RTF · PDF · TXT · ODT · MD';
}
