import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';

class RestoreCubit extends Cubit<AuthFormState> {
  RestoreCubit(this._repository) : super(const AuthFormState());
  final AuthRepository _repository;
  Future<void> restore() async {
    if (state.status == AuthFormStatus.submitting) return;
    emit(const AuthFormState(status: AuthFormStatus.submitting));
    final result = await _repository.restore();
    if (isClosed) return;
    emit(switch (result) {
      Success() => const AuthFormState(status: AuthFormStatus.success),
      FailureResult(:final failure) => AuthFormState(
        status: AuthFormStatus.failure,
        failure: failure,
      ),
    });
  }
}

class OnboardingCubit extends Cubit<AuthFormState> {
  OnboardingCubit(this._repository) : super(const AuthFormState());
  final AuthRepository _repository;
  Future<void> complete() async {
    if (state.status == AuthFormStatus.submitting) return;
    emit(const AuthFormState(status: AuthFormStatus.submitting));
    final result = await _repository.markOnboarded();
    if (isClosed) return;
    emit(switch (result) {
      Success() => const AuthFormState(status: AuthFormStatus.success),
      FailureResult(:final failure) => AuthFormState(
        status: AuthFormStatus.failure,
        failure: failure,
      ),
    });
  }
}
