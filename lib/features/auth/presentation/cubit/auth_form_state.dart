import 'package:equatable/equatable.dart';
import 'package:marieum_app/core/error/failure.dart';

enum AuthFormStatus { initial, submitting, success, failure }

class AuthFormState extends Equatable {
  const AuthFormState({
    this.status = AuthFormStatus.initial,
    this.fieldErrors = const {},
    this.failure,
  });
  final AuthFormStatus status;
  final Map<String, String> fieldErrors;
  final Failure? failure;
  @override
  List<Object?> get props => [status, fieldErrors, failure];
}

abstract final class AuthFormValidation {
  static Map<String, String> credentials(String userId, String password) => {
    if (!RegExp(r'^[a-z0-9_]{4,20}$').hasMatch(userId))
      'user_id': '영문 소문자·숫자·밑줄 4~20자로 입력해 주세요',
    if (password.length < 8) 'password': '비밀번호는 8자 이상 입력해 주세요',
  };
  static Map<String, String> serverFields(Failure failure) => switch (failure) {
    ConflictFailure() => {'user_id': '이미 사용 중인 아이디예요'},
    UnauthorizedFailure() => {'password': '아이디 또는 비밀번호를 다시 확인해 주세요'},
    ValidationFailure(:final fieldErrors) => {
      for (final entry in fieldErrors.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.first,
    },
    _ => {},
  };
}
