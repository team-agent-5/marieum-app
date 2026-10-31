import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/history/domain/history.dart';

// 원격 구현과 모의 구현을 같은 인터페이스로 교체한다.
// ignore: one_member_abstracts
abstract interface class HistoryDataSource {
  Future<Result<HistoryPageData>> page({required String since, String? cursor});
}

class RemoteHistoryDataSource implements HistoryDataSource {
  RemoteHistoryDataSource(this._client);
  final ApiClient _client;
  @override
  Future<Result<HistoryPageData>> page({
    required String since,
    String? cursor,
  }) => _client.request(
    '/phrase/history',
    query: {'limit': 20, 'since': since, 'cursor': cursor ?? ''},
    decode: decodeHistoryPage,
  );
}

HistoryPageData decodeHistoryPage(Object? json) {
  final body = json! as Map<String, Object?>;
  final entries = (body['items']! as List<Object?>)
      .map((value) {
        final item = value! as Map<String, Object?>;
        final id = item['log_id'];
        if (id is! String && id is! int) {
          throw const FormatException('Invalid log ID.');
        }
        final rank = item['selected_rank'];
        return HistoryEntry(
          logId: id.toString(),
          text: item['final_text']! as String,
          source: item['source']! as String,
          createdAt: DateTime.parse(item['created_at']! as String),
          selectedRank: rank == null ? null : rank as int,
        );
      })
      .toList(growable: false);
  return HistoryPageData(
    entries: List.unmodifiable(entries),
    total: body['total_estimate']! as int,
    nextCursor: body['next_cursor'] as String?,
  );
}

class MockHistoryDataSource implements HistoryDataSource {
  MockHistoryDataSource({required this.userId, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final String Function() userId;
  final DateTime Function() _now;
  final _records = <String, List<HistoryEntry>>{};
  @override
  Future<Result<HistoryPageData>> page({
    required String since,
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
        .where((e) => !e.createdAt.isBefore(DateTime.parse(since)))
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
