import AVFoundation
import Flutter

/// Records the microphone and plays the app's voice through one
/// voice-processing AVAudioEngine, so echo cancellation subtracts exactly
/// what the app plays. Separate players are invisible to it.
public class DuplexAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let channel: FlutterMethodChannel
  private var sink: FlutterEventSink?

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let timePitch = AVAudioUnitTimePitch()
  private let synthesizer = AVSpeechSynthesizer()
  private var playFormat: AVAudioFormat?
  private var running = false

  private let micFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
  private var micConverter: AVAudioConverter?
  private var gain: Float = 1

  private var playConverters: [String: AVAudioConverter] = [:]
  private var playbackId: Int?
  private var playbackResult: FlutterResult?
  private var scheduled = 0
  private var played = 0
  private var synthesisDone = false
  private var startedPlaying = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "marieum/duplex_audio", binaryMessenger: registrar.messenger())
    let instance = DuplexAudioPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "marieum/duplex_audio/mic", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    engine.attach(player)
    engine.attach(timePitch)
    NotificationCenter.default.addObserver(
      self, selector: #selector(configurationChanged),
      name: .AVAudioEngineConfigurationChange, object: engine)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "start":
        try start(gainDb: args["gainDb"] as? Double ?? 0, agc: args["agc"] as? Bool ?? false)
        result(nil)
      case "stop":
        stop()
        result(nil)
      case "playFile":
        try playFile(
          id: args["id"] as? Int ?? 0, path: args["path"] as? String ?? "",
          rate: Float(args["rate"] as? Double ?? 1), volume: Float(args["volume"] as? Double ?? 1),
          result: result)
      case "speak":
        try speak(
          id: args["id"] as? Int ?? 0, text: args["text"] as? String ?? "",
          voiceId: args["voiceId"] as? String, rate: Float(args["rate"] as? Double ?? 0.5),
          volume: Float(args["volume"] as? Double ?? 1), result: result)
      case "stopPlayback":
        stopPlayback()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "duplex_audio", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: Engine

  private func start(gainDb: Double, agc: Bool) throws {
    if running { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setActive(true)

    let input = engine.inputNode
    try input.setVoiceProcessingEnabled(true)
    // Apple's gain control keeps quiet speakers audible after processing.
    input.isVoiceProcessingAGCEnabled = agc
    if #available(iOS 17.0, *) {
      // Only the app's own voice is playing; nothing else should be ducked.
      input.voiceProcessingOtherAudioDuckingConfiguration =
        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
          enableAdvancedDucking: false, duckingLevel: .min)
    }
    gain = Float(pow(10, gainDb / 20))
    try connect()
    engine.prepare()
    try engine.start()
    running = true
  }

  private func connect() throws {
    let input = engine.inputNode
    let output = engine.mainMixerNode.outputFormat(forBus: 0)
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: output.sampleRate > 0 ? output.sampleRate : 48000,
        channels: 1)
    else { throw DuplexError.format }
    playFormat = format
    playConverters.removeAll()
    engine.connect(player, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)

    let inputFormat = input.outputFormat(forBus: 0)
    guard let converter = AVAudioConverter(from: inputFormat, to: micFormat) else {
      throw DuplexError.format
    }
    converter.downmix = true
    micConverter = converter
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.deliver(buffer)
    }
  }

  private func stop() {
    guard running else { return }
    running = false
    stopPlayback()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    try? engine.inputNode.setVoiceProcessingEnabled(false)
  }

  @objc private func configurationChanged(_ notification: Notification) {
    // A route change stops the engine; pick up the new formats and resume.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.running else { return }
      self.stopPlayback()
      do {
        try self.connect()
        self.engine.prepare()
        try self.engine.start()
      } catch {
        self.running = false
      }
    }
  }

  // MARK: Microphone

  private func deliver(_ buffer: AVAudioPCMBuffer) {
    guard let converter = micConverter, sink != nil else { return }
    let ratio = micFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
    guard let out = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: capacity) else { return }
    var fed = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
      if fed {
        status.pointee = .noDataNow
        return nil
      }
      fed = true
      status.pointee = .haveData
      return buffer
    }
    guard error == nil, out.frameLength > 0, let samples = out.floatChannelData?[0] else { return }
    let count = Int(out.frameLength)
    var data = Data(count: count * 2)
    let gain = self.gain
    data.withUnsafeMutableBytes { raw in
      let pcm = raw.bindMemory(to: Int16.self)
      for i in 0..<count {
        // tanh is near-linear for speech and rounds off peaks the gain
        // would otherwise clip.
        pcm[i] = Int16(tanhf(samples[i] * gain) * 32767).littleEndian
      }
    }
    DispatchQueue.main.async { [weak self] in
      self?.sink?(FlutterStandardTypedData(bytes: data))
    }
  }

  // MARK: Playback

  private func begin(id: Int, rate: Float, volume: Float, result: @escaping FlutterResult) throws {
    guard running else { throw DuplexError.notRunning }
    stopPlayback()
    playbackId = id
    playbackResult = result
    scheduled = 0
    played = 0
    synthesisDone = false
    startedPlaying = false
    timePitch.rate = rate
    player.volume = volume
  }

  private func playFile(
    id: Int, path: String, rate: Float, volume: Float, result: @escaping FlutterResult
  ) throws {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
    else { throw DuplexError.format }
    try file.read(into: buffer)
    try begin(id: id, rate: rate, volume: volume, result: result)
    schedule(buffer, id: id)
    synthesisDone = true
    finishIfDone(id: id)
  }

  private func speak(
    id: Int, text: String, voiceId: String?, rate: Float, volume: Float,
    result: @escaping FlutterResult
  ) throws {
    try begin(id: id, rate: 1, volume: volume, result: result)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice =
      voiceId.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
      ?? AVSpeechSynthesisVoice(language: "ko-KR")
    utterance.rate = rate
    // Buffers are scheduled as they are synthesized so speech starts at once.
    synthesizer.write(utterance) { [weak self] buffer in
      guard let pcm = buffer as? AVAudioPCMBuffer else { return }
      let copy = pcm.frameLength > 0 ? Self.copy(pcm) : nil
      DispatchQueue.main.async {
        guard let self, self.playbackId == id else { return }
        if let copy {
          self.schedule(copy, id: id)
        } else {
          self.synthesisDone = true
          self.finishIfDone(id: id)
        }
      }
    }
  }

  private func schedule(_ buffer: AVAudioPCMBuffer, id: Int) {
    guard let converted = convertForPlayback(buffer) else { return }
    scheduled += 1
    player.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.playbackId == id else { return }
        self.played += 1
        self.finishIfDone(id: id)
      }
    }
    if !startedPlaying {
      startedPlaying = true
      player.play()
      channel.invokeMethod("started", arguments: id)
    }
  }

  private func finishIfDone(id: Int) {
    guard playbackId == id, synthesisDone, played >= scheduled else { return }
    let result = playbackResult
    playbackId = nil
    playbackResult = nil
    player.stop()
    result?(startedPlaying)
  }

  private func stopPlayback() {
    synthesizer.stopSpeaking(at: .immediate)
    let result = playbackResult
    playbackId = nil
    playbackResult = nil
    player.stop()
    result?(false)
  }

  private func convertForPlayback(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let format = playFormat else { return nil }
    if buffer.format == format { return buffer }
    let key = "\(buffer.format.commonFormat.rawValue)-\(buffer.format.sampleRate)-\(buffer.format.channelCount)-\(buffer.format.isInterleaved)"
    let converter: AVAudioConverter
    if let cached = playConverters[key] {
      converter = cached
    } else {
      guard let created = AVAudioConverter(from: buffer.format, to: format) else { return nil }
      created.downmix = true
      playConverters[key] = created
      converter = created
    }
    let ratio = format.sampleRate / buffer.format.sampleRate
    guard
      let out = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64))
    else { return nil }
    var fed = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
      if fed {
        status.pointee = .noDataNow
        return nil
      }
      fed = true
      status.pointee = .haveData
      return buffer
    }
    return error == nil && out.frameLength > 0 ? out : nil
  }

  private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard
      let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
    else { return nil }
    copy.frameLength = buffer.frameLength
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
      for c in 0..<channels { dst[c].update(from: src[c], count: frames) }
    } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
      for c in 0..<channels { dst[c].update(from: src[c], count: frames) }
    } else if let src = buffer.int32ChannelData, let dst = copy.int32ChannelData {
      for c in 0..<channels { dst[c].update(from: src[c], count: frames) }
    } else {
      return nil
    }
    return copy
  }
}

private enum DuplexError: LocalizedError {
  case format
  case notRunning

  var errorDescription: String? {
    switch self {
    case .format: return "Unsupported audio format."
    case .notRunning: return "The audio engine is not running."
    }
  }
}
