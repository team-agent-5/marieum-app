import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements AuthRepository {}

void main() {
  group(AuthBloc, () {
    late _MockRepository repository;
    late StreamController<AuthStatus> changes;
    setUp(() {
      repository = _MockRepository();
      changes = StreamController<AuthStatus>.broadcast();
      when(() => repository.currentStatus).thenReturn(const AuthUnknown());
      when(() => repository.status).thenAnswer((_) => changes.stream);
      when(repository.logout).thenAnswer((_) async {
        changes.add(const AuthUnauthenticated());
        return const Success(null);
      });
    });
    tearDown(() => changes.close());
    blocTest<AuthBloc, AuthState>(
      'starts unknown without restoring or logging in',
      build: () => AuthBloc(repository),
      expect: () => <AuthState>[],
      verify: (bloc) {
        expect(bloc.state, const AuthState(AuthUnknown()));
        verifyNever(repository.restore);
      },
    );
    blocTest<AuthBloc, AuthState>(
      'forwards repository restore, login, profile update and expiration',
      build: () => AuthBloc(repository),
      act: (bloc) async {
        bloc.add(const AuthSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        changes
          ..add(const AuthUnknown(failure: NetworkFailure()))
          ..add(const AuthUnauthenticated())
          ..add(
            const AuthAuthenticated(
              PatientProfile(
                id: '1',
                nickname: '환자',
                onboardingCompleted: false,
                userId: 'user_1',
              ),
            ),
          )
          ..add(
            const AuthAuthenticated(
              PatientProfile(
                id: '1',
                nickname: '환자',
                onboardingCompleted: true,
                userId: 'user_1',
              ),
            ),
          )
          ..add(const AuthUnauthenticated());
      },
      expect: () => [
        isA<AuthState>().having((s) => s.status, 'status', isA<AuthUnknown>()),
        const AuthState(AuthUnauthenticated()),
        const AuthState(
          AuthAuthenticated(
            PatientProfile(
              id: '1',
              nickname: '환자',
              onboardingCompleted: false,
              userId: 'user_1',
            ),
          ),
        ),
        const AuthState(
          AuthAuthenticated(
            PatientProfile(
              id: '1',
              nickname: '환자',
              onboardingCompleted: true,
              userId: 'user_1',
            ),
          ),
        ),
        const AuthState(AuthUnauthenticated()),
      ],
    );
    blocTest<AuthBloc, AuthState>(
      'delegates logout and waits for repository status',
      build: () => AuthBloc(repository),
      act: (bloc) async {
        bloc.add(const AuthSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LogoutRequested());
      },
      expect: () => [const AuthState(AuthUnauthenticated())],
      verify: (_) => verify(repository.logout).called(1),
    );
    blocTest<AuthBloc, AuthState>(
      'replaces a duplicate subscription without duplicate emissions',
      build: () => AuthBloc(repository),
      act: (bloc) async {
        bloc.add(const AuthSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const AuthSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        changes.add(const AuthUnauthenticated());
      },
      expect: () => [const AuthState(AuthUnauthenticated())],
    );
  });
}
