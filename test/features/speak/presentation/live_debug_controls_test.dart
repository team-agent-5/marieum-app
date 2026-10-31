import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockLiveCubit extends MockCubit<LiveSessionState>
    implements LiveSessionCubit {}

void main() {
  group('Live debug controls', () {
    late _MockLiveCubit cubit;
    setUp(() {
      cubit = _MockLiveCubit();
      whenListen(
        cubit,
        const Stream<LiveSessionState>.empty(),
        initialState: const LiveSessionState(status: LiveStatus.listening),
      );
      when(cubit.start).thenAnswer((_) async {});
      when(cubit.close).thenAnswer((_) async {});
      when(
        () => cubit.setEchoCancel(enabled: any(named: 'enabled')),
      ).thenAnswer((_) async {});
    });
    testWidgets('lets the user compare echo cancellation on the phone', (
      tester,
    ) async {
      await tester.pumpApp(
        initialLocation: '/speak/live',
        createLiveSessionCubit: () => cubit,
      );
      expect(find.text('개발: 에코 제거'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(() => cubit.setEchoCancel(enabled: false)).called(1);
    });
  });
}
