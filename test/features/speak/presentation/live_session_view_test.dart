import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/live_session_view.dart';

class _MockLiveSessionCubit extends MockCubit<LiveSessionState>
    implements LiveSessionCubit {}

void main() {
  Future<void> pumpView(WidgetTester tester, LiveSessionState state) async {
    final cubit = _MockLiveSessionCubit();
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
    testWidgets('shows interpreted sentences and progress', (tester) async {
      await pumpView(
        tester,
        const LiveSessionState(
          status: LiveStatus.listening,
          segments: [
            LiveSegment(
              id: 0,
              status: LiveSegmentStatus.done,
              text: '물 주세요',
            ),
            LiveSegment(id: 1),
          ],
        ),
      );
      expect(find.text('물'), findsOneWidget);
      expect(find.text('주세요'), findsOneWidget);
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

    testWidgets('greys out the signal while speaking aloud', (tester) async {
      await pumpView(
        tester,
        const LiveSessionState(
          status: LiveStatus.listening,
          levels: [0.8],
          playingId: 0,
          segments: [
            LiveSegment(
              id: 0,
              status: LiveSegmentStatus.done,
              text: '고마워요',
            ),
          ],
        ),
      );
      expect(find.text('전달하고 있어요'), findsOneWidget);
      expect(barColors(tester).toSet(), {AppTokens.line});
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });
  });
}
