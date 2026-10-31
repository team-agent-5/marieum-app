import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/speak/domain/entities/live_phrase_policy.dart';

void main() {
  group(LivePhrasePolicy, () {
    test('removes replacement characters only from display text', () {
      expect(LivePhrasePolicy.displayText(' 물� 주세요� '), '물 주세요');
    });
    test('matches similar whole sentences after punctuation normalization', () {
      expect(LivePhrasePolicy.isEcho('미지근한 물 주세요', '미지근한 물 주세요.'), isTrue);
      expect(LivePhrasePolicy.isEcho('미지근한 물 주세요', '미지근한 물 주세오'), isTrue);
      expect(LivePhrasePolicy.isEcho('미지근한 물 주세요', '화장실 가고 싶어요'), isFalse);
    });
    test(
      'keeps short words even when they are contained in the spoken text',
      () {
        expect(LivePhrasePolicy.isEcho('물 좀 주세요', '물'), isFalse);
        expect(LivePhrasePolicy.isEcho('네', '네'), isFalse);
        expect(LivePhrasePolicy.isEcho('미지근한 물 주세요', '물 주세요'), isFalse);
      },
    );
  });
}
