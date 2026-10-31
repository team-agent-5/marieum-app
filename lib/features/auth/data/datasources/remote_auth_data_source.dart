import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';

class RemoteAuthDataSource implements AuthDataSource {
  RemoteAuthDataSource(this._client);
  final ApiClient _client;
  @override
  Future<Result<AuthSessionDto>> login({
    required String userId,
    required String password,
  }) => _client.request(
    '/auth/login',
    method: 'POST',
    authenticated: false,
    data: {'user_id': userId, 'password': password},
    decode: (json) => AuthSessionDto.fromJson(json, userId: userId),
  );
  @override
  Future<Result<AuthSessionDto>> signup({
    required String userId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  }) => _client.request(
    '/auth/signup',
    method: 'POST',
    authenticated: false,
    data: {
      'user_id': userId,
      'password': password,
      'password_confirm': passwordConfirm,
      'nickname': nickname,
    },
    decode: (json) => AuthSessionDto.fromJson(json, userId: userId),
  );
  @override
  Future<Result<PatientProfile>> profile({
    required String userId,
    required String token,
  }) => _client.request(
    '/patient/me',
    decode: (json) => AuthSessionDto.parseProfile(json, userId: userId),
  );
  @override
  Future<Result<void>> logout() =>
      _client.request('/auth/logout', method: 'POST', decode: (_) {});
  @override
  Future<Result<void>> markOnboarded(PatientProfile profile) => _client.request(
    '/patient/preferences',
    method: 'PATCH',
    data: {'onboarding_completed': true},
    decode: (json) {
      final body = json! as Map<String, Object?>;
      if (body['onboarding_completed'] != true) {
        throw const FormatException('Onboarding was not saved.');
      }
    },
  );
}
