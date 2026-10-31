import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements AuthRepository {}

void main() {
  group(LoginCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
      when(
        () => repository.login(
          userId: any(named: 'userId'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => const Success(null));
    });
    blocTest<LoginCubit, AuthFormState>(
      'starts with an initial form',
      build: () => LoginCubit(repository),
      verify: (cubit) => expect(cubit.state, const AuthFormState()),
    );
    blocTest<LoginCubit, AuthFormState>(
      'requires both fields before any request',
      build: () => LoginCubit(repository),
      act: (cubit) => cubit.submit(userId: '  ', password: ''),
      expect: () => [
        isA<AuthFormState>().having(
          (s) => s.fieldErrors.keys.toSet(),
          'fields',
          {'user_id', 'password'},
        ),
      ],
      verify: (_) => verifyNever(
        () => repository.login(
          userId: any(named: 'userId'),
          password: any(named: 'password'),
        ),
      ),
    );
    blocTest<LoginCubit, AuthFormState>(
      'emits submitting then success and trims only user ID',
      build: () => LoginCubit(repository),
      act: (cubit) => cubit.submit(userId: ' user_1 ', password: 'password '),
      expect: () => [
        const AuthFormState(status: AuthFormStatus.submitting),
        const AuthFormState(status: AuthFormStatus.success),
      ],
      verify: (_) => verify(
        () => repository.login(userId: 'user_1', password: 'password '),
      ).called(1),
    );
    for (final failure in <Failure>[
      const UnauthorizedFailure(),
      const NetworkFailure(),
      const ValidationFailure(
        fieldErrors: {
          'user_id': ['invalid'],
        },
      ),
    ]) {
      blocTest<LoginCubit, AuthFormState>(
        'emits a recoverable form failure for ${failure.runtimeType}',
        setUp: () => when(
          () => repository.login(userId: 'user_1', password: 'password'),
        ).thenAnswer((_) async => FailureResult(failure)),
        build: () => LoginCubit(repository),
        act: (cubit) => cubit.submit(userId: 'user_1', password: 'password'),
        expect: () => [
          const AuthFormState(status: AuthFormStatus.submitting),
          AuthFormState(
            status: AuthFormStatus.failure,
            failure: failure,
            fieldErrors: AuthFormValidation.serverFields(failure),
          ),
        ],
      );
    }
    blocTest<LoginCubit, AuthFormState>(
      'ignores duplicate submissions while one request is pending',
      build: () => LoginCubit(repository),
      act: (cubit) async {
        final pending = Completer<Result<void>>();
        when(
          () => repository.login(userId: 'user_1', password: 'password'),
        ).thenAnswer((_) => pending.future);
        final first = cubit.submit(userId: 'user_1', password: 'password');
        await cubit.submit(userId: 'user_1', password: 'password');
        pending.complete(const Success(null));
        await first;
      },
      expect: () => [
        const AuthFormState(status: AuthFormStatus.submitting),
        const AuthFormState(status: AuthFormStatus.success),
      ],
      verify: (_) => verify(
        () => repository.login(userId: 'user_1', password: 'password'),
      ).called(1),
    );
  });
}
