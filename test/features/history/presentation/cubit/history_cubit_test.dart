import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';
import 'package:marieum_app/features/history/domain/entities/history_range.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/domain/utils/history_date_range.dart';
import 'package:marieum_app/features/history/presentation/cubit/history_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements HistoryRepository {}

void main() {
  group(HistoryCubit, () {
    late _MockRepository repository;
    late HistoryEntry entry;
    setUp(() {
      repository = _MockRepository();
      entry = HistoryEntry(
        logId: '1',
        text: '물 주세요',
        source: 'voice',
        createdAt: DateTime(2026),
      );
    });
    blocTest<HistoryCubit, HistoryState>(
      'loads an empty page',
      build: () {
        when(() => repository.page(since: any(named: 'since'))).thenAnswer(
          (_) async => const Success(HistoryPageData(entries: [], total: 0)),
        );
        return HistoryCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const HistoryState(status: HistoryStatus.loading),
        const HistoryState(status: HistoryStatus.success),
      ],
    );
    blocTest<HistoryCubit, HistoryState>(
      'appends cursor page without duplicate IDs',
      build: () {
        when(() => repository.page(since: any(named: 'since'))).thenAnswer(
          (_) async => Success(
            HistoryPageData(entries: [entry], total: 1, nextCursor: 'next'),
          ),
        );
        when(
          () => repository.page(
            since: any(named: 'since'),
            cursor: 'next',
          ),
        ).thenAnswer(
          (_) async => Success(HistoryPageData(entries: [entry], total: 1)),
        );
        return HistoryCubit(repository);
      },
      act: (cubit) async {
        await cubit.load();
        await cubit.more();
      },
      expect: () => [
        isA<HistoryState>().having(
          (s) => s.status,
          'status',
          HistoryStatus.loading,
        ),
        isA<HistoryState>().having((s) => s.nextCursor, 'cursor', 'next'),
        isA<HistoryState>().having(
          (s) => s.entries.length,
          'retained entries',
          1,
        ),
        isA<HistoryState>().having(
          (s) => (s.entries.length, s.nextCursor),
          'final page',
          (1, null),
        ),
      ],
    );
    blocTest<HistoryCubit, HistoryState>(
      'reports network failure and permits retry',
      build: () {
        when(
          () => repository.page(since: any(named: 'since')),
        ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
        return HistoryCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const HistoryState(status: HistoryStatus.loading),
        isA<HistoryState>().having(
          (s) => s.failure,
          'failure',
          isA<NetworkFailure>(),
        ),
      ],
    );
    blocTest<HistoryCubit, HistoryState>(
      'ignores late results from the previous range',
      build: () => HistoryCubit(repository, now: () => DateTime(2026, 11)),
      act: (cubit) async {
        final pending = Completer<Result<HistoryPageData>>();
        when(
          () => repository.page(
            since: historySince(DateTime(2026, 11), HistoryRange.today),
          ),
        ).thenAnswer((_) => pending.future);
        when(
          () => repository.page(
            since: historySince(DateTime(2026, 11), HistoryRange.week),
          ),
        ).thenAnswer(
          (_) async => const Success(HistoryPageData(entries: [], total: 0)),
        );
        final first = cubit.load();
        await cubit.load(HistoryRange.week);
        pending.complete(Success(HistoryPageData(entries: [entry], total: 1)));
        await first;
      },
      expect: () => [
        const HistoryState(status: HistoryStatus.loading),
        const HistoryState(
          range: HistoryRange.week,
          status: HistoryStatus.loading,
        ),
        const HistoryState(
          range: HistoryRange.week,
          status: HistoryStatus.success,
        ),
      ],
    );
  });
}
