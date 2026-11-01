import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/live_session_view.dart';
import 'package:mocktail/mocktail.dart';

class _MockLiveSessionCubit extends MockCubit<LiveSessionState>
    implements LiveSessionCubit {}

final _at = DateTime(2026, 10, 31, 14, 5);

void main() {
  late _MockLiveSessionCubit cubit;

  Future<void> pumpView(WidgetTester tester, LiveSessionState state) async {
    cubit = _MockLiveSessionCubit();
    when(() => cubit.replay(any())).thenAnswer((_) async {});
    whenListen(
      cubit,
      const Stream<LiveSessionState>.empty(),
      initialState: state,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<LiveSessionCubit>.value(
          value: cubit,
          child: LiveSessionView(onClose: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  List<Color?> barColors(WidgetTester tester) => [
    for (final bar in tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('live_signal')),
        matching: find.byType(AnimatedContainer),
      ),
    ))
      (bar.decoration! as BoxDecoration).color,
  ];

  group(LiveSessionView, () {
    testWidgets('shows the newest sentence large and earlier ones above', (
      tester,
    ) async {
      await pumpView(
        tester,
        LiveSessionState(
          status: LiveStatus.listening,
          segments: [
            LiveSegment(
              id: 0,
              at: _at,
              status: LiveSegmentStatus.done,
              text: '물 주세요',
            ),
            LiveSegment(
              id: 1,
              at: _at,
              status: LiveSegmentStatus.done,
              text: '고마워요',
            ),
          ],
        ),
      );
      expect(find.text('물 주세요'), findsOneWidget);
      expect(find.text('14:05'), findsOneWidget);
      expect(tester.widget<Text>(find.text('물 주세요')).style!.fontSize, 17);
      expect(tester.widget<Text>(find.text('고마워요')).style!.fontSize, 30);

      await tester.tap(find.text('물 주세요'));
      verify(() => cubit.replay(0)).called(1);
    });

    testWidgets('keeps a lone sentence in the middle', (tester) async {
      LiveSegment done(int id) => LiveSegment(
        id: id,
        at: _at,
        status: LiveSegmentStatus.done,
        text: '문장$id',
      );
      final card = find.byKey(const ValueKey('live_transcript'));

      await pumpView(
        tester,
        LiveSessionState(status: LiveStatus.listening, segments: [done(0)]),
      );
      final middle = tester.getCenter(card).dy;
      expect(
        (tester.getCenter(find.text('문장0')).dy - middle).abs(),
        lessThan(30),
      );

      await pumpView(
        tester,
        LiveSessionState(
          status: LiveStatus.listening,
          segments: [for (var i = 0; i < 12; i++) done(i)],
        ),
      );
      expect(
        tester.getBottomLeft(find.text('문장11')).dy,
        greaterThan(tester.getBottomLeft(card).dy - 60),
      );
    });

    testWidgets('shows interpreted sentences and progress', (tester) async {
      await pumpView(
        tester,
        LiveSessionState(
          status: LiveStatus.listening,
          segments: [
            LiveSegment(
              id: 0,
              at: _at,
              status: LiveSegmentStatus.done,
              text: '물 주세요',
            ),
            LiveSegment(id: 1, at: _at),
          ],
        ),
      );
      expect(find.text('물 주세요'), findsOneWidget);
      expect(find.text('해석하고 있어요'), findsOneWidget);
      expect(find.text('녹음 끝내기'), findsNothing);
      expect(find.text('그만하기'), findsOneWidget);
    });

    testWidgets('colors loud input bars while hearing a voice', (
      tester,
    ) async {
      await pumpView(
        tester,
        const LiveSessionState(
          status: LiveStatus.listening,
          levels: [0.1, 0.8],
          hearing: true,
        ),
      );
      expect(find.text('목소리가 들려요'), findsOneWidget);
      final colors = barColors(tester);
      expect(colors.last, AppTokens.primary);
      expect(colors[colors.length - 2], AppTokens.lineStrong);
    });

    testWidgets('keeps showing the voice while speaking aloud', (tester) async {
      await pumpView(
        tester,
        LiveSessionState(
          status: LiveStatus.listening,
          levels: const [0.8],
          playingId: 0,
          segments: [
            LiveSegment(
              id: 0,
              at: _at,
              status: LiveSegmentStatus.done,
              text: '고마워요',
            ),
          ],
        ),
      );
      expect(find.text('전달하고 있어요'), findsOneWidget);
      expect(barColors(tester), contains(AppTokens.primary));
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });
  });
}
