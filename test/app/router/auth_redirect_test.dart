import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mocktail/mocktail.dart';
import '../../helpers/pump_app.dart';

class _MockBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _MockRepository extends Mock implements AuthRepository {}

const _newProfile = PatientProfile(
  id: '1',
  nickname: '환자',
  onboardingCompleted: false,
  userId: 'user_1',
);
void main() {
  group('Authentication redirects', () {
    const paths = [
      '/splash',
      '/login',
      '/signup',
      '/onboarding',
      '/onboarding?review=1',
      '/speak',
      '/history',
      '/account',
      '/unknown',
    ];
    for (final status in <AuthStatus>[
      const AuthUnknown(),
      const AuthUnauthenticated(),
      const AuthAuthenticated(_newProfile),
      const AuthAuthenticated(testProfile),
    ]) {
      final onboarded =
          status is AuthAuthenticated && status.profile.onboardingCompleted;
      for (final path in paths) {
        testWidgets(
          '${status.runtimeType} '
          'onboarded=$onboarded '
          'entering $path',
          (tester) async {
            final expected = switch (status) {
              AuthUnknown() => '/splash',
              AuthUnauthenticated() => path == '/signup' ? '/signup' : '/login',
              AuthAuthenticated(:final profile)
                  when !profile.onboardingCompleted =>
                '/onboarding',
              AuthAuthenticated() =>
                [
                      '/splash',
                      '/login',
                      '/signup',
                      '/onboarding',
                      '/unknown',
                    ].contains(path)
                    ? '/speak'
                    : path,
            };
            final router = await tester.pumpApp(
              initialLocation: path,
              status: status,
              settle: false,
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(router.state.uri.toString(), expected);
            await tester.pumpWidget(const SizedBox.shrink());
            router.dispose();
          },
        );
      }
    }
    testWidgets(
      'refreshes from AuthBloc and blocks back navigation after expiration',
      (tester) async {
        final bloc = _MockBloc();
        final changes = StreamController<AuthState>();
        whenListen(
          bloc,
          changes.stream,
          initialState: const AuthState(AuthAuthenticated(testProfile)),
        );
        final router = await tester.pumpApp(authBloc: bloc);
        addTearDown(() async {
          await changes.close();
          router.dispose();
        });
        unawaited(router.push<void>('/account'));
        await tester.pumpAndSettle();
        changes.add(const AuthState(AuthUnauthenticated()));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/login');
        if (router.canPop()) {
          router.pop();
          await tester.pumpAndSettle();
        }
        expect(router.state.uri.path, '/login');
      },
    );
    testWidgets('retries a failed restore from splash', (tester) async {
      final repository = _MockRepository();
      var calls = 0;
      when(repository.restore).thenAnswer((_) async {
        calls++;
        return const FailureResult(NetworkFailure());
      });
      final router = await tester.pumpApp(
        status: const AuthUnknown(),
        repository: repository,
        settle: false,
      );
      addTearDown(router.dispose);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('다시 시도'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
    });
    testWidgets(
      'onboarding completion calls repository but review returns without PATCH',
      (tester) async {
        final repository = _MockRepository();
        when(
          repository.markOnboarded,
        ).thenAnswer((_) async => const Success(null));
        final router = await tester.pumpApp(
          status: const AuthAuthenticated(_newProfile),
          repository: repository,
        );
        await tester.tap(find.text('완료'));
        await tester.pump();
        verify(repository.markOnboarded).called(1);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        final reviewRouter = await tester.pumpApp(repository: repository);
        addTearDown(reviewRouter.dispose);
        unawaited(reviewRouter.push<void>('/onboarding?review=1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('돌아가기'));
        await tester.pumpAndSettle();
        expect(reviewRouter.state.uri.path, '/speak');
        verifyNoMoreInteractions(repository);
      },
    );
  });
}
