import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';

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
