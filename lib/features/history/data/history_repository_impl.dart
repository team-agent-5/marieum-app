import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/data/history_data_source.dart';
import 'package:marieum_app/features/history/domain/history.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl(this._source);
  final HistoryDataSource _source;
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
