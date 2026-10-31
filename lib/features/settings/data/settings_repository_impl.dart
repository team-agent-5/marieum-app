import 'dart:async';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/settings/domain/app_settings.dart';

// 원격 구현과 모의 구현을 같은 인터페이스로 교체한다.
// ignore: one_member_abstracts
abstract interface class SettingsMirror {
  Future<Result<void>> send(AppSettings settings);
}

class RemoteSettingsMirror implements SettingsMirror {
  RemoteSettingsMirror(this._client);
  final ApiClient _client;
  @override
  Future<Result<void>> send(AppSettings settings) => _client.request(
    '/patient/preferences',
    method: 'PATCH',
    data: settingsPayload(settings),
    decode: (_) {},
  );
}

class MockSettingsMirror implements SettingsMirror {
  @override
  Future<Result<void>> send(AppSettings settings) async => const Success(null);
}

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({
    required this.prefs,
    required this.mirror,
    required this.applyVoice,
  }) : initial = AppSettings(
         rate:
             TtsRate.values
                 .where((v) => v.name == prefs.readString(PrefsKeys.ttsRate))
                 .firstOrNull ??
             TtsRate.normal,
         volume:
             TtsVolume.values
                 .where((v) => v.name == prefs.readString(PrefsKeys.ttsVolume))
                 .firstOrNull ??
             TtsVolume.normal,
         largeText: prefs.readBool(PrefsKeys.largeText) ?? false,
       ) {
    applyVoice(initial);
  }
  final PrefsStore prefs;
  final SettingsMirror mirror;
  final void Function(AppSettings) applyVoice;
  @override
  final AppSettings initial;
  Future<void> _writes = Future.value();
  Future<void> _mirrors = Future.value();
  @override
  Future<Result<void>> save(AppSettings settings) {
    applyVoice(settings);
    final result = _writes.then((_) async {
      Failure? failure;
      try {
        await prefs.writeString(PrefsKeys.ttsRate, settings.rate.name);
        await prefs.writeString(PrefsKeys.ttsVolume, settings.volume.name);
        await prefs.writeBool(PrefsKeys.largeText, value: settings.largeText);
      } on Object catch (error) {
        failure = error is Failure ? error : StorageFailure(cause: error);
      }
      _mirrors = _mirrors.then((_) async {
        try {
          await mirror.send(settings);
        } on Object {
          /* A mirror never changes local settings. */
        }
      });
      unawaited(_mirrors);
      return failure == null
          ? const Success<void>(null)
          : FailureResult<void>(failure);
    });
    _writes = result.then((_) {});
    return result;
  }
}

Map<String, Object> settingsPayload(AppSettings settings) => {
  'tts_rate': settings.rate.name,
  'tts_volume': switch (settings.volume) {
    TtsVolume.soft => 'low',
    TtsVolume.normal => 'normal',
    TtsVolume.loud => 'high',
  },
  'large_text': settings.largeText,
};
