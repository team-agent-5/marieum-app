import 'dart:async';
import 'dart:io';

import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/cloud_audio_player.dart';
import 'package:marieum_app/core/tts/cloud_tts_cache.dart';
import 'package:marieum_app/core/tts/cloud_tts_client.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';
import 'package:marieum_app/core/tts/tts_mapping.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

/// Speaks with the chosen cloud voice and falls back to the device voice when
/// the gateway is not configured, slow or failing, so speech never goes
/// silent.
class CloudTtsPort implements TtsPort {
  CloudTtsPort({
    required this._client,
    required this._cache,
    required this._player,
    required this._device,
    required this._warmTexts,
  });

  /// Longest wait for an uncached sentence before using the device voice.
  static const fetchLimit = Duration(seconds: 4);

  final CloudTtsClient _client;
  final CloudTtsCache _cache;
  final CloudAudioPlayer _player;
  final PlaybackTtsPort _device;
  final List<String> Function() _warmTexts;

  TtsRate rate = TtsRate.normal;
  TtsVolume volume = TtsVolume.normal;
  CloudVoice _voice = CloudVoice.female;
  bool _warmed = false;
  bool _stopped = false;
  final _pending = <String, Future<File?>>{};

  bool get enabled => _client.isConfigured;

  CloudVoice get voice => _voice;

  /// Setting the voice, including the first time, prepares the quick
  /// phrases in that voice.
  set voice(CloudVoice value) {
    if (value == _voice && _warmed) return;
    _voice = value;
    _warmed = true;
    prefetch(_warmTexts());
  }

  @override
  Future<bool> isKoreanAvailable() async =>
      enabled || await _device.isKoreanAvailable();

  Future<Result<void>> speakCached(
    String text, {
    required void Function() onStarted,
    required void Function() onEnded,
  }) async {
    _stopped = false;
    File? file;
    try {
      file = await _cache.find(_voice.id, text);
    } on Object {
      file = null;
    }
    if (_stopped) return const FailureResult(TtsFailure('음성 재생이 중지되었습니다.'));
    if (file != null) {
      var started = false;
      var succeeded = false;
      try {
        await _player.play(
          file.path,
          speed: switch (rate) {
            TtsRate.slow => 0.85,
            TtsRate.normal => 1.0,
            TtsRate.fast => 1.15,
          },
          volume: TtsMapping.volume(volume),
          onStarted: () {
            if (_stopped || started) return;
            started = true;
            onStarted();
          },
        );
        succeeded = true;
      } on Object {
        // A cached file may be unreadable; use the device voice below.
      } finally {
        if (started) onEnded();
      }
      if (_stopped) return const FailureResult(TtsFailure('음성 재생이 중지되었습니다.'));
      if (succeeded) return const Success(null);
    }
    AppLog.tts('live device voice (no playable cache)');
    return _device.speakWithPlayback(
      text,
      onStarted: onStarted,
      onEnded: onEnded,
    );
  }

  @override
  Future<Result<void>> speak(String text) async {
    if (!enabled) {
      AppLog.tts('device voice (no gateway key) "$text"');
      return _device.speak(text);
    }
    _stopped = false;
    File? file;
    try {
      file = await _audioFor(text, _voice).timeout(fetchLimit);
    } on Object catch (error) {
      AppLog.tts('cloud unavailable (${error.runtimeType}), device voice');
      file = null;
    }
    if (_stopped) {
      return const FailureResult(TtsFailure('음성 재생이 중지되었습니다.'));
    }
    if (file == null) return _device.speak(text);
    AppLog.tts('cloud ${_voice.id} "$text"');
    try {
      await _player.play(
        file.path,
        speed: switch (rate) {
          TtsRate.slow => 0.85,
          TtsRate.normal => 1.0,
          TtsRate.fast => 1.15,
        },
        volume: TtsMapping.volume(volume),
      );
      return _stopped
          ? const FailureResult(TtsFailure('음성 재생이 중지되었습니다.'))
          : const Success(null);
    } on Object catch (error) {
      if (_stopped) {
        return const FailureResult(TtsFailure('음성 재생이 중지되었습니다.'));
      }
      AppLog.tts('cloud playback failed (${error.runtimeType}), device voice');
      return _device.speak(text);
    }
  }

  @override
  Future<Result<void>> stop() async {
    _stopped = true;
    try {
      await _player.stop();
    } on Object {
      // The device voice is stopped below either way.
    }
    return _device.stop();
  }

  /// Synthesizes sentences ahead of time so a later tap plays at once.
  void prefetch(Iterable<String> texts) {
    if (!enabled) return;
    final voice = _voice;
    unawaited(() async {
      for (final text in texts.toSet()) {
        try {
          await _audioFor(text, voice);
        } on Object {
          // Prefetch is best effort.
        }
      }
    }());
  }

  Future<File?> _audioFor(String text, CloudVoice voice) {
    final key = CloudTtsCache.keyFor(voice.id, text);
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = () async {
      try {
        final cached = await _cache.find(voice.id, text);
        if (cached != null) return cached;
        final started = DateTime.now();
        final audio = await _client.synthesize(text, voice);
        AppLog.tts(
          'synthesized ${voice.id} "$text" ${audio.length}B '
          '${DateTime.now().difference(started).inMilliseconds}ms',
        );
        return await _cache.save(voice.id, text, audio);
      } finally {
        // Removed after this turn so concurrent callers share the request.
        scheduleMicrotask(() => unawaited(_pending.remove(key)));
      }
    }();
    // Callers still see the error; only the shared copy is marked handled.
    return _pending[key] = future..ignore();
  }
}
