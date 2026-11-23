import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/live_session_view.dart';
import 'package:mocktail/mocktail.dart';

class _MockLiveSessionCubit extends MockCubit<LiveSessionState>
    implements LiveSessionCubit {}

final _at = DateTime(2026, 10, 31, 14, 5);

void main() {
  late _MockLiveSessionCubit cubit;

  Future<void> pumpView(
    WidgetTester tester,
    LiveSessionState state, {
    bool withHostRoute = false,
  }) async {
    cubit = _MockLiveSessionCubit();
    when(() => cubit.replay(any())).thenAnswer((_) async {});
    whenListen(
      cubit,
      const Stream<LiveSessionState>.empty(),
      initialState: state,
    );
    final view = BlocProvider<LiveSessionCubit>.value(
      value: cubit,
      child: LiveSessionView(onClose: () {}),
    );
    if (withHostRoute) {
      final router = GoRouter(
        initialLocation: AppRoutes.live,
        routes: [
          GoRoute(path: AppRoutes.live, builder: (_, _) => view),
          GoRoute(
            path: AppRoutes.listenHost,
            builder: (context, _) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => context.pop(true),
                    child: const Text('연결 완료'),
                  ),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('연결 취소'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    } else {
      await tester.pumpWidget(MaterialApp(home: view));
    }
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

  const checking = '상대방 폰을 확인하고 있어요';
  const relaying = '상대방 폰으로 전하고 있어요';
  const localFallback = '상대방 폰 연결이 끊겨 이 폰에서 읽어요';
  const deliveries = [
    (LiveDelivery.sending, '보내는 중'),
    (LiveDelivery.delivered, '상대방 폰에 보냈어요'),
    (LiveDelivery.played, '상대방 폰에서 읽고 있어요'),
    (LiveDelivery.local, '이 폰에서 읽었어요'),
  ];

  LiveSegment sentence(int id, LiveDelivery delivery) => LiveSegment(
    id: id,
    at: _at,
    status: LiveSegmentStatus.done,
    text: '문장$id',
    delivery: delivery,
  );

  group('sound destination', () {
    Set<bool> selected(WidgetTester tester) => tester
        .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
        .selected;

    testWidgets('defaults to this phone and switches directly when joined', (
      tester,
    ) async {
      await pumpView(
        tester,
        const LiveSessionState(
          status: LiveStatus.listening,
          listener: ListenerPresence.joined,
        ),
      );

      expect(find.text('소리 나는 곳'), findsOneWidget);
      expect(selected(tester), {false});
      await tester.tap(find.text('상대방 폰'));

      verify(cubit.useOtherPhone).called(1);
    });

    for (final confirmed in [true, false]) {
      testWidgets(
        'switches to the other phone only if setup returns true (confirmed: $confirmed)',
        (
          tester,
        ) async {
          await pumpView(
            tester,
            const LiveSessionState(
              status: LiveStatus.listening,
              listener: ListenerPresence.none,
            ),
            withHostRoute: true,
          );

          await tester.tap(find.text('상대방 폰'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          verifyNever(cubit.useOtherPhone);
          await tester.tap(find.text(confirmed ? '연결 완료' : '연결 취소'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          if (confirmed) {
            verify(cubit.useOtherPhone).called(1);
          } else {
            verifyNever(cubit.useOtherPhone);
            expect(selected(tester), {false});
          }
        },
      );
    }

    testWidgets('switches back to this phone', (tester) async {
      await pumpView(
        tester,
        const LiveSessionState(status: LiveStatus.listening, relay: true),
      );
      when(cubit.useThisPhone).thenAnswer((_) async {});

      expect(selected(tester), {true});
      await tester.tap(find.text('내 폰'));

      verify(cubit.useThisPhone).called(1);
    });
  });

  group('relay live session', () {
    for (final (presence, message) in [
      (null, checking),
      (ListenerPresence.joined, relaying),
      (ListenerPresence.left, localFallback),
      (ListenerPresence.none, localFallback),
    ]) {
      testWidgets('shows the relay banner for ${presence?.name ?? 'unknown'}', (
        tester,
      ) async {
        await pumpView(
          tester,
          LiveSessionState(
            status: LiveStatus.listening,
            relay: true,
            listener: presence,
          ),
        );

        expect(find.text(message), findsOneWidget);
        expect(find.text('내 목소리로 말하기'), findsOneWidget);
        expect(find.text('실시간 모드'), findsOneWidget);
      });
    }

    for (final (delivery, label) in deliveries) {
      testWidgets('shows the ${delivery.name} badge on the newest sentence', (
        tester,
      ) async {
        await pumpView(
          tester,
          LiveSessionState(
            status: LiveStatus.listening,
            relay: true,
            segments: [sentence(0, delivery)],
          ),
        );

        expect(find.text(label), findsOneWidget);
      });
    }

    testWidgets('shows a badge on a past sentence and omits missing delivery', (
      tester,
    ) async {
      await pumpView(
        tester,
        LiveSessionState(
          status: LiveStatus.listening,
          relay: true,
          segments: [
            sentence(0, LiveDelivery.played),
            sentence(1, LiveDelivery.none),
          ],
        ),
      );

      expect(find.text('문장0'), findsOneWidget);
      expect(find.text('문장1'), findsOneWidget);
      expect(find.text('상대방 폰에서 읽고 있어요'), findsOneWidget);
      for (final (_, label) in deliveries.where(
        (entry) => entry.$1 != LiveDelivery.played,
      )) {
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets(
      'keeps the badge reachable after a long sentence on a narrow phone',
      (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpView(
          tester,
          LiveSessionState(
            status: LiveStatus.listening,
            relay: true,
            listener: ListenerPresence.none,
            segments: [
              sentence(0, LiveDelivery.local).copyWith(
                text: List.filled(8, '이 문장을 함께 확인해 주세요.').join(' '),
              ),
            ],
          ),
        );

        final badge = find.text('이 폰에서 읽었어요');
        await tester.ensureVisible(badge);
        await tester.pump();
        expect(badge.hitTestable(), findsOneWidget);
        expect(find.text(localFallback), findsOneWidget);
      },
    );

    testWidgets('keeps relay indicators off the regular live screen', (
      tester,
    ) async {
      await pumpView(
        tester,
        LiveSessionState(
          status: LiveStatus.listening,
          listener: ListenerPresence.joined,
          segments: [sentence(0, LiveDelivery.played)],
        ),
      );

      expect(find.text('내 목소리로 말하기'), findsOneWidget);
      expect(find.text('실시간 모드'), findsOneWidget);
      for (final message in [checking, relaying, localFallback]) {
        expect(find.text(message), findsNothing);
      }
      expect(find.text('상대방 폰에서 읽고 있어요'), findsNothing);
    });
  });

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

    testWidgets('asks to wait until the microphone is back', (tester) async {
      final segment = LiveSegment(
        id: 0,
        at: _at,
        status: LiveSegmentStatus.done,
        text: '고마워요',
      );
      final speaking = LiveSessionState(
        status: LiveStatus.listening,
        playingId: 0,
        micPaused: true,
        segments: [segment],
      );
      final states = StreamController<LiveSessionState>();
      cubit = _MockLiveSessionCubit();
      whenListen(cubit, states.stream, initialState: speaking);
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<LiveSessionCubit>.value(
            value: cubit,
            child: LiveSessionView(onClose: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      const toast = '읽어드리는 동안 잠시 기다려 주세요';
      expect(find.text(toast), findsOneWidget);

      // The voice has ended but the microphone is still reopening.
      states.add(speaking.copyWith(playingId: () => null));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(toast), findsOneWidget);

      states.add(speaking.copyWith(playingId: () => null, micPaused: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(toast), findsNothing);
      await states.close();
    });

    testWidgets('says the last words are on their way while finishing', (
      tester,
    ) async {
      await pumpView(
        tester,
        const LiveSessionState(status: LiveStatus.finishing),
      );
      expect(find.text('하시던 말을 마저 전하고 있어요'), findsOneWidget);
      expect(find.text('마무리하고 있어요'), findsOneWidget);
      expect(find.text('바로 끝내기'), findsOneWidget);
    });

    testWidgets('shows no wait message while listening', (tester) async {
      await pumpView(
        tester,
        const LiveSessionState(status: LiveStatus.listening),
      );
      expect(find.text('읽어드리는 동안 잠시 기다려 주세요'), findsNothing);
    });
  });
}
