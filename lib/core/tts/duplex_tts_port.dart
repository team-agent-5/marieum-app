import 'package:duplex_audio/duplex_audio.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/cloud_tts_port.dart';
import 'package:marieum_app/core/tts/tts_mapping.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_service.dart';

/// iOS live mode voice: plays through the same engine as the microphone so
/// its echo is cancelled. A cached cloud voice is used when there is one,
/// otherwise the chosen device voice speaks at once.
class DuplexTtsPort implements PlaybackTtsPort {
  DuplexTtsPort({
    required this._cloud,
    required this._device,
    DuplexAudio? audio,
  }) : _audio = audio ?? DuplexAudio.instance;

  final CloudTtsPort _cloud;
  final TtsService _device;
  final DuplexAudio _audio;

  @override
  Future<bool> isKoreanAvailable() => _device.isKoreanAvailable();

  @override
  Future<Result<void>> speak(String text) =>
      speakWithPlayback(text, onStarted: () {}, onEnded: () {});

  @override
  Future<Result<void>> speakWithPlayback(
    String text, {
    required void Function() onStarted,
    required void Function() onEnded,
  }) async {
    var started = false;
    void start() {
      started = true;
      onStarted();
    }

    try {
      final file = _cloud.enabled ? await _cloud.cachedAudio(text) : null;
      final bool finished;
      if (file != null) {
        AppLog.tts('duplex cloud ${_cloud.voice.id} "$text"');
        finished = await _audio.playFile(
          file.path,
          rate: CloudTtsPort.speedFor(_cloud.rate),
          volume: TtsMapping.volume(_cloud.volume),
          onStarted: start,
        );
      } else {
        AppLog.tts('duplex device "$text"');
        finished = await _audio.speak(
          text,
          voiceId: _device.currentVoice?.id,
          rate: TtsMapping.rate(VoicePlatform.ios, _device.rate),
          volume: TtsMapping.volume(_device.volume),
          onStarted: start,
        );
      }
      return finished
          ? const Success(null)
          : const FailureResult(TtsFailure('음성 재생이 중지되었습니다.'));
    } on Object catch (error) {
      AppLog.tts('duplex playback failed $error');
      return const FailureResult(TtsFailure('음성을 재생하지 못했어요.'));
    } finally {
      if (started) onEnded();
    }
  }

  @override
  Future<Result<void>> stop() async {
    try {
      await _audio.stopPlayback();
    } on Object {
      // Nothing is playing once the engine has stopped.
    }
    return const Success(null);
  }
}
