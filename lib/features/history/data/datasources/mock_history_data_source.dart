import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/data/datasources/history_data_source.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';

class MockHistoryDataSource implements HistoryDataSource {
  MockHistoryDataSource({required this.userId, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final String Function() userId;
  final DateTime Function() _now;
  final _records = <String, List<HistoryEntry>>{};
  @override
  Future<Result<HistoryPageData>> page({
    required String? since,
    String? cursor,
  }) async {
    final user = userId();
    final records = _records.putIfAbsent(
      user,
      () => user != 'demo_a'
          ? []
          : List.generate(
              27,
              (i) => HistoryEntry(
                logId: 'mock-history-$i',
                text: ['미지근한 물 주세요', '화장실 가고 싶어요', '아파요'][i % 3],
                source: i < 12 ? 'voice' : 'preset',
                selectedRank: i < 12 ? i % 3 + 1 : null,
                createdAt: _now().subtract(Duration(hours: i)),
              ),
            ),
    );
    final filtered = records
        .where(
          (e) => since == null || !e.createdAt.isBefore(DateTime.parse(since)),
        )
        .toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final entries = filtered.skip(start).take(20).toList(growable: false);
    final end = start + entries.length;
    return Success(
      HistoryPageData(
        entries: entries,
        total: filtered.length,
        nextCursor: end < filtered.length ? '$end' : null,
      ),
    );
  }
}
