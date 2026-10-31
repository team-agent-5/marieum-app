import 'dart:async';

import 'package:flutter/services.dart';

/// Records the microphone and plays the app's voice through one iOS
/// voice-processing audio engine, so echo cancellation removes exactly what
/// the app plays.
class DuplexAudio {
  DuplexAudio._() {
    _channel.setMethodCallHandler(_onCall);
  }

  static final instance = DuplexAudio._();

  static const _channel = MethodChannel('marieum/duplex_audio');
  static const _mic = EventChannel('marieum/duplex_audio/mic');

  final _started = <int, void Function()>{};
  int _nextId = 0;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'started') {
      _started.remove(call.arguments as int)?.call();
    }
    return null;
  }

  /// Starts the engine; the stream carries PCM16 16 kHz mono chunks.
  /// [gainDb] is applied after Apple's processing with a soft limiter.
  Future<Stream<Uint8List>> start({double gainDb = 0, bool agc = true}) async {
    final stream = _mic.receiveBroadcastStream().map(
      (chunk) => chunk as Uint8List,
    );
    await _channel.invokeMethod<void>('start', {'gainDb': gainDb, 'agc': agc});
    return stream;
  }

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Plays an audio file; completes with whether it played to the end.
  Future<bool> playFile(
    String path, {
    required double rate,
    required double volume,
    void Function()? onStarted,
  }) => _play('playFile', {
    'path': path,
    'rate': rate,
    'volume': volume,
  }, onStarted);

  /// Speaks with the system voice; [rate] is AVSpeechUtterance's rate.
  Future<bool> speak(
    String text, {
    required double rate,
    required double volume,
    String? voiceId,
    void Function()? onStarted,
  }) => _play('speak', {
    'text': text,
    'voiceId': voiceId,
    'rate': rate,
    'volume': volume,
  }, onStarted);

  Future<void> stopPlayback() => _channel.invokeMethod<void>('stopPlayback');

  Future<bool> _play(
    String method,
    Map<String, Object?> arguments,
    void Function()? onStarted,
  ) async {
    final id = _nextId++;
    if (onStarted != null) _started[id] = onStarted;
    try {
      return await _channel.invokeMethod<bool>(method, {
            ...arguments,
            'id': id,
          }) ??
          false;
    } finally {
      _started.remove(id);
    }
  }
}
