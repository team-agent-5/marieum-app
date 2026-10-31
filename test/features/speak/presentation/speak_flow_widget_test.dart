import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/widgets/recording_view.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockUtteranceBloc extends MockBloc<UtteranceEvent, UtteranceState>
    implements UtteranceBloc {}

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

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
    testWidgets('shows timer, guidance and cancel, and locks other controls', (
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
      expect(find.text('말씀이 끝나면 다시 눌러 주세요'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);

      await tester.tap(find.text('요청'), warnIfMissed: false);
      await tester.tap(find.text('실시간 모드'), warnIfMissed: false);
      await tester.tap(find.text('물 주세요'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('0:03'), findsOneWidget);
      verifyNever(() => bloc.add(any()));

      await tester.tap(find.text('취소'));
      verify(() => bloc.add(const UtteranceCancelPressed())).called(1);
    });

    testWidgets('tapping the button again stops recording', (tester) async {
      await pump(tester, const UtteranceState(phase: UtterancePhase.recording));
      await tester.tap(find.byKey(const ValueKey('speak_cta')));
      verify(
        () => bloc.add(const UtteranceButtonPressed(SpeakMode.precise)),
      ).called(1);
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

  group('recording page', () {
    Future<void> show(WidgetTester tester, UtteranceState state) async {
      when(() => bloc.state).thenReturn(state);
      states.add(state);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('opens when recording starts and closes when it ends', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      await show(
        tester,
        const UtteranceState(
          phase: UtterancePhase.recording,
          elapsed: Duration(seconds: 2),
        ),
      );
      expect(find.byType(RecordingView), findsOneWidget);
      expect(find.text('내 목소리로 말하기'), findsOneWidget);
      expect(find.text('정확도 모드'), findsWidgets);
      expect(find.text('00:02'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('recording_finish')));
      verify(
        () => bloc.add(const UtteranceButtonPressed(SpeakMode.precise)),
      ).called(1);

      await show(tester, const UtteranceState(phase: UtterancePhase.analyzing));
      expect(find.byType(RecordingView), findsNothing);
    });

    testWidgets('types live text and cancels from the page', (tester) async {
      await pump(tester, const UtteranceState());
      await show(
        tester,
        const UtteranceState(
          phase: UtterancePhase.recording,
          liveTextAvailable: true,
          liveText: '물',
        ),
      );
      expect(find.text('실시간 텍스트'), findsOneWidget);
      expect(find.text('물'), findsOneWidget);

      await show(
        tester,
        const UtteranceState(
          phase: UtterancePhase.recording,
          liveTextAvailable: true,
          liveText: '물 주세요',
        ),
      );
      expect(find.text('물'), findsOneWidget);
      expect(find.text('주세요'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('recording_cancel')));
      verify(() => bloc.add(const UtteranceCancelPressed())).called(1);
    });

    testWidgets('explains when live text is unavailable', (tester) async {
      await pump(tester, const UtteranceState());
      await show(tester, const UtteranceState(phase: UtterancePhase.recording));
      expect(find.text('말씀을 마치면 글자로 바꿔 드려요'), findsOneWidget);
      expect(find.byType(TypedTranscript), findsNothing);
    });
  });

  group('candidate sheet', () {
    testWidgets('shows heard text, reasons and needs a pick before speaking', (
      tester,
    ) async {
      await pump(tester, const UtteranceState());
      await emit(tester, _suggesting);

      expect(find.text('이렇게 말씀하시려는 거예요?'), findsOneWidget);
      expect(find.text('들린 내용 · 물 좀 주세요'), findsOneWidget);
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
