import 'dart:convert';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';

class MockAuthDataSource implements AuthDataSource {
  MockAuthDataSource(this._prefs);
  final PrefsStore _prefs;
  String _key(String userId) => 'mock_profile_$userId';
  PatientProfile _profile(String userId) {
    final saved = _prefs.readString(_key(userId));
    return saved == null
        ? PatientProfile(
            id: 'mock-$userId',
            nickname: userId == 'demo_a' ? '김환자' : userId,
            onboardingCompleted: userId == 'demo_a',
            userId: userId,
          )
        : AuthSessionDto.parseProfile(jsonDecode(saved), userId: userId);
  }

  Future<void> _save(PatientProfile profile) => _prefs.writeString(
    _key(profile.userId),
    jsonEncode({
      'id': profile.id,
      'nickname': profile.nickname,
      'onboarding_completed': profile.onboardingCompleted,
    }),
  );
  @override
  Future<Result<AuthSessionDto>> login({
    required String userId,
    required String password,
  }) async => Success(
    AuthSessionDto(
      accessToken: 'mock-session:$userId',
      profile: _profile(userId),
    ),
  );
  @override
  Future<Result<AuthSessionDto>> signup({
    required String userId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  }) async {
    final profile = PatientProfile(
      id: 'mock-$userId',
      nickname: nickname,
      onboardingCompleted: userId == 'demo_a',
      userId: userId,
    );
    await _save(profile);
    return Success(
      AuthSessionDto(accessToken: 'mock-session:$userId', profile: profile),
    );
  }

  @override
  Future<Result<PatientProfile>> profile({
    required String userId,
    required String token,
  }) async => token == 'mock-session:$userId'
      ? Success(_profile(userId))
      : const FailureResult(UnauthorizedFailure());
  @override
  Future<Result<void>> logout() async => const Success(null);
  @override
  Future<Result<void>> markOnboarded(PatientProfile profile) async {
    await _save(profile.onboarded());
    return const Success(null);
  }
}
