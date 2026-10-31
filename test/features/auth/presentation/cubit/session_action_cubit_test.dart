import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/session_action_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements AuthRepository {}

void main() {
  group(RestoreCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
    });
    for (final result in <Result<void>>[
      const Success(null),
      const FailureResult(NetworkFailure()),
    ]) {
      blocTest<RestoreCubit, AuthFormState>(
        'reports ${result.runtimeType} and permits retry',
        setUp: () => when(repository.restore).thenAnswer((_) async => result),
        build: () => RestoreCubit(repository),
        act: (cubit) => cubit.restore(),
        expect: () => [
          const AuthFormState(status: AuthFormStatus.submitting),
          if (result is FailureResult<void>)
            AuthFormState(
              status: AuthFormStatus.failure,
              failure: result.failure,
            )
          else
            const AuthFormState(status: AuthFormStatus.success),
        ],
      );
    }
  });
  group(OnboardingCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
    });
    for (final result in <Result<void>>[
      const Success(null),
      const FailureResult(NetworkFailure()),
    ]) {
      blocTest<OnboardingCubit, AuthFormState>(
        'reports completion ${result.runtimeType}',
        setUp: () =>
            when(repository.markOnboarded).thenAnswer((_) async => result),
        build: () => OnboardingCubit(repository),
        act: (cubit) => cubit.complete(),
        expect: () => [
          const AuthFormState(status: AuthFormStatus.submitting),
          if (result is FailureResult<void>)
            AuthFormState(
              status: AuthFormStatus.failure,
              failure: result.failure,
            )
          else
            const AuthFormState(status: AuthFormStatus.success),
        ],
      );
    }
  });
}
