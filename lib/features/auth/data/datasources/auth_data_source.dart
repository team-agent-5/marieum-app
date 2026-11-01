import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';

abstract interface class AuthDataSource {
  Future<Result<AuthSessionDto>> login({
    required String userId,
    required String password,
  });
  Future<Result<AuthSessionDto>> signup({
    required String userId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  });
  Future<Result<PatientProfile>> profile({
    required String userId,
    required String token,
  });
  Future<Result<void>> logout();
  Future<Result<void>> markOnboarded(PatientProfile profile);
}
