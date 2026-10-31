import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';

class SignupCubit extends Cubit<AuthFormState> {
  SignupCubit(this._repository) : super(const AuthFormState());
  final AuthRepository _repository;
  Future<void> submit({
    required String userId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  }) async {
    if (state.status == AuthFormStatus.submitting) return;
    final id = userId.trim();
    final name = nickname.trim();
    final errors = AuthFormValidation.credentials(id, password);
    if (passwordConfirm != password) {
      errors['password_confirm'] = '비밀번호가 일치하지 않아요';
    }
    if (name.isEmpty || name.runes.length > 16) {
      errors['nickname'] = '닉네임은 1~16자로 입력해 주세요';
    }
    if (errors.isNotEmpty) {
      emit(AuthFormState(status: AuthFormStatus.failure, fieldErrors: errors));
      return;
    }
    emit(const AuthFormState(status: AuthFormStatus.submitting));
    final result = await _repository.signup(
      userId: id,
      password: password,
      passwordConfirm: passwordConfirm,
      nickname: name,
    );
    if (isClosed) return;
    switch (result) {
      case Success():
        emit(const AuthFormState(status: AuthFormStatus.success));
      case FailureResult(:final failure):
        emit(
          AuthFormState(
            status: AuthFormStatus.failure,
            fieldErrors: AuthFormValidation.serverFields(failure),
            failure: failure,
          ),
        );
    }
  }
}
