import 'dart:async';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/settings/data/datasources/settings_mirror.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';

class MockSettingsMirror implements SettingsMirror {
  @override
  Future<Result<void>> send(AppSettings settings) async => const Success(null);
}
