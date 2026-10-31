import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';

class LoginCubit extends Cubit<AuthFormState> {
  LoginCubit(this._repository) : super(const AuthFormState());
  final AuthRepository _repository;
  Future<void> submit({
    required String userId,
    required String password,
  }) async {
    if (state.status == AuthFormStatus.submitting) return;
    final id = userId.trim();
    final errors = AuthFormValidation.credentials(id, password);
    if (errors.isNotEmpty) {
      emit(AuthFormState(status: AuthFormStatus.failure, fieldErrors: errors));
      return;
    }
    emit(const AuthFormState(status: AuthFormStatus.submitting));
    final result = await _repository.login(userId: id, password: password);
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
