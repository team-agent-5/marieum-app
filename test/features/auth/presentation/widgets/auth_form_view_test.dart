import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/widgets/auth_form_view.dart';
import 'package:mocktail/mocktail.dart';
import '../../../../helpers/pump_app.dart';

class _MockRepository extends Mock implements AuthRepository {}

void main() {
  group(AuthFormView, () {
    testWidgets('shows login failure inline and retains entered credentials', (
      tester,
    ) async {
      final repository = _MockRepository();
      when(
        () => repository.login(userId: 'user_1', password: 'password'),
      ).thenAnswer((_) async => const FailureResult(UnauthorizedFailure()));
      final router = await tester.pumpApp(
        status: const AuthUnauthenticated(),
        repository: repository,
      );
      addTearDown(router.dispose);
      await tester.enterText(
        find.byKey(const ValueKey('auth_user_id')),
        'user_1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth_password')),
        'password',
      );
      await tester.tap(find.byKey(const ValueKey('auth_submit')));
      await tester.pumpAndSettle();
      expect(find.text('아이디 또는 비밀번호를 다시 확인해 주세요'), findsOneWidget);
      expect(router.state.uri.path, '/login');
      expect(find.text('user_1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'shows loading variant and prevents duplicate signup submissions',
      (tester) async {
        final repository = _MockRepository();
        final pending = Completer<Result<void>>();
        when(
          () => repository.signup(
            userId: 'user_1',
            password: 'password',
            passwordConfirm: 'password',
            nickname: '환자',
          ),
        ).thenAnswer((_) => pending.future);
        final router = await tester.pumpApp(
          initialLocation: '/signup',
          status: const AuthUnauthenticated(),
          repository: repository,
        );
        addTearDown(router.dispose);
        for (final entry in {
          'nickname': '환자',
          'user_id': 'user_1',
          'password': 'password',
          'password_confirm': 'password',
        }.entries) {
          await tester.enterText(
            find.byKey(ValueKey('auth_${entry.key}')),
            entry.value,
          );
        }
        await tester.ensureVisible(find.byKey(const ValueKey('auth_submit')));
        await tester.tap(find.byKey(const ValueKey('auth_submit')));
        await tester.pump();
        expect(find.text('계정을 만들고 있어요'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        pending.complete(const FailureResult(ConflictFailure()));
        await tester.pumpAndSettle();
        expect(find.text('이미 사용 중인 아이디예요'), findsOneWidget);
        expect(find.text('환자'), findsOneWidget);
        verify(
          () => repository.signup(
            userId: 'user_1',
            password: 'password',
            passwordConfirm: 'password',
            nickname: '환자',
          ),
        ).called(1);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
