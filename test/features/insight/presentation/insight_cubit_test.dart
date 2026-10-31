import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/history.dart';
import 'package:marieum_app/features/insight/presentation/insight_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements HistoryRepository {}

void main() {
  group(InsightCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
    });
    blocTest<InsightCubit, InsightState>(
      'loads all pages using seven-days-ago midnight',
      build: () {
        when(
          () => repository.all(since: any(named: 'since')),
        ).thenAnswer((_) async => const Success([]));
        return InsightCubit(repository, now: () => DateTime(2026, 11));
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const InsightState(status: InsightStatus.loading),
        isA<InsightState>().having(
          (s) => s.summary!.learning,
          'learning',
          isTrue,
        ),
      ],
      verify: (_) => verify(
        () => repository.all(
          since: localMidnightIso(DateTime(2026, 11), daysAgo: 7),
        ),
      ).called(1),
    );
    blocTest<InsightCubit, InsightState>(
      'reports history errors without fabricated statistics',
      build: () {
        when(
          () => repository.all(since: any(named: 'since')),
        ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
        return InsightCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const InsightState(status: InsightStatus.loading),
        isA<InsightState>().having(
          (s) => (s.status, s.summary, s.failure.runtimeType),
          'failure',
          (InsightStatus.failure, null, NetworkFailure),
        ),
      ],
    );
  });
}
