import 'package:equatable/equatable.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';

class InsightSummary extends Equatable {
  const InsightSummary({
    required this.total,
    required this.voiceCount,
    required this.rankCounts,
    required this.frequent,
  });
  factory InsightSummary.fromEntries(List<HistoryEntry> entries) {
    final ranks = [0, 0, 0];
    final frequencies = <String, int>{};
    for (final entry in entries) {
      final rank = entry.selectedRank;
      if (entry.source == 'voice' && rank != null && rank >= 1 && rank <= 3) {
        ranks[rank - 1]++;
      }
      frequencies.update(entry.text, (n) => n + 1, ifAbsent: () => 1);
    }
    final ordered = frequencies.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count == 0 ? a.key.compareTo(b.key) : count;
      });
    return InsightSummary(
      total: entries.length,
      voiceCount: ranks.fold(0, (a, b) => a + b),
      rankCounts: List.unmodifiable(ranks),
      frequent: List.unmodifiable(
        ordered.take(3).map((e) => (text: e.key, count: e.value)),
      ),
    );
  }
  final int total;
  final int voiceCount;
  final List<int> rankCounts;
  final List<({String text, int count})> frequent;
  bool get learning => voiceCount < 10;
  double rankRatio(int rank) =>
      voiceCount == 0 ? 0 : rankCounts[rank - 1] / voiceCount;
  @override
  List<Object?> get props => [total, voiceCount, rankCounts, frequent];
}
