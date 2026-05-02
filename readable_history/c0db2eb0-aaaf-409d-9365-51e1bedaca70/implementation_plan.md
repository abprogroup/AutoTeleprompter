# Native Windows SAPI Pivot & Offline Pack Flow

Since you've firmly decided that the only native option is the laptop's built-in OS engine (SAPI), we will completely eradicate the embedded browser and deeply integrate the Native Windows Speech UI.

To meet your requirement ("ensure we can download the missing packs if needed - for offline work"), we will rebuild the "Missing Language" dialog specifically for Windows. Instead of Android-style Google app warnings, the Windows dialog will intercept the natively triggered SAPI errors and guide the user exactly to the Windows settings to download offline files.

## User Review Required
Please review the dialog flow approach to ensure it matches your UX expectations. Once reviewed, I will execute the changes!

## Proposed Changes

### `Platform_Windows`

#### 1. [MODIFY] `stt_service_factory.dart`
- Switch the Windows platform to return `SttDesktopAdapter()`.

#### 2. [MODIFY] `teleprompter_screen.dart`
- **Cleanup**: Delete all `webview_windows` imports, controllers, initialization Logic (`_preGrantWebView2Mic`), and the physical `Webview` Stack widget (the invisible 1x1 block).
- **Windows Missing Language Dialog**: Introduce an `if (Platform.isWindows)` branch inside `_showMissingLanguageDialog`.
  - **Body Text**: "Windows requires the $languageName Speech Pack for offline recognition. If no offline pack exists for this language, please enable Online Speech Recognition."
  - **Action Buttons**: Add two responsive buttons that use Dart's native `Process.run('cmd', ['/c', 'start', '...'])` to instantly open specific Windows OS Panels:
    - Button 1: "Download Speech Packs" (Deep links to `ms-settings:speech`)
    - Button 2: "Enable Online Recognition" (Deep links to `ms-settings:privacy-speech`)

#### 3. [DELETE] `stt_browser_adapter.dart`
- Completely remove the browser websocket server to rid the project of web technology.

#### 4. [MODIFY] `pubspec.yaml`
- Strip out `webview_windows`, `shelf`, `shelf_router`, `shelf_web_socket`, and `web_socket_channel` to purify the app dependencies.

## Verification Plan

### Manual Verification
1. Rebuild the `Platform_Windows` application natively (`flutter build windows`).
2. Run the application. Select a language (like Hebrew if the pack is not installed).
3. If SAPI fails to connect due to a missing pack, verify that the new contextual Windows dialog pops up.
4. Click the "Download Speech Packs" button and ensure the native Windows 11/10 Settings panel dynamically opens to the Time & Language context menu, allowing you to explicitly download the pack for offline work.
