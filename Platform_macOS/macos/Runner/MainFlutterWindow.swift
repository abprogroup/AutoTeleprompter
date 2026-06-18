import Cocoa
import FlutterMacOS
import AVFoundation
import CoreVideo
import Speech

class MainFlutterWindow: NSWindow {
  private var macCameraBridge: MacCameraBridge?

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

    let systemChannel = FlutterMethodChannel(
      name: "autoteleprompter/system",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    systemChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "openExternalUrl":
        guard
          let arguments = call.arguments as? [String: Any],
          let target = arguments["target"] as? String
        else {
          result(false)
          return
        }
        let filePath = (arguments["filePath"] as? Bool) ?? false
        let url: URL?
        if filePath {
          url = URL(fileURLWithPath: target)
        } else if let parsed = URL(string: target), parsed.scheme != nil {
          url = parsed
        } else {
          url = URL(fileURLWithPath: target)
        }
        guard let resolvedUrl = url else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          result(NSWorkspace.shared.open(resolvedUrl))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let permissionsChannel = FlutterMethodChannel(
      name: "autoteleprompter/permissions",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    permissionsChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "microphoneStatus":
        result(Self.captureStatusName(
          AVCaptureDevice.authorizationStatus(for: .audio)))
      case "requestMicrophone":
        AVCaptureDevice.requestAccess(for: .audio) { _ in
          DispatchQueue.main.async {
            result(Self.captureStatusName(
              AVCaptureDevice.authorizationStatus(for: .audio)))
          }
        }
      case "cameraStatus":
        result(Self.captureStatusName(
          AVCaptureDevice.authorizationStatus(for: .video)))
      case "requestCamera":
        AVCaptureDevice.requestAccess(for: .video) { _ in
          DispatchQueue.main.async {
            result(Self.captureStatusName(
              AVCaptureDevice.authorizationStatus(for: .video)))
          }
        }
      case "speechStatus":
        result(Self.speechStatusName(SFSpeechRecognizer.authorizationStatus()))
      case "requestSpeech":
        SFSpeechRecognizer.requestAuthorization { status in
          DispatchQueue.main.async {
            result(Self.speechStatusName(status))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    macCameraBridge = MacCameraBridge(
      registry: flutterViewController.engine,
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private static func captureStatusName(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "granted"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  private static func speechStatusName(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "granted"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }
}

private final class MacCameraBridge: NSObject,
  FlutterTexture,
  AVCaptureVideoDataOutputSampleBufferDelegate,
  AVCaptureFileOutputRecordingDelegate {
  private let registry: FlutterTextureRegistry
  private let channel: FlutterMethodChannel
  private let sessionQueue =
    DispatchQueue(label: "com.autoteleprompter.camera.session")
  private let videoOutputQueue =
    DispatchQueue(label: "com.autoteleprompter.camera.video")
  private let pixelBufferLock = NSLock()

  private var session: AVCaptureSession?
  private var movieOutput: AVCaptureMovieFileOutput?
  private var textureId: Int64?
  private var latestPixelBuffer: CVPixelBuffer?
  private var stopRecordingResult: FlutterResult?
  private var currentRecordingPath: String?

  init(registry: FlutterTextureRegistry, binaryMessenger: FlutterBinaryMessenger) {
    self.registry = registry
    self.channel = FlutterMethodChannel(
      name: "autoteleprompter/camera",
      binaryMessenger: binaryMessenger)
    super.init()
    channel.setMethodCallHandler(handle)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    pixelBufferLock.lock()
    defer { pixelBufferLock.unlock() }
    guard let buffer = latestPixelBuffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "listDevices":
      result(Self.availableVideoDevices().map(Self.devicePayload))
    case "initialize":
      initialize(call.arguments, result: result)
    case "startRecording":
      startRecording(call.arguments, result: result)
    case "stopRecording":
      stopRecording(result: result)
    case "dispose":
      dispose(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func availableVideoDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
      mediaType: .video,
      position: .unspecified
    ).devices
  }

  private static func devicePayload(_ device: AVCaptureDevice) -> [String: Any] {
    [
      "id": device.uniqueID,
      "name": device.localizedName,
      "position": positionName(device.position),
    ]
  }

  private static func positionName(_ position: AVCaptureDevice.Position) -> String {
    switch position {
    case .front:
      return "front"
    case .back:
      return "back"
    case .unspecified:
      return "unspecified"
    @unknown default:
      return "unspecified"
    }
  }

  private func initialize(_ arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let deviceId = args?["deviceId"] as? String
    let resolution = args?["resolution"] as? String ?? "720p"
    let enableAudio = args?["enableAudio"] as? Bool ?? false
    let selectedDevice = Self.availableVideoDevices().first {
      device in device.uniqueID == deviceId
    } ?? Self.availableVideoDevices().first

    guard let videoDevice = selectedDevice else {
      result(FlutterError(
        code: "no_camera",
        message: "No macOS camera device is available.",
        details: nil))
      return
    }

    if textureId == nil {
      textureId = registry.register(self)
    }
    guard let textureId = textureId else {
      result(FlutterError(
        code: "texture",
        message: "Camera preview texture could not be registered.",
        details: nil))
      return
    }

    sessionQueue.async {
      do {
        self.teardownSession()
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = Self.sessionPreset(for: resolution)

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(videoInput) {
          session.addInput(videoInput)
        } else {
          throw NSError(
            domain: "AutoTeleprompterCamera",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Video input is unavailable."])
        }

        if enableAudio,
          let audioDevice = AVCaptureDevice.default(for: .audio) {
          let audioInput = try AVCaptureDeviceInput(device: audioDevice)
          if session.canAddInput(audioInput) {
            session.addInput(audioInput)
          }
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String:
            Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
        if session.canAddOutput(videoOutput) {
          session.addOutput(videoOutput)
        } else {
          throw NSError(
            domain: "AutoTeleprompterCamera",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Video output is unavailable."])
        }

        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
          session.addOutput(movieOutput)
        } else {
          throw NSError(
            domain: "AutoTeleprompterCamera",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Movie output is unavailable."])
        }

        session.commitConfiguration()
        session.startRunning()
        self.session = session
        self.movieOutput = movieOutput

        let size = Self.previewSize(for: session.sessionPreset)
        DispatchQueue.main.async {
          result([
            "textureId": textureId,
            "width": size.width,
            "height": size.height,
          ])
        }
      } catch {
        self.teardownSession()
        DispatchQueue.main.async {
          result(FlutterError(
            code: "camera_init",
            message: error.localizedDescription,
            details: nil))
        }
      }
    }
  }

  private static func sessionPreset(for resolution: String) -> AVCaptureSession.Preset {
    let normalized = resolution.lowercased()
    if normalized.contains("1080") {
      return .high
    }
    if normalized.contains("480") {
      return .vga640x480
    }
    return .hd1280x720
  }

  private static func previewSize(for preset: AVCaptureSession.Preset)
    -> (width: Int, height: Int) {
    switch preset {
    case .vga640x480:
      return (640, 480)
    case .hd1280x720:
      return (1280, 720)
    default:
      return (1920, 1080)
    }
  }

  private func startRecording(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
      let path = args["path"] as? String else {
      result(FlutterError(
        code: "bad_args",
        message: "Recording path is required.",
        details: nil))
      return
    }
    sessionQueue.async {
      guard let movieOutput = self.movieOutput else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "not_initialized",
            message: "Camera is not initialized.",
            details: nil))
        }
        return
      }
      if movieOutput.isRecording {
        DispatchQueue.main.async { result(true) }
        return
      }
      self.currentRecordingPath = path
      movieOutput.startRecording(to: URL(fileURLWithPath: path), recordingDelegate: self)
      DispatchQueue.main.async { result(true) }
    }
  }

  private func stopRecording(result: @escaping FlutterResult) {
    sessionQueue.async {
      guard let movieOutput = self.movieOutput, movieOutput.isRecording else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "not_recording",
            message: "Camera is not recording.",
            details: nil))
        }
        return
      }
      self.stopRecordingResult = result
      movieOutput.stopRecording()
    }
  }

  private func dispose(result: @escaping FlutterResult) {
    sessionQueue.async {
      self.teardownSession()
      DispatchQueue.main.async {
        if let textureId = self.textureId {
          self.registry.unregisterTexture(textureId)
          self.textureId = nil
        }
        result(true)
      }
    }
  }

  private func teardownSession() {
    if let movieOutput = movieOutput, movieOutput.isRecording {
      movieOutput.stopRecording()
    }
    session?.stopRunning()
    session = nil
    movieOutput = nil
    clearPixelBuffer()
  }

  private func clearPixelBuffer() {
    pixelBufferLock.lock()
    latestPixelBuffer = nil
    pixelBufferLock.unlock()
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
      let textureId = textureId else { return }

    pixelBufferLock.lock()
    latestPixelBuffer = pixelBuffer
    pixelBufferLock.unlock()

    DispatchQueue.main.async {
      self.registry.textureFrameAvailable(textureId)
    }
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    let pending = stopRecordingResult
    stopRecordingResult = nil
    currentRecordingPath = nil

    DispatchQueue.main.async {
      if let error = error {
        pending?(FlutterError(
          code: "recording_failed",
          message: error.localizedDescription,
          details: nil))
      } else {
        pending?(outputFileURL.path)
      }
    }
  }
}
