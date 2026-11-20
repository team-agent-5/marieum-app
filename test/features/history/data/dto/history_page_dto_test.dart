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

    test('drops rejected suggestions the patient never said', () {
      final page = decodeHistoryPage({
        'items': [
          {
            'log_id': 79,
            'final_text': '화장실 가고 싶어요',
            'source': 'voice_bypass',
            'created_at': '2026-11-20T07:43:13Z',
            'selected_rank': null,
          },
          {
            'log_id': 78,
            'final_text': '물 좀 주세요',
            'source': 'rejected',
            'created_at': '2026-11-20T07:43:12Z',
            'selected_rank': null,
          },
        ],
        'total_estimate': 2,
        'next_cursor': null,
      });
      expect(page.entries.map((e) => e.logId), ['79']);
      expect(page.total, 1);
    });
  });
}
