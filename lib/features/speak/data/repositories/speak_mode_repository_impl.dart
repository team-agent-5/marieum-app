import 'dart:async';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/features/speak/data/datasources/speak_preferences_data_source.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/repositories/speak_mode_repository.dart';

class SpeakModeRepositoryImpl implements SpeakModeRepository {
  SpeakModeRepositoryImpl({required this._prefs, required this._source})
    : initialMode = _prefs.readString(PrefsKeys.speakMode) == 'live'
          ? SpeakMode.live
          : SpeakMode.precise;
  final PrefsStore _prefs;
  final SpeakPreferencesDataSource _source;
  @override
  final SpeakMode initialMode;
  Future<void> _writes = Future.value();
  Future<void> _mirrors = Future.value();
  @override
  Future<Result<void>> save(SpeakMode mode) {
    final result = _writes.then((_) async {
      Failure? failure;
      try {
        await _prefs.writeString(PrefsKeys.speakMode, mode.name);
      } on Object catch (error) {
        failure = error is Failure ? error : StorageFailure(cause: error);
      }
      // Ordered mirrors never hold up local persistence or the UI.
      _mirrors = _mirrors.then((_) async {
        try {
          await _source.mirrorMode(mode);
        } on Object {
          /* Best effort mirror. */
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
