import 'dart:async';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';

// 원격 구현과 모의 구현을 같은 인터페이스로 교체한다.
// ignore: one_member_abstracts
abstract interface class SettingsMirror {
  Future<Result<void>> send(AppSettings settings);
}
