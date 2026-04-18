import 'dart:io';

/// Platform-specific keyboard behavior helpers.
///
/// Mobile soft keyboards (iOS / Android) don't have a dedicated Dismiss key,
/// so we need to show an in-app "Done" toolbar above the keyboard.
/// On macOS / Windows the physical keyboard has Escape / Enter — no toolbar needed.
class PlatformKeyboard {
  const PlatformKeyboard._();

  /// Whether to show a "Done" dismiss bar above the on-screen keyboard.
  /// True on iOS only — Android's keyboard already has a dismiss button in the
  /// navigation bar. On macOS and Windows there is no soft keyboard at all.
  static bool get showDoneBar => Platform.isIOS;
}
