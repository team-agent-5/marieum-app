import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/signup_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements AuthRepository {}

void main() {
  group(SignupCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
      when(
        () => repository.signup(
          userId: any(named: 'userId'),
          password: any(named: 'password'),
          passwordConfirm: any(named: 'passwordConfirm'),
          nickname: any(named: 'nickname'),
        ),
      ).thenAnswer((_) async => const Success(null));
    });
    blocTest<SignupCubit, AuthFormState>(
      'starts with an initial form',
      build: () => SignupCubit(repository),
      verify: (cubit) => expect(cubit.state, const AuthFormState()),
    );
    blocTest<SignupCubit, AuthFormState>(
      'reports all invalid fields without contacting repository',
      build: () => SignupCubit(repository),
      act: (cubit) => cubit.submit(
        userId: 'bad!',
        password: 'short',
        passwordConfirm: 'other',
        nickname: ' ',
      ),
      expect: () => [
        isA<AuthFormState>().having(
          (s) => s.fieldErrors.keys.toSet(),
          'fields',
          {'user_id', 'password', 'password_confirm', 'nickname'},
        ),
      ],
      verify: (_) => verifyNever(
        () => repository.signup(
          userId: any(named: 'userId'),
          password: any(named: 'password'),
          passwordConfirm: any(named: 'passwordConfirm'),
          nickname: any(named: 'nickname'),
        ),
      ),
    );
    for (final id in ['abc', '김환자ab', 'abc-', 'abcdefghijklmnopqrstu']) {
      blocTest<SignupCubit, AuthFormState>(
        'rejects invalid ID $id',
        build: () => SignupCubit(repository),
        act: (cubit) => cubit.submit(
          userId: id,
          password: 'password',
          passwordConfirm: 'password',
          nickname: '환자',
        ),
        expect: () => [
          isA<AuthFormState>().having((s) => s.fieldErrors.keys, 'fields', [
            'user_id',
          ]),
        ],
      );
    }
    for (final id in ['abc_', 'Kim_01', 'abcdefghijklmnopqrst']) {
      blocTest<SignupCubit, AuthFormState>(
        'accepts ID boundary $id and a sixteen-character nickname',
        build: () => SignupCubit(repository),
        act: (cubit) => cubit.submit(
          userId: id,
          password: 'password',
          passwordConfirm: 'password',
          nickname: '가' * 16,
        ),
        expect: () => [
          const AuthFormState(status: AuthFormStatus.submitting),
          const AuthFormState(status: AuthFormStatus.success),
        ],
      );
    }
    blocTest<SignupCubit, AuthFormState>(
      'rejects nickname longer than sixteen characters',
      build: () => SignupCubit(repository),
      act: (cubit) => cubit.submit(
        userId: 'user_1',
        password: 'password',
        passwordConfirm: 'password',
        nickname: '가' * 17,
      ),
      expect: () => [
        isA<AuthFormState>().having((s) => s.fieldErrors.keys, 'fields', [
          'nickname',
        ]),
      ],
    );
    blocTest<SignupCubit, AuthFormState>(
      'submits password confirmation and trimmed nickname',
      build: () => SignupCubit(repository),
      act: (cubit) => cubit.submit(
        userId: ' user_1 ',
        password: 'password',
        passwordConfirm: 'password',
        nickname: ' 환자 ',
      ),
      expect: () => [
        const AuthFormState(status: AuthFormStatus.submitting),
        const AuthFormState(status: AuthFormStatus.success),
      ],
      verify: (_) => verify(
        () => repository.signup(
          userId: 'user_1',
          password: 'password',
          passwordConfirm: 'password',
          nickname: '환자',
        ),
      ).called(1),
    );
    for (final failure in <Failure>[
      const ConflictFailure(),
      const NetworkFailure(),
      const ValidationFailure(
        fieldErrors: {
          'password_confirm': ['mismatch'],
        },
      ),
    ]) {
      blocTest<SignupCubit, AuthFormState>(
        'maps ${failure.runtimeType} to form errors',
        setUp: () => when(
          () => repository.signup(
            userId: 'user_1',
            password: 'password',
            passwordConfirm: 'password',
            nickname: '환자',
          ),
        ).thenAnswer((_) async => FailureResult(failure)),
        build: () => SignupCubit(repository),
        act: (cubit) => cubit.submit(
          userId: 'user_1',
          password: 'password',
          passwordConfirm: 'password',
          nickname: '환자',
        ),
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
  });
}
