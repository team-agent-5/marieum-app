import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/pump_app.dart';

class _MockPlaybackCubit extends MockCubit<PlaybackState>
    implements PlaybackCubit {}

void main() {
  group('Proactive suggestion modal', () {
    late _MockPlaybackCubit cubit;
    late StreamController<PlaybackState> states;
    const suggestion = ProactiveSuggestion(
      candidate: Candidate(
        rank: 2,
        text: '미지근한 물 주세요',
        score: 0.86,
        reasonDisplay: '저녁에 자주 요청하신 음료',
      ),
      modalText: '미지근한 물 주세요라고 말할까요?',
    );
    const pending = PlaybackState(
      text: '물 주세요',
      status: PlaybackStatus.playing,
      suggestion: suggestion,
      suggestionPending: true,
    );
    setUp(() {
      cubit = _MockPlaybackCubit();
      states = StreamController<PlaybackState>.broadcast();
      whenListen(cubit, states.stream, initialState: pending);
      when(cubit.start).thenAnswer((_) async {});
      when(cubit.close).thenAnswer((_) async {});
      when(cubit.acceptSuggestion).thenAnswer((_) async {});
    });
    tearDown(() async => states.close());
    Future<void> open(WidgetTester tester) async {
      final router = await tester.pumpApp(createPlaybackCubit: (_) => cubit);
      unawaited(
        router.push<void>(
          '/speak/playback',
          extra: const PlaybackRequest(
            text: '물 주세요',
            origin: PlaybackOrigin.utterance,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows server modal wording and reason while original text is playing',
      (tester) async {
        await open(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(suggestion.modalText), findsOneWidget);
        expect(find.text(suggestion.candidate.reasonDisplay!), findsOneWidget);
        expect(find.text('물 주세요'), findsOneWidget);
        await tester.tap(find.text('네'));
        await tester.pump();
        verify(cubit.acceptSuggestion).called(1);
      },
    );
    testWidgets('declines without navigating away from original playback', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('아니오'));
      await tester.pump();
      verify(cubit.declineSuggestion).called(1);
      verifyNever(cubit.acceptSuggestion);
    });
    testWidgets('removes the modal when the response window expires', (
      tester,
    ) async {
      await open(tester);
      states.add(
        const PlaybackState(
          text: '물 주세요',
          status: PlaybackStatus.playing,
          suggestion: suggestion,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('물 주세요'), findsOneWidget);
    });
    testWidgets('back dismisses only the suggestion before leaving playback', (
      tester,
    ) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      verify(cubit.declineSuggestion).called(1);
      expect(find.text('물 주세요'), findsOneWidget);
    });
  });
}
