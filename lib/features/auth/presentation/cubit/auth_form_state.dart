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
  static final _userIdPattern = RegExp(r'^[A-Za-z0-9_]{4,20}$');

  static Map<String, String> credentials(String userId, String password) => {
    if (!_userIdPattern.hasMatch(userId)) 'user_id': '영문·숫자·밑줄 4~20자로 입력해 주세요',
    if (password.length < 8) 'password': '비밀번호는 8자 이상 입력해 주세요',
  };

  static Map<String, String> login(String userId, String password) => {
    if (userId.isEmpty) 'user_id': '아이디를 입력해 주세요',
    if (password.isEmpty) 'password': '비밀번호를 입력해 주세요',
  };
  static const _fieldMessages = {
    'user_id': '영문·숫자·밑줄 4~20자로 입력해 주세요',
    'password': '비밀번호는 8자 이상 입력해 주세요',
    'password_confirm': '비밀번호가 일치하지 않아요',
    'nickname': '닉네임은 1~16자로 입력해 주세요',
  };

  static Map<String, String> serverFields(Failure failure) => switch (failure) {
    ConflictFailure() => {'user_id': '이미 사용 중인 아이디예요'},
    // Highlight both fields without revealing which one was wrong.
    UnauthorizedFailure() => {
      'user_id': '',
      'password': '아이디 또는 비밀번호를 다시 확인해 주세요',
    },
    // Server issue strings are codes (e.g. "password_confirm_mismatch"),
    // so each field gets fixed Korean wording instead.
    ValidationFailure(:final fieldErrors) => {
      for (final field in fieldErrors.keys) field: ?_fieldMessages[field],
    },
    _ => {},
  };
}
