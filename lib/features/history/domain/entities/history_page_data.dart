import 'package:marieum_app/features/history/domain/entities/history_entry.dart';

class HistoryPageData {
  const HistoryPageData({
    required this.entries,
    required this.total,
    this.nextCursor,
  });
  final List<HistoryEntry> entries;
  final int total;
  final String? nextCursor;
}
