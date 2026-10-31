import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockTts extends Mock implements TtsPort {}

class _MockHaptics extends Mock implements VoiceHaptics {}

class _MockRepository extends Mock implements UtteranceRepository {}

const _verbatim = Candidate(
  rank: 1,
  text: '물 주세요',
  score: 0.99,
  source: CandidateSource.asrVerbatim,
);
const _recommendedCandidate = Candidate(
  rank: 2,
  text: '미지근한 물 주세요',
  score: 0.86,
  reasonDisplay: '저녁에 자주 요청하신 음료',
  source: CandidateSource.llmInference,
);
const _recommendation = ProactiveSuggestion(
  candidate: _recommendedCandidate,
  modalText: '미지근한 물 주세요라고 말할까요?',
);
const _response = Suggestions(
  traceId: 'trace',
  mode: SuggestionMode.proactive,
  verbatim: _verbatim,
  candidates: [_verbatim, _recommendedCandidate],
  proactiveSuggestion: _recommendation,
);
const _transcription = Transcription(
  traceId: 'asr',
  finalTranscript: '물 주세요',
  asrConfidence: 0.99,
);

void main() {
  group('Proactive playback', () {
    late _MockTts tts;
    late _MockHaptics haptics;
    late _MockRepository repository;
    late Completer<Result<void>> original;
    late Completer<Result<void>> recommended;
    setUpAll(() {
      registerFallbackValue(VoiceHaptic.selected);
      registerFallbackValue(_transcription);
      registerFallbackValue(_response);
      registerFallbackValue(_verbatim);
      registerFallbackValue(Duration.zero);
    });
    setUp(() {
      tts = _MockTts();
      haptics = _MockHaptics();
      repository = _MockRepository();
      original = Completer();
      recommended = Completer();
      when(() => haptics.trigger(any())).thenAnswer((_) async {});
      when(() => tts.speak(_verbatim.text)).thenAnswer((_) => original.future);
      when(
        () => tts.speak(_recommendation.candidate.text),
      ).thenAnswer((_) => recommended.future);
      when(tts.stop).thenAnswer((_) async {
        if (!original.isCompleted) {
          original.complete(const FailureResult(TtsFailure('stopped')));
        }
        if (!recommended.isCompleted) {
          recommended.complete(const FailureResult(TtsFailure('stopped')));
        }
        return const Success(null);
      });
    });
    PlaybackCubit build() => PlaybackCubit(
      request: const PlaybackRequest(
        text: '물 주세요',
        origin: PlaybackOrigin.utterance,
        suggestions: _response,
        transcription: _transcription,
      ),
      tts: tts,
      haptics: haptics,
      repository: repository,
    );
    blocTest<PlaybackCubit, PlaybackState>(
      'opens the suggestion while verbatim playback is still pending',
      build: build,
      act: (cubit) async {
        unawaited(cubit.start());
        await pumpEventQueue();
        expect(cubit.state.suggestionPending, isTrue);
        expect(cubit.state.text, _verbatim.text);
        expect(original.isCompleted, isFalse);
        verify(() => tts.speak(_verbatim.text)).called(1);
        verifyNever(() => tts.speak(_recommendation.candidate.text));
      },
    );
    blocTest<PlaybackCubit, PlaybackState>(
      'acceptance stops original audio '
      'before speaking the suggested phrase once',
      build: build,
      act: (cubit) async {
        unawaited(cubit.start());
        await pumpEventQueue();
        when(tts.stop).thenAnswer((_) async {
          if (!original.isCompleted) {
            original.complete(const FailureResult(TtsFailure('stopped')));
          }
          return const Success(null);
        });
        final acceptance = cubit.acceptSuggestion();
        await cubit.acceptSuggestion();
        await pumpEventQueue();
        expect(cubit.state.text, _recommendation.candidate.text);
        expect(cubit.state.suggestionPending, isFalse);
        verifyInOrder([
          () => tts.speak(_verbatim.text),
          tts.stop,
          () => tts.speak(_recommendation.candidate.text),
        ]);
        verify(
          () => repository.logSelected(
            transcription: _transcription,
            suggestions: _response,
            candidate: _recommendation.candidate,
            latency: any(named: 'latency'),
          ),
        ).called(1);
        recommended.complete(const Success(null));
        await acceptance;
        expect(cubit.state.status, PlaybackStatus.completed);
        expect(cubit.state.text, _recommendation.candidate.text);
      },
    );
    blocTest<PlaybackCubit, PlaybackState>(
      'decline closes only the modal and leaves the original speech running',
      build: build,
      act: (cubit) async {
        unawaited(cubit.start());
        await pumpEventQueue();
        cubit.declineSuggestion();
        expect(cubit.state.suggestionPending, isFalse);
        expect(original.isCompleted, isFalse);
        verifyNever(tts.stop);
        verifyNever(() => tts.speak(_recommendation.candidate.text));
      },
    );
    blocTest<PlaybackCubit, PlaybackState>(
      'expires after three seconds without replaying or stopping the original',
      build: build,
      act: (cubit) async {
        unawaited(cubit.start());
        await Future<void>.delayed(const Duration(milliseconds: 3050));
        expect(cubit.state.suggestionPending, isFalse);
        await cubit.acceptSuggestion();
        verifyNever(tts.stop);
        verifyNever(() => tts.speak(_recommendation.candidate.text));
      },
    );
    blocTest<PlaybackCubit, PlaybackState>(
      'keeps a completed playback screen open while a modal is still pending',
      build: build,
      act: (cubit) async {
        original.complete(const Success(null));
        await cubit.start();
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        expect(cubit.state.status, PlaybackStatus.completed);
        expect(cubit.state.suggestionPending, isTrue);
        cubit.declineSuggestion();
        expect(cubit.state.suggestionPending, isFalse);
      },
    );
    blocTest<PlaybackCubit, PlaybackState>(
      'plays a proactive response without a suggestion '
      'using the normal completion flow',
      build: () => PlaybackCubit(
        request: const PlaybackRequest(
          text: '물 주세요',
          origin: PlaybackOrigin.utterance,
          suggestions: Suggestions(
            traceId: 'no-modal',
            mode: SuggestionMode.proactive,
            verbatim: _verbatim,
            candidates: [_verbatim],
          ),
        ),
        tts: tts,
        haptics: haptics,
      ),
      act: (cubit) async {
        original.complete(const Success(null));
        await cubit.start();
        expect(cubit.state.status, PlaybackStatus.completed);
        expect(cubit.state.suggestionPending, isFalse);
        expect(cubit.state.suggestion, isNull);
      },
    );
  });
}
