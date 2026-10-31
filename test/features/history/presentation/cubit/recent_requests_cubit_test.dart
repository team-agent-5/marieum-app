import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/presentation/cubit/recent_requests_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockHistory extends Mock implements HistoryRepository {}

void main() {
  group(RecentRequestsCubit, () {
    late _MockHistory repository;
    setUp(() {
      repository = _MockHistory();
    });
    blocTest<RecentRequestsCubit, RecentRequestsState>(
      'loads recent records',
      build: () {
        when(repository.recent).thenAnswer((_) async => const Success([]));
        return RecentRequestsCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const RecentRequestsState(loading: true),
        const RecentRequestsState(),
      ],
    );
    blocTest<RecentRequestsCubit, RecentRequestsState>(
      'exposes an error for retry',
      build: () {
        when(
          repository.recent,
        ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
        return RecentRequestsCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const RecentRequestsState(loading: true),
        isA<RecentRequestsState>().having(
          (s) => s.failure,
          'failure',
          isA<NetworkFailure>(),
        ),
      ],
    );
  });
}
