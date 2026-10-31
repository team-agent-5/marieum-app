import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/pages/onboarding_page.dart';
import 'package:mocktail/mocktail.dart';
import '../../../../helpers/pump_app.dart';

class _MockRepository extends Mock implements AuthRepository {}

const _fresh = AuthAuthenticated(
  PatientProfile(
    id: '2',
    nickname: '환자',
    onboardingCompleted: false,
    userId: 'demo_b',
  ),
);
void main() {
  group(OnboardingPage, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
      when(
        repository.markOnboarded,
      ).thenAnswer((_) async => const Success(null));
    });
    testWidgets('moves through three steps and saves only after completion', (
      tester,
    ) async {
      final router = await tester.pumpApp(
        status: _fresh,
        repository: repository,
      );
      addTearDown(router.dispose);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('말하기 버튼을 누르고 말씀하세요'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      verifyNever(repository.markOnboarded);
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();
      verify(repository.markOnboarded).called(1);
    });
    testWidgets('swipes between steps', (tester) async {
      final router = await tester.pumpApp(
        status: _fresh,
        repository: repository,
      );
      addTearDown(router.dispose);
      final pages = find.byKey(const ValueKey('onboarding_pages'));
      await tester.fling(pages, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      await tester.fling(pages, const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });
    testWidgets('skip saves onboarding and offers retry on failure', (
      tester,
    ) async {
      when(
        repository.markOnboarded,
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final router = await tester.pumpApp(
        status: _fresh,
        repository: repository,
      );
      addTearDown(router.dispose);
      await tester.tap(find.text('건너뛰기'));
      await tester.pumpAndSettle();
      expect(find.text('서버에 연결할 수 없습니다.'), findsOneWidget);
      when(
        repository.markOnboarded,
      ).thenAnswer((_) async => const Success(null));
      await tester.tap(find.text('건너뛰기'));
      await tester.pumpAndSettle();
      verify(repository.markOnboarded).called(2);
    });
    testWidgets('review completion never saves onboarding', (tester) async {
      final router = await tester.pumpApp(
        initialLocation: '/onboarding?review=1',
        repository: repository,
      );
      addTearDown(router.dispose);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('돌아가기'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/speak');
      verifyNever(repository.markOnboarded);
    });
  });
}
