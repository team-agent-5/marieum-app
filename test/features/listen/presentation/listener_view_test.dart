import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listener_cubit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listener_view.dart';
import 'package:mocktail/mocktail.dart';

class _MockListenerCubit extends MockCubit<ListenerState>
    implements ListenerCubit {}

void main() {
  late _MockListenerCubit cubit;

  setUp(() => cubit = _MockListenerCubit());

  Future<void> pump(WidgetTester tester, ListenerState state) async {
    whenListen(cubit, const Stream<ListenerState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<ListenerCubit>.value(
          value: cubit,
          child: ListenerView(onClose: () {}),
        ),
      ),
    );
  }

  testWidgets('submits a pasted code in uppercase without spaces', (
    tester,
  ) async {
    when(() => cubit.join('K7Q2MX')).thenAnswer((_) async {});
    await pump(tester, const ListenerState());

    await tester.enterText(find.byType(TextField), 'k7q 2mx');
    await tester.pump();
    await tester.tap(find.text('연결하기'));

    verify(() => cubit.join('K7Q2MX')).called(1);
  });

  testWidgets('shows the cubit error and leaves code entry available', (
    tester,
  ) async {
    await pump(tester, const ListenerState(error: '코드가 맞지 않거나 시간이 지났어요.'));

    expect(find.text('코드가 맞지 않거나 시간이 지났어요.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('QR 찍기'), findsOneWidget);
  });

  testWidgets('shows the latest line, playback status and history', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 22);
    await pump(
      tester,
      ListenerState(
        phase: ListenerPhase.listening,
        speakingId: 'latest',
        lines: [
          HeardLine(utteranceId: 'earlier', text: '안녕하세요', heardAt: now),
          HeardLine(utteranceId: 'latest', text: '물 좀 주세요', heardAt: now),
        ],
      ),
    );

    final recent = tester.widget<Text>(find.text('물 좀 주세요'));
    final earlier = tester.widget<Text>(find.text('안녕하세요'));
    expect(recent.style!.fontSize, greaterThan(earlier.style!.fontSize!));
    expect(find.text('재생 중'), findsOneWidget);
    expect(find.text('지난 문장'), findsOneWidget);
    expect(find.text('그만 듣기'), findsOneWidget);
  });

  testWidgets('shows why the session ended and can accept another code', (
    tester,
  ) async {
    when(() => cubit.join('K7Q2MX')).thenAnswer((_) async {});
    await pump(
      tester,
      const ListenerState(
        phase: ListenerPhase.ended,
        endReason: ListenEndReason.patientLeft,
      ),
    );

    expect(find.text('환자가 연결을 끊었어요'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
    await tester.tap(find.text('다시 연결'));
    await tester.pumpAndSettle();
    expect(find.text('환자가 연결을 끊었어요'), findsNothing);
    await tester.enterText(find.byType(TextField), 'K7Q2MX');
    await tester.pump();
    await tester.tap(find.text('연결하기'));
    verify(() => cubit.join('K7Q2MX')).called(1);
  });
}
