import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';

abstract interface class SpeakModeRepository {
  SpeakMode get initialMode;
  Future<Result<void>> save(SpeakMode mode);
}
