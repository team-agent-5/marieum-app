import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';

abstract interface class SettingsRepository {
  AppSettings get initial;
  Future<Result<void>> save(AppSettings settings);
}
