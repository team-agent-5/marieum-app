import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';

abstract interface class AuthRepository {
  AuthStatus get currentStatus;
  Stream<AuthStatus> get status;
  Future<Result<void>> restore();
  Future<Result<void>> login({
    required String userId,
    required String password,
  });
  Future<Result<void>> signup({
    required String userId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  });
  Future<Result<void>> logout();
  Future<Result<void>> expireSession();
  Future<Result<void>> markOnboarded();
  Future<void> dispose();
}
