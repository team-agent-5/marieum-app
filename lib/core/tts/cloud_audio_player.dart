import 'dart:async';

import 'package:just_audio/just_audio.dart';

abstract interface class CloudAudioPlayer {
  /// Completes when playback ends or is stopped.
  Future<void> play(
    String path, {
    required double speed,
    required double volume,
    void Function()? onStarted,
  });
  Future<void> stop();
}

class JustAudioCloudPlayer implements CloudAudioPlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(
    String path, {
    required double speed,
    required double volume,
    void Function()? onStarted,
  }) async {
    await _player.setFilePath(path);
    await _player.setSpeed(speed);
    await _player.setVolume(volume);
    var started = false;
    final subscription = _player.playerStateStream.listen((state) {
      if (!started &&
          state.playing &&
          state.processingState == ProcessingState.ready) {
        started = true;
        onStarted?.call();
      }
    });
    try {
      await _player.play();
    } finally {
      await subscription.cancel();
      await _player.stop();
    }
  }

  @override
  Future<void> stop() => _player.stop();
}
