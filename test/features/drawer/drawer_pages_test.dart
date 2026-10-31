import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/auth/presentation/pages/account_page.dart';
import 'package:marieum_app/features/privacy/presentation/pages/privacy_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/pump_app.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

void main() {
  group(AccountPage, () {
    testWidgets(
      'shows nickname and prefs ID with disabled edits and active logout',
      (tester) async {
        final bloc = _MockAuthBloc();
        when(
          () => bloc.state,
        ).thenReturn(const AuthState(AuthAuthenticated(testProfile)));
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        final router = await tester.pumpApp(
          initialLocation: '/account',
          authBloc: bloc,
          loginUserId: 'saved_login',
        );
        addTearDown(router.dispose);
        expect(find.text('김환자'), findsOneWidget);
        expect(find.text('saved_login'), findsOneWidget);
        expect(find.text('365일'), findsOneWidget);
        expect(find.text('준비 중'), findsNothing);
        expect(find.text('비밀번호'), findsNothing);
        await tester.ensureVisible(find.text('로그아웃'));
        await tester.tap(find.text('로그아웃'));
        await tester.pump();
        verify(() => bloc.add(const LogoutRequested())).called(1);
      },
    );
  });
  group(PrivacyPage, () {
    testWidgets('shows only what the app can do today', (tester) async {
      final router = await tester.pumpApp(initialLocation: '/privacy');
      addTearDown(router.dispose);
      expect(find.text('음성 원본은 저장하지 않아요'), findsOneWidget);
      expect(find.text('다른 사람의 데이터와 섞이지 않아요.'), findsOneWidget);
      expect(find.text('계정과 데이터 삭제'), findsNothing);
      expect(find.text('준비 중'), findsNothing);
    });
  });
  group('drawer logout', () {
    testWidgets('dispatches the existing logout event', (tester) async {
      final bloc = _MockAuthBloc();
      when(
        () => bloc.state,
      ).thenReturn(const AuthState(AuthAuthenticated(testProfile)));
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
      final router = await tester.pumpApp(authBloc: bloc);
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('로그아웃'),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('app_drawer_scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      verify(() => bloc.add(const LogoutRequested())).called(1);
    });
  });
}
