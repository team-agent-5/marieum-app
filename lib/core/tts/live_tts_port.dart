import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/cloud_tts_port.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

class LiveTtsPort implements PlaybackTtsPort {
  LiveTtsPort(this._cloud);
  final CloudTtsPort _cloud;

  @override
  Future<bool> isKoreanAvailable() => _cloud.isKoreanAvailable();

  @override
  Future<Result<void>> speak(String text) =>
      speakWithPlayback(text, onStarted: () {}, onEnded: () {});

  @override
  Future<Result<void>> speakWithPlayback(
    String text, {
    required void Function() onStarted,
    required void Function() onEnded,
  }) => _cloud.speakCached(text, onStarted: onStarted, onEnded: onEnded);

  @override
  Future<Result<void>> stop() => _cloud.stop();
}
