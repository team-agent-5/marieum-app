import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';

abstract interface class TtsEngine {
  Future<bool> isLanguageAvailable(String language);
  Future<List<TtsVoice>> koreanVoices();
  Future<void> setVoice(TtsVoice voice);
  Future<void> configure({required double rate, required double volume});
  Future<void> speak(String text, {void Function()? onStarted});
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({required this._platform, FlutterTts? plugin})
    : _plugin = plugin ?? FlutterTts() {
    _plugin
      ..setStartHandler(() => _onStarted?.call())
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
  void Function()? _onStarted;

  void _complete([TtsFailure? failure]) {
    final pending = _pending;
    _pending = null;
    _onStarted = null;
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
  Future<List<TtsVoice>> koreanVoices() async {
    final Object? voices = await _plugin.getVoices;
    if (voices is! List) return const [];
    final result = <TtsVoice>[];
    for (final Object? raw in voices) {
      if (raw is! Map) continue;
      final name = _text(raw['name']);
      final locale = _text(raw['locale']);
      if (name == null ||
          locale == null ||
          !locale.toLowerCase().startsWith('ko')) {
        continue;
      }
      result.add(
        TtsVoice(
          id: _text(raw['identifier']) ?? _text(raw['id']) ?? name,
          name: name,
          locale: locale,
          quality: _quality(raw['quality']),
          requiresNetwork: _networkRequired(raw),
        ),
      );
    }
    return result;
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  TtsVoiceQuality _quality(Object? value) {
    final text = _text(value)?.toLowerCase();
    if (_platform == VoicePlatform.ios) {
      return switch (text) {
        'premium' => TtsVoiceQuality.premium,
        'enhanced' => TtsVoiceQuality.enhanced,
        'default' => TtsVoiceQuality.normal,
        _ => TtsVoiceQuality.unknown,
      };
    }
    final number = value is num ? value : num.tryParse(text ?? '');
    if (number != null) {
      if (number >= 500) return TtsVoiceQuality.high;
      if (number >= 300) return TtsVoiceQuality.normal;
      return TtsVoiceQuality.unknown;
    }
    return switch (text) {
      'very high' => TtsVoiceQuality.high,
      'high' || 'normal' => TtsVoiceQuality.normal,
      _ => TtsVoiceQuality.unknown,
    };
  }

  static bool _networkRequired(Map<Object?, Object?> voice) {
    final value = voice['network_required'];
    if (value == true || value == 1 || value == '1' || value == 'true') {
      return true;
    }
    final features = voice['features'];
    final tokens = switch (features) {
      String() => features.split(RegExp(r'[\s,;]+')),
      Iterable<Object?>() => features.whereType<String>(),
      _ => const <String>[],
    };
    return tokens.any((feature) => feature.toLowerCase() == 'networktts');
  }

  @override
  Future<void> setVoice(TtsVoice voice) async {
    final Object? result = await _plugin.setVoice({
      'name': voice.name,
      'locale': voice.locale,
      // iOS picks the exact voice by identifier; same-name voices differ in
      // quality, so name and locale alone are ambiguous.
      if (voice.id != voice.name) 'identifier': voice.id,
    });
    if (result != 1) throw const TtsFailure('목소리를 설정하지 못했습니다.');
  }

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
  Future<void> speak(String text, {void Function()? onStarted}) async {
    if (_pending != null) throw const TtsFailure('이미 음성을 재생하고 있습니다.');
    final pending = Completer<void>();
    _pending = pending;
    _onStarted = onStarted;
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
