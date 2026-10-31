import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/data/datasources/history_data_source.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl(this._source);
  final HistoryDataSource _source;
  @override
  Future<Result<List<HistoryEntry>>> recent() async {
    final result = await _source.page(since: null);
    return switch (result) {
      Success(:final value) => Success(
        List.unmodifiable(value.entries.take(3)),
      ),
      FailureResult(:final failure) => FailureResult(failure),
    };
  }

  @override
  Future<Result<HistoryPageData>> page({
    required String since,
    String? cursor,
  }) => _source.page(since: since, cursor: cursor);
  @override
  Future<Result<List<HistoryEntry>>> all({required String since}) async {
    final entries = <String, HistoryEntry>{};
    final cursors = <String>{};
    String? cursor;
    do {
      final result = await page(since: since, cursor: cursor);
      if (result case FailureResult(:final failure)) {
        return FailureResult(failure);
      }
      final data = (result as Success<HistoryPageData>).value;
      for (final entry in data.entries) {
        entries[entry.logId] = entry;
      }
      cursor = data.nextCursor;
      if (cursor != null && !cursors.add(cursor)) {
        return const FailureResult(ProtocolFailure());
      }
    } while (cursor != null);
    return Success(List.unmodifiable(entries.values));
  }
}
