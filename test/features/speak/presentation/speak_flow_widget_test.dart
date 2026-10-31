import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/live_session_view.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockUtteranceBloc extends MockBloc<UtteranceEvent, UtteranceState>
    implements UtteranceBloc {}

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _MockSpeakModeCubit extends MockCubit<SpeakModeState>
    implements SpeakModeCubit {}

const _transcription = Transcription(
  traceId: 't1',
  finalTranscript: '물 좀 주세요',
  asrConfidence: 0.82,
);
const _suggestions = Suggestions(
  traceId: 's1',
  candidates: [
    Candidate(
      rank: 1,
      text: '물 주세요',
      score: 0.9,
      reasonDisplay: '자주 쓰는 말',
    ),
    Candidate(
      rank: 2,
      text: '미지근한 물 주세요',
      score: 0.7,
      reasonLabel: 'time_context',
    ),
    Candidate(rank: 3, text: '물 말고 차 주세요', score: 0.5),
  ],
);
const _suggesting = UtteranceState(
  phase: UtterancePhase.suggesting,
  transcription: _transcription,
  suggestions: _suggestions,
);

void main() {
  late _MockUtteranceBloc bloc;
  late StreamController<UtteranceState> states;

  setUpAll(() => registerFallbackValue(const UtteranceSheetDismissed()));

  setUp(() {
    bloc = _MockUtteranceBloc();
    states = StreamController<UtteranceState>.broadcast();
    addTearDown(states.close);
  });

  Future<void> pump(
    WidgetTester tester,
    UtteranceState initial, {
    bool settle = true,
    bool largeText = false,
  }) async {
    whenListen(bloc, states.stream, initialState: initial);
    final settings = _MockSettingsCubit();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState(AppSettings(largeText: largeText)),
    );
    final router = await tester.pumpApp(
      createUtteranceBloc: () => bloc,
      settingsCubit: settings,
      settle: settle,
    );
    if (!settle) await tester.pump(const Duration(milliseconds: 300));
    addTearDown(router.dispose);
  }

  Future<void> emit(WidgetTester tester, UtteranceState state) async {
    when(() => bloc.state).thenReturn(state);
    states.add(state);
    await tester.pumpAndSettle();
  }

  group('main screen while recording', () {
    testWidgets('shows timer and guidance and locks other controls', (
      tester,
    ) async {
      await pump(
        tester,
        const UtteranceState(
          phase: UtterancePhase.recording,
          elapsed: Duration(seconds: 3),
        ),
      );
      expect(find.text('0:03'), findsOneWidget);
      expect(find.text('손을 떼면 끝나요'), findsOneWidget);

      await tester.tap(find.text('요청'), warnIfMissed: false);
      await tester.tap(find.text('실시간 모드'), warnIfMissed: false);
      await tester.tap(find.text('물 주세요'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('0:03'), findsOneWidget);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('accuracy mode records while the button is held', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      expect(find.text('누르고 있는 동안 말씀하세요'), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('speak_cta'))),
      );
      verify(
        () => bloc.add(const UtteranceHoldStarted(SpeakMode.precise)),
      ).called(1);
      await gesture.up();
      verify(() => bloc.add(const UtteranceHoldEnded())).called(1);
      verifyNever(
        () => bloc.add(const UtteranceButtonPressed(SpeakMode.precise)),
      );
    });

    testWidgets('ignores taps while analyzing', (tester) async {
      await pump(
        tester,
        const UtteranceState(phase: UtterancePhase.analyzing),
        settle: false,
      );
      expect(find.text('분석하고 있어요'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('speak_cta')));
      verifyNever(() => bloc.add(any()));
    });
  });

  group('live mode', () {
    testWidgets('the main button opens the live session', (tester) async {
      final mode = _MockSpeakModeCubit();
      whenListen(
        mode,
        const Stream<SpeakModeState>.empty(),
        initialState: const SpeakModeState(SpeakMode.live),
      );
      whenListen(
        bloc,
        const Stream<UtteranceState>.empty(),
        initialState: const UtteranceState(),
      );
      final router = await tester.pumpApp(
        createUtteranceBloc: () => bloc,
        modeCubit: mode,
        settle: false,
      );
      addTearDown(router.dispose);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('speak_cta')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(router.state.uri.path, AppRoutes.live);
      expect(find.byType(LiveSessionView), findsOneWidget);
      verifyNever(() => bloc.add(any()));
    });
  });

  group('candidate sheet', () {
    testWidgets('a chosen sentence opens the shared playback screen', (
      tester,
    ) async {
      await pump(tester, _suggesting);
      await emit(
        tester,
        const UtteranceState(spokenText: '물 주세요', playbackId: 1),
      );
      expect(find.text('말하고 있어요'), findsOneWidget);
    });

    testWidgets('one clear candidate is shown large and spoken directly', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      const only = Candidate(rank: 1, text: '오늘 좀 피곤해요', score: 0.98);
      await emit(
        tester,
        const UtteranceState(
          phase: UtterancePhase.suggesting,
          transcription: _transcription,
          suggestions: Suggestions(traceId: 's1', candidates: [only]),
          selected: only,
        ),
      );
      expect(find.text('이렇게 말씀드릴게요'), findsOneWidget);
      expect(find.text('오늘 좀 피곤해요'), findsOneWidget);
      expect(find.textContaining('들린 내용'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('utterance_confirm')));
      verify(() => bloc.add(const UtteranceConfirmPressed())).called(1);
    });

    testWidgets('failure shows the failure screen with retry', (tester) async {
      await pump(tester, const UtteranceState());
      await emit(
        tester,
        const UtteranceState(
          phase: UtterancePhase.failed,
          notice: NetworkFailure(),
        ),
      );
      expect(find.text('서버에 연결하지 못했어요'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('failed_retry')));
      verify(() => bloc.add(const UtteranceRetryPressed())).called(1);
    });

    testWidgets('shows heard text, reasons and needs a pick before speaking', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      await emit(tester, _suggesting);

      expect(find.text('이렇게 말씀하시려는 거예요?'), findsOneWidget);
      expect(find.text('들린 내용: "물 좀 주세요"'), findsOneWidget);
      expect(find.text('자주 쓰는 말'), findsOneWidget);
      expect(find.text('이 시간대에 자주 선택'), findsOneWidget);
      expect(find.byKey(const ValueKey('utterance_confirm')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('candidate_2')));
      verify(
        () => bloc.add(UtteranceCandidateTapped(_suggestions.candidates[1])),
      ).called(1);

      await emit(
        tester,
        UtteranceState(
          phase: UtterancePhase.suggesting,
          transcription: _transcription,
          suggestions: _suggestions,
          selected: _suggestions.candidates[1],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('utterance_confirm')));
      verify(() => bloc.add(const UtteranceConfirmPressed())).called(1);
    });

    testWidgets('enlarges candidate text in large text mode', (tester) async {
      double candidateScale() =>
          tester.widget<Text>(find.text('물 주세요').last).textScaler!.scale(10);
      await pump(tester, const UtteranceState());
      await emit(tester, _suggesting);
      final normal = candidateScale();
      await tester.pumpWidget(const SizedBox.shrink());

      await pump(tester, const UtteranceState(), largeText: true);
      await emit(tester, _suggesting);
      expect(candidateScale(), closeTo(normal * 1.25, 0.001));
    });

    testWidgets('closing the sheet reports a dismissal, not a retry', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      await emit(tester, _suggesting);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('이렇게 말씀하시려는 거예요?'), findsNothing);
      verify(() => bloc.add(const UtteranceSheetDismissed())).called(1);
      verifyNever(() => bloc.add(const UtteranceRetryPressed()));
    });

    testWidgets('closes itself when the flow returns to idle', (tester) async {
      await pump(tester, const UtteranceState());
      await emit(tester, _suggesting);
      await emit(tester, const UtteranceState());
      expect(find.text('이렇게 말씀하시려는 거예요?'), findsNothing);
      verifyNever(() => bloc.add(const UtteranceSheetDismissed()));
    });

    testWidgets('third unclear attempt offers quick phrases that play', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      await emit(
        tester,
        const UtteranceState(
          phase: UtterancePhase.reask,
          reaskCount: 3,
          transcription: _transcription,
        ),
      );
      expect(find.text('원하는 문장을 골라 주세요'), findsOneWidget);
      expect(find.text('다시 말하기'), findsNothing);
      await tester.tap(find.text('화장실 가고 싶어요').last);
      await tester.pumpAndSettle();
      expect(find.text('말하고 있어요'), findsOneWidget);
    });

    testWidgets('first unclear attempt asks to speak once more', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      await emit(
        tester,
        const UtteranceState(
          phase: UtterancePhase.reask,
          reaskCount: 1,
          transcription: Transcription(
            traceId: 't',
            finalTranscript: '무ㅏ',
            asrConfidence: 0.2,
            heardText: '무ㅏ 조세여',
          ),
        ),
      );
      expect(find.text('한 번만 다시 말씀해 주세요'), findsOneWidget);
      expect(find.text('무ㅏ 조세여'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reask_retry')));
      verify(() => bloc.add(const UtteranceRetryPressed())).called(1);
    });
  });
}
