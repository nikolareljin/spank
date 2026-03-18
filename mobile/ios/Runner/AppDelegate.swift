import AVFoundation
import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let motionManager = CMMotionManager()
  private let settingsKey = "spank_mobile"
  private var audioPlayer: AVAudioPlayer?
  private var lastEmit: TimeInterval = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let methods = FlutterMethodChannel(
      name: "spank/methods",
      binaryMessenger: controller.binaryMessenger
    )
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handleMethod(call: call, result: result)
    }

    let motion = FlutterEventChannel(
      name: "spank/motion",
      binaryMessenger: controller.binaryMessenger
    )
    motion.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethod(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "loadSettings":
      result(loadSettings())
    case "saveSettings":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Expected settings map.", details: nil))
        return
      }
      saveSettings(args)
      result(nil)
    case "playAsset":
      guard
        let args = call.arguments as? [String: Any],
        let assetPath = args["assetPath"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing assetPath.", details: nil))
        return
      }

      let volume = max(0.0, min((args["volume"] as? Double) ?? 1.0, 1.0))
      do {
        try playAsset(assetPath: assetPath, volume: volume)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "playback_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func loadSettings() -> [String: Any] {
    let defaults: [String: Any] = [
      "threshold": 1.8,
      "sampleIntervalMs": 40,
      "cooldownMs": 1200,
      "soundPack": "pain",
      "volume": 1.0,
      "dryRun": false,
    ]
    let stored = UserDefaults.standard.dictionary(forKey: settingsKey) ?? [:]
    return defaults.merging(stored) { _, new in new }
  }

  private func saveSettings(_ settings: [String: Any]) {
    UserDefaults.standard.set(settings, forKey: settingsKey)
  }

  private func playAsset(assetPath: String, volume: Double) throws {
    let assetKey =
      registrar(forPlugin: "spank_mobile")?.lookupKey(forAsset: assetPath) ?? assetPath
    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
      throw NSError(
        domain: "spank_mobile",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Unable to find \(assetPath) in app bundle."]
      )
    }

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)

    audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    audioPlayer?.volume = Float(volume)
    audioPlayer?.prepareToPlay()
    audioPlayer?.play()
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    guard motionManager.isAccelerometerAvailable else {
      return FlutterError(
        code: "sensor_unavailable",
        message: "Accelerometer is not available.",
        details: nil
      )
    }

    let sampleIntervalMs =
      ((arguments as? [String: Any])?["sampleIntervalMs"] as? Double) ?? 40
    lastEmit = 0
    motionManager.accelerometerUpdateInterval = max(sampleIntervalMs / 1000.0, 0.016)
    motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
      guard let self else { return }
      if let error {
        events(
          FlutterError(
            code: "sensor_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
        return
      }

      guard let data else { return }

      let now = Date().timeIntervalSince1970 * 1000
      if self.lastEmit != 0 && now - self.lastEmit < sampleIntervalMs {
        return
      }
      self.lastEmit = now

      events([
        "timestampMs": Int64(now.rounded()),
        "x": data.acceleration.x,
        "y": data.acceleration.y,
        "z": data.acceleration.z,
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motionManager.stopAccelerometerUpdates()
    return nil
  }
}
