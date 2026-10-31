import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/history/data/dto/history_page_dto.dart';

void main() {
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
