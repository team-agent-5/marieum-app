import 'dart:async';

import 'package:flutter/services.dart';

/// On-device speech recognition fed with the recorder's PCM16 16kHz mono
/// chunks, so the microphone stays with the recorder. Only used to show text
/// while recording; the server transcription remains the result.
abstract interface class LiveTranscriber {
  /// False when on-device recognition is unavailable or not allowed.
  Future<bool> start();
  void append(Uint8List pcm);
  Stream<String> get partials;
  Future<void> stop();
}

class UnavailableLiveTranscriber implements LiveTranscriber {
  @override
  Future<bool> start() async => false;
  @override
  void append(Uint8List pcm) {}
  @override
  Stream<String> get partials => const Stream.empty();
  @override
  Future<void> stop() async {}
}

class PlatformLiveTranscriber implements LiveTranscriber {
  PlatformLiveTranscriber({
    this._channel = const MethodChannel('marieum/live_transcriber'),
    this.locale = 'ko-KR',
  });

  final MethodChannel _channel;
  final String locale;
  final _partials = StreamController<String>.broadcast();
  bool _active = false;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Future<bool> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'partial' && _active && call.arguments is String) {
        _partials.add(call.arguments as String);
      }
    });
    try {
      _active = await _channel.invokeMethod<bool>('start', locale) ?? false;
    } on Object {
      _active = false;
    }
    return _active;
  }

  @override
  void append(Uint8List pcm) {
    if (!_active) return;
    unawaited(
      _channel.invokeMethod<void>('append', pcm).catchError((Object _) {}),
    );
  }

  @override
  Future<void> stop() async {
    final wasActive = _active;
    _active = false;
    _channel.setMethodCallHandler(null);
    if (wasActive) {
      try {
        await _channel.invokeMethod<void>('stop');
      } on Object {
        // Recognition is best effort.
      }
    }
    await _partials.close();
  }
}
