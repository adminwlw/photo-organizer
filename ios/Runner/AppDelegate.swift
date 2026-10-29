import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var volumeStreamHandler: HardwareVolumeStreamHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let handler = HardwareVolumeStreamHandler()
    let channel = FlutterEventChannel(
      name: "com.sim360.albumcleaner/hardware_volume",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setStreamHandler(handler)
    volumeStreamHandler = handler
  }
}

private final class HardwareVolumeStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var observation: NSKeyValueObservation?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    let session = AVAudioSession.sharedInstance()
    observation = session.observe(\.outputVolume, options: [.old, .new]) {
      [weak self] _, change in
      guard change.oldValue != change.newValue else { return }
      DispatchQueue.main.async { self?.eventSink?(change.newValue) }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observation?.invalidate()
    observation = nil
    eventSink = nil
    return nil
  }
}
