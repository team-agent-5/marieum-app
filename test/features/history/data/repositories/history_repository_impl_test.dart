import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/data/datasources/history_data_source.dart';
import 'package:marieum_app/features/history/data/repositories/history_repository_impl.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';
import 'package:mocktail/mocktail.dart';

class _MockSource extends Mock implements HistoryDataSource {}

void main() {
  group(HistoryRepositoryImpl, () {
    late _MockSource source;
    setUp(() {
      source = _MockSource();
    });
    test('follows all cursors and deduplicates repeated log IDs', () async {
      final entry = HistoryEntry(
        logId: '1',
        text: '물 주세요',
        source: 'voice',
        createdAt: DateTime(2026),
      );
      when(() => source.page(since: 'since')).thenAnswer(
        (_) async => Success(
          HistoryPageData(entries: [entry], total: 1, nextCursor: 'next'),
        ),
      );
      when(() => source.page(since: 'since', cursor: 'next')).thenAnswer(
        (_) async => Success(HistoryPageData(entries: [entry], total: 1)),
      );
      final result =
          await HistoryRepositoryImpl(source).all(since: 'since')
              as Success<List<HistoryEntry>>;
      expect(result.value, [entry]);
      verify(() => source.page(since: 'since', cursor: 'next')).called(1);
    });
    test('reports repeated cursors instead of looping indefinitely', () async {
      const data = Success(
        HistoryPageData(entries: [], total: 1, nextCursor: 'next'),
      );
      when(() => source.page(since: 'since')).thenAnswer((_) async => data);
      when(
        () => source.page(since: 'since', cursor: 'next'),
      ).thenAnswer((_) async => data);
      final result =
          await HistoryRepositoryImpl(source).all(since: 'since')
              as FailureResult<List<HistoryEntry>>;
      expect(result.failure, isA<ProtocolFailure>());
    });
    test('takes only the latest three records without a time filter', () async {
      final entries = List.generate(
        4,
        (i) => HistoryEntry(
          logId: '$i',
          text: '문장 $i',
          source: 'preset',
          createdAt: DateTime(2026),
        ),
      );
      when(() => source.page(since: null)).thenAnswer(
        (_) async => Success(HistoryPageData(entries: entries, total: 4)),
      );
      final result =
          await HistoryRepositoryImpl(source).recent()
              as Success<List<HistoryEntry>>;
      expect(result.value, entries.take(3).toList());
    });
    test('propagates page failures', () async {
      when(
        () => source.page(since: 'since'),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final result =
          await HistoryRepositoryImpl(source).all(since: 'since')
              as FailureResult<List<HistoryEntry>>;
      expect(result.failure, isA<NetworkFailure>());
    });
  });
}
