import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
          child: ListenHostView(onClose: () {}),
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

  testWidgets('back waits for the session to end before popping', (
    tester,
  ) async {
    final ended = Completer<void>();
    stubState(const ListenHostState(phase: ListenHostPhase.connected));
    when(cubit.start).thenAnswer((_) async {});
    when(cubit.end).thenAnswer((_) => ended.future);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ListenHostPage(createCubit: () => cubit),
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

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    verify(cubit.end).called(1);
    expect(find.byType(ListenHostPage), findsOneWidget);

    ended.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ListenHostPage), findsNothing);
  });
}
