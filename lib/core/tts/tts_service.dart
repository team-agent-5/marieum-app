import 'dart:async';

import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/tts_engine.dart';
import 'package:marieum_app/core/tts/tts_mapping.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:marieum_app/core/tts/tts_voice_selector.dart';

class TtsService implements TtsPort, TtsVoiceSelector {
  TtsService({
    required this._engine,
    required this._audioSession,
    required this._platform,
  });

  final TtsEngine _engine;
  final VoiceAudioSession _audioSession;
  final VoicePlatform _platform;
  TtsRate rate = TtsRate.normal;
  TtsVolume volume = TtsVolume.normal;
  Completer<Result<void>>? _active;
  bool _disposed = false;
  bool _stopping = false;
  Future<Result<void>>? _stopOperation;
  bool _koreanAvailable = false;
  Future<bool>? _availabilityCheck;
  List<TtsVoice>? _voices;
  Future<List<TtsVoice>>? _voicesCheck;
  String? _voiceId;
  @override
  TtsVoice? get currentVoice => _currentVoice;
  TtsVoice? _currentVoice;

  @override
  Future<List<TtsVoice>> availableVoices() => _voicesCheck ??= _loadVoices();

  Future<List<TtsVoice>> _loadVoices() async {
    try {
      _voices = List.unmodifiable(await _engine.koreanVoices());
    } on Object {
      _voices = const [];
    }
    _chooseVoice();
    return _voices!;
  }

  void _chooseVoice() {
    final voices = _voices;
    if (voices == null) return;
    final preferred = voices.where((voice) => voice.id == _voiceId).firstOrNull;
    if (preferred != null) {
      _currentVoice = preferred;
      return;
    }
    TtsVoice? best;
    for (final voice in voices) {
      final candidate = best;
      if (candidate == null ||
          (candidate.requiresNetwork && !voice.requiresNetwork) ||
          (candidate.requiresNetwork == voice.requiresNetwork &&
              voice.quality.index < candidate.quality.index)) {
        best = voice;
      }
    }
    _currentVoice = best;
  }

  @override
  Future<void> selectVoice(String? id) async {
    if (_voiceId == id) return;
    _voiceId = id;
    _chooseVoice();
  }

  @override
  Future<bool> isKoreanAvailable() {
    if (_koreanAvailable) return Future.value(true);
    return _availabilityCheck ??=
        Future<bool>.sync(
              () => _engine.isLanguageAvailable('ko-KR'),
            )
            .then((available) {
              _koreanAvailable = available;
              return available;
            })
            .whenComplete(() => _availabilityCheck = null);
  }

  @override
  Future<Result<void>> speak(String text) async {
    if (_disposed || _stopping || _active != null) {
      return const FailureResult(TtsFailure('음성 서비스가 준비되지 않았습니다.'));
    }
    final active = Completer<Result<void>>();
    _active = active;
    unawaited(_speak(text, active));
    return active.future;
  }

  Future<void> _speak(String text, Completer<Result<void>> active) async {
    try {
      if (!await isKoreanAvailable()) throw const TtsUnavailableFailure();
      if (active.isCompleted) return;
      await availableVoices();
      if (active.isCompleted) return;
      final voice = currentVoice;
      await _engine.configure(
        rate: TtsMapping.rate(_platform, rate),
        volume: TtsMapping.volume(volume),
      );
      if (active.isCompleted) return;
      if (voice != null) {
        try {
          await _engine.setVoice(voice);
        } on Object {
          // configure has already selected the default Korean voice.
        }
      }
      if (active.isCompleted) return;
      // Apply last, after flutter_tts has configured its shared iOS session.
      await _audioSession.configure();
      if (active.isCompleted) return;
      AppLog.tts('device ${voice?.name ?? 'default'} "$text"');
      await _engine.speak(text);
      if (!active.isCompleted) active.complete(const Success<void>(null));
    } on Object catch (error) {
      AppLog.tts('device voice failed $error');
      if (!active.isCompleted) {
        _koreanAvailable = false;
        active.complete(
          FailureResult(
            error is Failure ? error : TtsFailure(error.toString()),
          ),
        );
      }
    } finally {
      if (identical(_active, active)) _active = null;
    }
  }

  @override
  Future<Result<void>> stop() => _stopOperation ??= _stop();

  Future<Result<void>> _stop() async {
    _stopping = true;
    final active = _active;
    if (active != null && !active.isCompleted) {
      active.complete(const FailureResult(TtsFailure('음성 재생이 중지되었습니다.')));
    }
    try {
      await _engine.stop();
      return const Success(null);
    } on Object catch (error) {
      return FailureResult(TtsFailure(error.toString()));
    } finally {
      if (active != null && !active.isCompleted) {
        active.complete(const FailureResult(TtsFailure('음성 재생이 중지되었습니다.')));
      }
      if (identical(_active, active)) _active = null;
      _stopping = false;
      _stopOperation = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}
