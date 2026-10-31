import 'package:just_audio/just_audio.dart';

abstract interface class CloudAudioPlayer {
  /// Completes when playback ends or is stopped.
  Future<void> play(
    String path, {
    required double speed,
    required double volume,
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
  }) async {
    await _player.setFilePath(path);
    await _player.setSpeed(speed);
    await _player.setVolume(volume);
    await _player.play();
    await _player.stop();
  }

  @override
  Future<void> stop() => _player.stop();
}
