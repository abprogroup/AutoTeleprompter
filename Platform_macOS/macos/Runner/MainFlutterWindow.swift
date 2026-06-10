import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Presenter real-fullscreen channel — mirrors the Windows
    // `autoteleprompter/window` channel so shared Dart callers work unchanged.
    // Uses native NSWindow fullscreen (green-button / Spaces fullscreen).
    let windowChannel = FlutterMethodChannel(
      name: "autoteleprompter/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "setPresenterFullscreen":
        let enabled = (call.arguments as? Bool) ?? false
        let isFullscreen = self.styleMask.contains(.fullScreen)
        if enabled != isFullscreen {
          // Fullscreen transition is async; report the requested state.
          self.toggleFullScreen(nil)
        }
        result(enabled)
      case "isPresenterFullscreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
