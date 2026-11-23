import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listen_host_cubit.dart';
import 'package:marieum_app/features/listen/presentation/pages/listen_host_page.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_host_view.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _MockListenHostCubit extends MockCubit<ListenHostState>
    implements ListenHostCubit {}

void main() {
  late _MockListenHostCubit cubit;

  setUp(() => cubit = _MockListenHostCubit());

  void stubState(ListenHostState state) {
    whenListen(
      cubit,
      const Stream<ListenHostState>.empty(),
      initialState: state,
    );
  }

  Future<void> pump(WidgetTester tester, ListenHostState state) async {
    stubState(state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<ListenHostCubit>.value(
          value: cubit,
          child: ListenHostView(onClose: () {}, onBack: () {}),
        ),
      ),
    );
  }

  testWidgets('waiting shows the grouped code, QR and countdown', (
    tester,
  ) async {
    final expiry = DateTime(2026, 11, 22, 12);
    await pump(
      tester,
      ListenHostState(
        phase: ListenHostPhase.waiting,
        session: ListenSession(
          id: 'session',
          joinCode: 'K7Q2MX',
          joinExpiresAt: expiry,
          expiresAt: expiry.add(const Duration(hours: 2)),
        ),
        joinRemaining: const Duration(minutes: 2, seconds: 5),
      ),
    );

    expect(find.text('K7Q 2MX'), findsOneWidget);
    expect(find.text('남은 시간 02:05'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(QrImageView),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is QrPainter,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('waiting shows a short server code without grouping', (
    tester,
  ) async {
    final expiry = DateTime(2026, 11, 22, 12);
    await pump(
      tester,
      ListenHostState(
        phase: ListenHostPhase.waiting,
        session: ListenSession(
          id: 'session',
          joinCode: 'K7',
          joinExpiresAt: expiry,
          expiresAt: expiry.add(const Duration(hours: 2)),
        ),
      ),
    );

    expect(find.text('K7'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('connected shows confirmation', (tester) async {
    await pump(tester, const ListenHostState(phase: ListenHostPhase.connected));

    expect(find.text('상대방 폰과 연결됐어요'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  for (final (action, label) in [
    ('primary button', '돌아가서 말하기'),
    ('toolbar back', '뒤로'),
    ('system back', null),
  ]) {
    testWidgets(
      '$action keeps a recovered connection and returns true',
      (
        tester,
      ) async {
        stubState(const ListenHostState(phase: ListenHostPhase.connected));
        when(cubit.start).thenAnswer((_) async {});
        bool? result;
        final router = GoRouter(
          initialLocation: AppRoutes.live,
          routes: [
            GoRoute(
              path: AppRoutes.live,
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await context.push<bool>(AppRoutes.listenHost);
                  },
                  child: const Text('연결 화면 열기'),
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.listenHost,
              builder: (_, _) => ListenHostPage(createCubit: () => cubit),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.tap(find.text('연결 화면 열기'));
        await tester.pumpAndSettle();

        expect(find.text('상대방 폰과 연결됐어요'), findsOneWidget);
        if (label == null) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(
            label == '뒤로' ? find.byTooltip(label) : find.text(label),
          );
        }
        await tester.pumpAndSettle();

        expect(router.state.uri.path, AppRoutes.live);
        expect(result, isTrue);
        verifyNever(cubit.end);
      },
    );
  }

  testWidgets('expired code can be renewed', (tester) async {
    when(cubit.renew).thenAnswer((_) async {});
    await pump(
      tester,
      const ListenHostState(phase: ListenHostPhase.codeExpired),
    );

    await tester.tap(find.text('새 코드 만들기'));

    verify(cubit.renew).called(1);
  });

  testWidgets('listener leaving shows a message and offers a new code', (
    tester,
  ) async {
    when(cubit.renew).thenAnswer((_) async {});
    await pump(tester, const ListenHostState(phase: ListenHostPhase.left));

    expect(find.text('상대방 폰 연결이 끊겼어요'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    await tester.tap(find.text('새 코드 만들기'));

    verify(cubit.renew).called(1);
  });

  for (final (phase, action, disconnect) in [
    (ListenHostPhase.codeExpired, 'back before connecting', false),
    (ListenHostPhase.connected, 'disconnect after connecting', true),
  ]) {
    testWidgets('$action waits for end and returns no confirmation', (
      tester,
    ) async {
      final ended = Completer<void>();
      stubState(ListenHostState(phase: phase));
      when(cubit.start).thenAnswer((_) async {});
      when(cubit.end).thenAnswer((_) => ended.future);
      final result = Completer<bool?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.complete(
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ListenHostPage(createCubit: () => cubit),
                    ),
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      verify(cubit.start).called(1);

      if (disconnect) {
        await tester.tap(find.text('연결 끊기'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      verify(cubit.end).called(1);
      expect(find.byType(ListenHostPage), findsOneWidget);

      ended.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ListenHostPage), findsNothing);
      expect(await result.future, isNull);
    });
  }
}
