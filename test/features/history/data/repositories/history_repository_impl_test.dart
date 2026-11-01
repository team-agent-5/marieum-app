import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/data/datasources/history_data_source.dart';
import 'package:marieum_app/features/history/data/repositories/history_repository_impl.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';
import 'package:mocktail/mocktail.dart';

class _MockSource extends Mock implements HistoryDataSource {}

const _since = '2026-01-01T00:00:00.000+09:00';

HistoryEntry _entry(String id, DateTime createdAt) => HistoryEntry(
  logId: id,
  text: '문장 $id',
  source: 'voice',
  createdAt: createdAt,
);

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
        createdAt: DateTime.utc(2026, 3),
      );
      when(() => source.page(since: null)).thenAnswer(
        (_) async => Success(
          HistoryPageData(entries: [entry], total: 1, nextCursor: 'next'),
        ),
      );
      when(() => source.page(since: null, cursor: 'next')).thenAnswer(
        (_) async => Success(HistoryPageData(entries: [entry], total: 1)),
      );
      final result =
          await HistoryRepositoryImpl(source).all(since: _since)
              as Success<List<HistoryEntry>>;
      expect(result.value, [entry]);
      verify(() => source.page(since: null, cursor: 'next')).called(1);
    });
    test('reports repeated cursors instead of looping indefinitely', () async {
      const data = Success(
        HistoryPageData(entries: [], total: 1, nextCursor: 'next'),
      );
      when(() => source.page(since: null)).thenAnswer((_) async => data);
      when(
        () => source.page(since: null, cursor: 'next'),
      ).thenAnswer((_) async => data);
      final result =
          await HistoryRepositoryImpl(source).all(since: _since)
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
    test('drops entries before the start and stops paging there', () async {
      final start = DateTime.parse(_since);
      when(() => source.page(since: null)).thenAnswer(
        (_) async => Success(
          HistoryPageData(
            entries: [
              _entry('3', start.add(const Duration(hours: 2))),
              _entry('2', start),
              _entry('1', start.subtract(const Duration(minutes: 1))),
            ],
            total: 30,
            nextCursor: 'older',
          ),
        ),
      );
      final page =
          await HistoryRepositoryImpl(source).page(since: _since)
              as Success<HistoryPageData>;
      expect([for (final e in page.value.entries) e.logId], ['3', '2']);
      expect(page.value.nextCursor, isNull);
      expect(page.value.total, 2);
      verifyNever(() => source.page(since: null, cursor: 'older'));
    });

    test('keeps paging while every entry is inside the range', () async {
      final start = DateTime.parse(_since);
      when(() => source.page(since: null)).thenAnswer(
        (_) async => Success(
          HistoryPageData(
            entries: [_entry('9', start.add(const Duration(days: 1)))],
            total: 30,
            nextCursor: 'older',
          ),
        ),
      );
      final page =
          await HistoryRepositoryImpl(source).page(since: _since)
              as Success<HistoryPageData>;
      expect(page.value.nextCursor, 'older');
      expect(page.value.total, 30);
    });

    test('propagates page failures', () async {
      when(
        () => source.page(since: null),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final result =
          await HistoryRepositoryImpl(source).all(since: _since)
              as FailureResult<List<HistoryEntry>>;
      expect(result.failure, isA<NetworkFailure>());
    });
  });
}
