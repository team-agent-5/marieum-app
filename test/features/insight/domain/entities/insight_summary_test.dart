import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/insight/domain/entities/insight_summary.dart';

HistoryEntry _entry(
  int id, {
  String source = 'voice',
  int? rank = 1,
  String text = '물 주세요',
}) => HistoryEntry(
  logId: '$id',
  text: text,
  source: source,
  selectedRank: rank,
  createdAt: DateTime(2026),
);
void main() {
  group(InsightSummary, () {
    test('handles empty history without dividing by zero', () {
      final summary = InsightSummary.fromEntries(const []);
      expect(summary.total, 0);
      expect(summary.voiceCount, 0);
      expect(summary.learning, isTrue);
      expect(summary.rankRatio(1), 0);
      expect(summary.frequent, isEmpty);
    });
    for (final count in [9, 10]) {
      test(
        'changes learning status exactly at ten ranked voice choices ($count)',
        () {
          final summary = InsightSummary.fromEntries(
            List.generate(count, _entry),
          );
          expect(summary.learning, count < 10);
          expect(summary.voiceCount, count);
        },
      );
    }
    test('excludes unranked and non-voice entries from rank distribution', () {
      final summary = InsightSummary.fromEntries([
        _entry(1),
        _entry(2, rank: 2),
        _entry(3, rank: null),
        _entry(4, source: 'preset'),
        _entry(5, source: 'voice_bypass'),
        _entry(6, rank: 4),
      ]);
      expect(summary.total, 6);
      expect(summary.voiceCount, 2);
      expect(summary.rankCounts, [1, 1, 0]);
      expect(summary.rankRatio(1), .5);
    });
    test(
      'counts text frequency across all sources and keeps the top three',
      () {
        final summary = InsightSummary.fromEntries([
          _entry(1, text: '가'),
          _entry(2, source: 'preset', text: '가'),
          _entry(3, text: '나'),
          _entry(4, text: '나'),
          _entry(5, text: '나'),
          _entry(6, text: '다'),
          _entry(7, text: '라'),
        ]);
        expect(summary.frequent, [
          (text: '나', count: 3),
          (text: '가', count: 2),
          (text: '다', count: 1),
        ]);
      },
    );
  });
}
