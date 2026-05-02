import Flutter
import UIKit
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "autoteleprompter/ios_audio_input",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "listInputs":
          result(Self.listAudioInputs())
        case "setPreferredInput":
          let args = call.arguments as? [String: Any]
          let id = (args?["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          Self.setPreferredInput(id: id, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .measurement,
      options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
    )
    try session.setActive(true)
  }

  private static func listAudioInputs() -> [[String: String]] {
    do {
      try configureAudioSession()
      let inputs = AVAudioSession.sharedInstance().availableInputs ?? []
      return inputs.map { port in
        [
          "id": port.uid,
          "label": "\(port.portName) (\(port.portType.rawValue))"
        ]
      }
    } catch {
      return []
    }
  }

  private static func setPreferredInput(id: String, result: @escaping FlutterResult) {
    do {
      try configureAudioSession()
      let session = AVAudioSession.sharedInstance()
      if id.isEmpty {
        try session.setPreferredInput(nil)
        result("System default microphone")
        return
      }
      guard let input = session.availableInputs?.first(where: { $0.uid == id }) else {
        result(FlutterError(
          code: "INPUT_NOT_FOUND",
          message: "Selected microphone is not available",
          details: nil
        ))
        return
      }
      try session.setPreferredInput(input)
      result("\(input.portName) (\(input.portType.rawValue))")
    } catch {
      result(FlutterError(
        code: "INPUT_ROUTE_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }
}
