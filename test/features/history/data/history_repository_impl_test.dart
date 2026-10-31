import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/data/history_data_source.dart';
import 'package:marieum_app/features/history/data/history_repository_impl.dart';
import 'package:marieum_app/features/history/domain/history.dart';
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
  group('decodeHistoryPage', () {
    test('decodes server history fields and nullable rank', () {
      final page = decodeHistoryPage({
        'items': [
          {
            'log_id': 1,
            'final_text': '물 주세요',
            'source': 'preset',
            'created_at': '2026-11-01T00:00:00+09:00',
            'selected_rank': null,
          },
        ],
        'total_estimate': 1,
        'next_cursor': 'next',
      });
      expect(page.entries.single.logId, '1');
      expect(page.entries.single.selectedRank, isNull);
      expect(page.nextCursor, 'next');
    });
  });
}
