import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/speak/presentation/widgets/typed_transcript.dart';

void main() {
  Future<void> pumpText(
    WidgetTester tester,
    String text, {
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Material(child: TypedTranscript(text: text)),
      ),
    ),
  );

  double opacityOf(WidgetTester tester, String word) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(word), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  group(TypedTranscript, () {
    testWidgets('only newly added words fade in', (tester) async {
      await pumpText(tester, '물');
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, '물'), 1);

      await pumpText(tester, '물 주세요');
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, '물'), 1);
      expect(opacityOf(tester, '주세요'), lessThan(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester, '주세요'), 1);
    });

    testWidgets('a corrected word animates again', (tester) async {
      await pumpText(tester, '무 주세요');
      await tester.pump(const Duration(milliseconds: 400));
      await pumpText(tester, '물 주세요');
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, '물'), lessThan(1));
      expect(opacityOf(tester, '주세요'), 1);
    });

    testWidgets('shows words at once with reduce motion', (tester) async {
      await pumpText(tester, '물 주세요', reduceMotion: true);
      await tester.pump();
      expect(opacityOf(tester, '물'), 1);
      expect(opacityOf(tester, '주세요'), 1);
    });
  });
}
