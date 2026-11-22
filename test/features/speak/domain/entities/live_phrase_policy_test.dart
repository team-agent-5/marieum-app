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
    test('finds a piece of the last sentence heard again', () {
      const last = '아주 읽고 단추를 채웁니다 책상이 가방이 있습니다';
      expect(LivePhrasePolicy.isLeftover('가방이', last), isTrue);
      expect(LivePhrasePolicy.isLeftover('가방이 있습니다.', last), isTrue);
      expect(LivePhrasePolicy.isLeftover('가방이 없어요', last), isFalse);
      expect(LivePhrasePolicy.isLeftover(last, last), isFalse);
      expect(LivePhrasePolicy.isLeftover('', last), isFalse);
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
