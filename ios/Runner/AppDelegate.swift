import AVFoundation
import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveTranscriber") {
      LiveTranscriber.register(with: registrar)
    }
  }
}

/// On-device recognition fed with PCM16 16kHz mono chunks from Dart.
final class LiveTranscriber: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var session = 0

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "marieum/live_transcriber", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LiveTranscriber(channel: channel), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      start(locale: call.arguments as? String ?? "ko-KR", result: result)
    case "append":
      if let data = call.arguments as? FlutterStandardTypedData {
        append(data.data)
      }
      result(nil)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(locale: String, result: @escaping FlutterResult) {
    stop()
    session += 1
    let current = session
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard current == self.session, status == .authorized,
          let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
          recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else {
          result(false)
          return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.recognizer = recognizer
        self.request = request
        self.task = recognizer.recognitionTask(with: request) { [weak self] response, _ in
          guard let response else { return }
          let text = response.bestTranscription.formattedString
          DispatchQueue.main.async {
            guard let self, current == self.session else { return }
            self.channel.invokeMethod("partial", arguments: text)
          }
        }
        result(true)
      }
    }
  }

  private func append(_ data: Data) {
    guard let request else { return }
    let count = data.count / 2
    guard count > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
      let samples = buffer.floatChannelData?[0]
    else { return }
    buffer.frameLength = AVAudioFrameCount(count)
    data.withUnsafeBytes { raw in
      for index in 0..<count {
        let value = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
        samples[index] = Float(value) / 32768
      }
    }
    request.append(buffer)
  }

  private func stop() {
    session += 1
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    recognizer = nil
  }
}
