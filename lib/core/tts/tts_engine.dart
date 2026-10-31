import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

abstract interface class TtsEngine {
  Future<bool> isLanguageAvailable(String language);
  Future<void> configure({required double rate, required double volume});
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({required this._platform, FlutterTts? plugin})
    : _plugin = plugin ?? FlutterTts() {
    _plugin
      ..setCompletionHandler(_complete)
      ..setCancelHandler(
        () => _complete(const TtsFailure('음성 재생이 중지되었습니다.')),
      )
      ..setErrorHandler(
        (message) => _complete(TtsFailure(message.toString())),
      );
  }

  final VoicePlatform _platform;
  final FlutterTts _plugin;
  Completer<void>? _pending;

  void _complete([TtsFailure? failure]) {
    final pending = _pending;
    _pending = null;
    if (pending == null || pending.isCompleted) return;
    if (failure == null) {
      pending.complete();
    } else {
      pending.completeError(failure);
    }
  }

  @override
  Future<bool> isLanguageAvailable(String language) async =>
      await _plugin.isLanguageAvailable(language) == true;

  @override
  Future<void> configure({required double rate, required double volume}) async {
    // Callbacks also settle cancellation, unlike the native iOS speak result.
    await _plugin.awaitSpeakCompletion(false);
    if (_platform == VoicePlatform.ios) {
      final result = await _plugin.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        ],
      );
      if (result != 1) throw const TtsFailure('오디오 세션을 설정하지 못했습니다.');
    }
    await _plugin.setLanguage('ko-KR');
    await _plugin.setSpeechRate(rate);
    await _plugin.setVolume(volume);
  }

  @override
  Future<void> speak(String text) async {
    if (_pending != null) throw const TtsFailure('이미 음성을 재생하고 있습니다.');
    final pending = Completer<void>();
    _pending = pending;
    // Listen before an immediate platform completion or error.
    final started = _plugin
        .speak(text)
        .then<void>(
          (result) {
            if (result != 1) _complete(const TtsFailure('음성을 재생하지 못했습니다.'));
          },
          onError: (Object error, StackTrace stack) {
            _complete(TtsFailure(error.toString()));
          },
        );
    await Future.wait([started, pending.future]);
  }

  @override
  Future<void> stop() async {
    try {
      await _plugin.stop();
    } finally {
      _complete(const TtsFailure('음성 재생이 중지되었습니다.'));
    }
  }
}
