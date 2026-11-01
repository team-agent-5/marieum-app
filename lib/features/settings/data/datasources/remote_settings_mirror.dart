import 'dart:async';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/settings/data/datasources/settings_mirror.dart';
import 'package:marieum_app/features/settings/data/dto/settings_payload.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';

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
