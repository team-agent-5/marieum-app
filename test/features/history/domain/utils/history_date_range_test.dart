import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/history/domain/entities/history_range.dart';
import 'package:marieum_app/features/history/domain/utils/history_date_range.dart';

void main() {
  group('historySince', () {
    for (final now in [
      DateTime(2026),
      DateTime(2026, 1, 1, 23, 59, 59),
    ]) {
      test('uses calendar midnights across year boundary at $now', () {
        final today = historySince(now, HistoryRange.today);
        final week = historySince(now, HistoryRange.week);
        expect(DateTime.parse(today).toLocal(), DateTime(2026));
        expect(DateTime.parse(week).toLocal(), DateTime(2025, 12, 26));
        expect(today, matches(RegExp(r'[+-]\d{2}:\d{2}$')));
        expect(week, matches(RegExp(r'[+-]\d{2}:\d{2}$')));
      });
    }
    test('changes today only at local midnight', () {
      final before = historySince(
        DateTime(2026, 11, 1, 23, 59),
        HistoryRange.today,
      );
      final after = historySince(DateTime(2026, 11, 2), HistoryRange.today);
      expect(DateTime.parse(before).toLocal(), DateTime(2026, 11));
      expect(DateTime.parse(after).toLocal(), DateTime(2026, 11, 2));
    });
  });
}
