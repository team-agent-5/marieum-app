import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/history/domain/history.dart';
import 'package:marieum_app/features/insight/domain/insight_summary.dart';
import 'package:marieum_app/features/insight/presentation/insight_cubit.dart';
import 'package:marieum_app/features/insight/presentation/insight_page.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/pump_app.dart';

class _MockInsight extends MockCubit<InsightState> implements InsightCubit {}

void main() {
  group(InsightPage, () {
    testWidgets(
      'shows history-derived statistics without an undefined phrase count',
      (tester) async {
        final cubit = _MockInsight();
        final summary = InsightSummary.fromEntries(
          List.generate(
            10,
            (i) => HistoryEntry(
              logId: '$i',
              text: '물 주세요',
              source: 'voice',
              selectedRank: i < 5 ? 1 : 2,
              createdAt: DateTime(2026),
            ),
          ),
        );
        when(() => cubit.state).thenReturn(
          InsightState(status: InsightStatus.success, summary: summary),
        );
        when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
        when(cubit.load).thenAnswer((_) async {});
        when(cubit.close).thenAnswer((_) async {});
        final router = await tester.pumpApp(
          initialLocation: '/insight',
          createInsightCubit: () => cubit,
        );
        addTearDown(router.dispose);
        expect(find.text('이번 주 요청'), findsOneWidget);
        expect(find.text('첫 후보 선택'), findsOneWidget);
        expect(find.text('50%'), findsOneWidget);
        expect(find.text('자주 쓰는 말'), findsNothing);
        expect(find.text('자주 쓴 말'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
