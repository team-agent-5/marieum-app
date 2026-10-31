import 'dart:async';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/settings/data/datasources/settings_mirror.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/domain/repositories/settings_repository.dart';

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
         voiceId: prefs.readString(PrefsKeys.ttsVoiceId),
         cloudVoice:
             CloudVoice.values
                 .where((v) => v.name == prefs.readString(PrefsKeys.cloudVoice))
                 .firstOrNull ??
             CloudVoice.female,
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
        await prefs.writeString(PrefsKeys.cloudVoice, settings.cloudVoice.name);
        final voiceId = settings.voiceId;
        if (voiceId == null) {
          await prefs.remove(PrefsKeys.ttsVoiceId);
        } else {
          await prefs.writeString(PrefsKeys.ttsVoiceId, voiceId);
        }
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
