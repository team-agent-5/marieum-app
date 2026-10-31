import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/speech/live_transcriber.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements UtteranceRepository {}

class _MockRecorder extends Mock implements Recorder {}

class _MockHaptics extends Mock implements VoiceHaptics {}

class _MockTranscriber extends Mock implements LiveTranscriber {}

final _audio = RecordedAudio(bytes: Uint8List(64), durationMs: 2000);

const _clear = Transcription(
  traceId: 't1',
  finalTranscript: '물 좀 주세요',
  asrConfidence: 0.82,
);
const _unclear = Transcription(
  traceId: 't2',
  finalTranscript: '무ㅏ 조세여',
  asrConfidence: 0.22,
  heardText: '무ㅏ 조세여',
);
const _candidate = Candidate(rank: 1, text: '물 주세요', score: 0.9);
const _suggestions = Suggestions(
  traceId: 's1',
  candidates: [
    _candidate,
    Candidate(rank: 2, text: '미지근한 물 주세요', score: 0.7),
  ],
);

void main() {
  late _MockRepository repository;
  late _MockHaptics haptics;
  late List<_MockRecorder> recorders;
  late List<Completer<RecordedAudio>> recordings;

  setUpAll(() {
    registerFallbackValue(_audio);
    registerFallbackValue(_clear);
    registerFallbackValue(_suggestions);
    registerFallbackValue(_candidate);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(VoiceHaptic.selected);
  });

  setUp(() {
    repository = _MockRepository();
    haptics = _MockHaptics();
    recorders = [];
    recordings = [];
    when(() => haptics.trigger(any())).thenAnswer((_) async {});
    when(() => repository.transcribe(any())).thenAnswer(
      (_) async => const Success(_clear),
    );
    when(() => repository.suggest(any())).thenAnswer(
      (_) async => const Success(_suggestions),
    );
  });

  Recorder newRecorder() {
    final recorder = _MockRecorder();
    final recording = Completer<RecordedAudio>();
    when(recorder.requestPermission).thenAnswer((_) async => true);
    when(
      () => recorder.start(limit: any(named: 'limit')),
    ).thenAnswer((_) async {});
    when(() => recorder.levels).thenAnswer((_) => const Stream.empty());
    when(() => recorder.completed).thenAnswer((_) => recording.future);
    when(recorder.stop).thenAnswer((_) async {
      if (!recording.isCompleted) recording.complete(_audio);
      return _audio;
    });
    when(recorder.dispose).thenAnswer((_) async {});
    recorders.add(recorder);
    recordings.add(recording);
    return recorder;
  }

  UtteranceBloc build() => UtteranceBloc(
    repository: repository,
    createRecorder: newRecorder,
    haptics: haptics,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  UtterancePhase phaseOf(UtteranceState state) => state.phase;

  group(UtteranceBloc, () {
    blocTest<UtteranceBloc, UtteranceState>(
      'first tap records, second tap stops and shows candidates',
      build: build,
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
      },
      expect: () => [
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.recording,
        ),
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.analyzing,
        ),
        isA<UtteranceState>()
            .having(phaseOf, 'phase', UtterancePhase.suggesting)
            .having((s) => s.suggestions, 'suggestions', _suggestions)
            .having((s) => s.selected, 'selected', isNull),
      ],
      verify: (_) {
        verify(() => repository.transcribe(_audio)).called(1);
        verify(() => repository.suggest(_clear)).called(1);
        verify(() => haptics.trigger(VoiceHaptic.recordingStarted)).called(1);
        verify(() => haptics.trigger(VoiceHaptic.recordingStopped)).called(1);
      },
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'finishes on its own when the recorder hits the ten-second limit',
      build: build,
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        recordings.single.complete(_audio);
        await settle();
      },
      skip: 1,
      expect: () => [
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.analyzing,
        ),
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.suggesting,
        ),
      ],
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'ignores the button while analyzing',
      build: () {
        when(
          () => repository.transcribe(any()),
        ).thenAnswer((_) => Completer<Result<Transcription>>().future);
        return build();
      },
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
      },
      expect: () => [
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.recording,
        ),
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.analyzing,
        ),
      ],
      verify: (_) => expect(recorders, hasLength(1)),
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'cancel discards the recording without contacting the server',
      build: build,
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceCancelPressed());
        await settle();
        recordings.single.complete(_audio);
        await settle();
      },
      expect: () => [
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.recording,
        ),
        const UtteranceState(),
      ],
      verify: (_) {
        verifyNever(() => repository.transcribe(any()));
        verify(recorders.single.dispose).called(1);
      },
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'requires a tap to select and a second tap to speak',
      build: build,
      seed: () => const UtteranceState(
        phase: UtterancePhase.suggesting,
        transcription: _clear,
        suggestions: _suggestions,
      ),
      act: (bloc) async {
        bloc.add(const UtteranceCandidateTapped(_candidate));
        await settle();
        bloc.add(const UtteranceConfirmPressed());
        await settle();
      },
      expect: () => [
        isA<UtteranceState>()
            .having(phaseOf, 'phase', UtterancePhase.suggesting)
            .having((s) => s.selected, 'selected', _candidate),
        isA<UtteranceState>()
            .having(phaseOf, 'phase', UtterancePhase.idle)
            .having((s) => s.spokenText, 'text', '물 주세요')
            .having((s) => s.playbackId, 'playbackId', 1),
      ],
      verify: (_) {
        verify(
          () => repository.logSelected(
            transcription: _clear,
            suggestions: _suggestions,
            candidate: _candidate,
            latency: any(named: 'latency'),
          ),
        ).called(1);
      },
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'confirm without a selection does nothing',
      build: build,
      seed: () => const UtteranceState(
        phase: UtterancePhase.suggesting,
        transcription: _clear,
        suggestions: _suggestions,
      ),
      act: (bloc) => bloc.add(const UtteranceConfirmPressed()),
      expect: () => <UtteranceState>[],
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'retry rejects the shown candidates and records again',
      build: build,
      seed: () => const UtteranceState(
        mode: SpeakMode.live,
        phase: UtterancePhase.suggesting,
        transcription: _clear,
        suggestions: _suggestions,
      ),
      act: (bloc) => bloc.add(const UtteranceRetryPressed()),
      expect: () => [
        isA<UtteranceState>().having(
          phaseOf,
          'phase',
          UtterancePhase.recording,
        ),
      ],
      verify: (_) => verify(
        () => repository.logRejected(
          transcription: _clear,
          suggestions: _suggestions,
          latency: any(named: 'latency'),
        ),
      ).called(1),
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'closing the sheet is not a rejection',
      build: build,
      seed: () => const UtteranceState(
        phase: UtterancePhase.suggesting,
        transcription: _clear,
        suggestions: _suggestions,
      ),
      act: (bloc) => bloc.add(const UtteranceSheetDismissed()),
      expect: () => const [UtteranceState()],
      verify: (_) => verifyNever(
        () => repository.logRejected(
          transcription: any(named: 'transcription'),
          suggestions: any(named: 'suggestions'),
          latency: any(named: 'latency'),
        ),
      ),
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'asks again on low confidence and gives up after the third try',
      build: () {
        when(
          () => repository.transcribe(any()),
        ).thenAnswer((_) async => const Success(_unclear));
        return build();
      },
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.live));
        for (var attempt = 0; attempt < 3; attempt++) {
          await settle();
          bloc.add(const UtteranceButtonPressed(SpeakMode.live));
          await settle();
          if (attempt < 2) bloc.add(const UtteranceRetryPressed());
        }
        await settle();
        bloc.add(const UtteranceRetryPressed());
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.phase, UtterancePhase.reask);
        expect(bloc.state.reaskCount, 3);
        expect(bloc.state.reaskExhausted, isTrue);
        expect(recorders, hasLength(3));
        verifyNever(() => repository.suggest(any()));
      },
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'shows the quick phrase fallback when no candidates come back',
      build: () {
        when(() => repository.suggest(any())).thenAnswer(
          (_) async => const Success(
            Suggestions(traceId: 's2', candidates: []),
          ),
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
      },
      verify: (bloc) => expect(bloc.state.phase, UtterancePhase.noMatch),
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'falls back to quick phrases when suggestions time out',
      build: () {
        when(
          () => repository.suggest(any()),
        ).thenAnswer((_) async => const FailureResult(TimeoutFailure()));
        return build();
      },
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
      },
      verify: (bloc) => expect(bloc.state.phase, UtterancePhase.noMatch),
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'shows the failure screen on a network failure',
      build: () {
        when(
          () => repository.transcribe(any()),
        ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
        return build();
      },
      act: (bloc) async {
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
        bloc.add(const UtteranceButtonPressed(SpeakMode.precise));
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.phase, UtterancePhase.failed);
        expect(bloc.state.notice, isA<NetworkFailure>());
      },
    );

    blocTest<UtteranceBloc, UtteranceState>(
      'shows the failure screen when the microphone is denied',
      build: () => UtteranceBloc(
        repository: repository,
        createRecorder: () {
          final recorder = newRecorder() as _MockRecorder;
          when(
            () => recorder.start(limit: any(named: 'limit')),
          ).thenThrow(
            const PermissionFailure(permanent: true),
          );
          return recorder;
        },
        haptics: haptics,
      ),
      act: (bloc) => bloc.add(const UtteranceButtonPressed(SpeakMode.precise)),
      verify: (bloc) {
        expect(bloc.state.phase, UtterancePhase.failed);
        expect(
          bloc.state.notice,
          isA<PermissionFailure>().having(
            (f) => f.permanent,
            'permanent',
            true,
          ),
        );
      },
    );

    group('live mode', () {
      blocTest<UtteranceBloc, UtteranceState>(
        'speaks the transcript right away without candidates',
        build: () {
          when(
            () => repository.bypass(any(), latency: any(named: 'latency')),
          ).thenAnswer((_) async => const Success('물 좀 주세요'));
          return build();
        },
        act: (bloc) async {
          bloc.add(const UtteranceButtonPressed(SpeakMode.live));
          await settle();
          bloc.add(const UtteranceButtonPressed(SpeakMode.live));
          await settle();
        },
        verify: (bloc) {
          verifyNever(() => repository.suggest(any()));
          expect(bloc.state.phase, UtterancePhase.idle);
          expect(bloc.state.spokenText, '물 좀 주세요');
          expect(bloc.state.playbackId, 1);
        },
      );

      blocTest<UtteranceBloc, UtteranceState>(
        'asks again when the server refuses a low-confidence bypass',
        build: () {
          when(
            () => repository.bypass(any(), latency: any(named: 'latency')),
          ).thenAnswer(
            (_) async =>
                const FailureResult(ValidationFailure(fieldErrors: {})),
          );
          return build();
        },
        act: (bloc) async {
          bloc.add(const UtteranceButtonPressed(SpeakMode.live));
          await settle();
          bloc.add(const UtteranceButtonPressed(SpeakMode.live));
          await settle();
        },
        verify: (bloc) {
          expect(bloc.state.phase, UtterancePhase.reask);
          expect(bloc.state.spokenText, isNull);
        },
      );
    });

    test('stops recording and speech when closed', () async {
      final bloc = build()
        ..add(const UtteranceButtonPressed(SpeakMode.precise));
      await settle();
      await bloc.close();
      verify(recorders.single.dispose).called(1);
    });
  });

  group('hold to record', () {
    test('holding records and releasing stops and analyzes', () async {
      var now = DateTime(2026, 10, 31, 12);
      final bloc = UtteranceBloc(
        repository: repository,
        createRecorder: newRecorder,
        haptics: haptics,
        now: () => now,
      );
      addTearDown(bloc.close);
      bloc.add(const UtteranceHoldStarted(SpeakMode.precise));
      await settle();
      expect(bloc.state.phase, UtterancePhase.recording);
      now = now.add(const Duration(seconds: 2));
      bloc.add(const UtteranceHoldEnded());
      await settle();
      await settle();
      verify(recorders.single.stop).called(1);
      expect(bloc.state.phase, UtterancePhase.suggesting);
    });

    test('a very short hold is dropped without analysis', () async {
      final now = DateTime(2026, 10, 31, 12);
      final bloc = UtteranceBloc(
        repository: repository,
        createRecorder: newRecorder,
        haptics: haptics,
        now: () => now,
      );
      addTearDown(bloc.close);
      bloc.add(const UtteranceHoldStarted(SpeakMode.precise));
      await settle();
      bloc.add(const UtteranceHoldEnded());
      await settle();
      expect(bloc.state.phase, UtterancePhase.idle);
      verifyNever(() => repository.transcribe(any()));
    });

    blocTest<UtteranceBloc, UtteranceState>(
      'retry in accuracy mode waits for the next hold and keeps attempts',
      build: build,
      seed: () => const UtteranceState(
        phase: UtterancePhase.reask,
        transcription: _unclear,
        reaskCount: 1,
      ),
      act: (bloc) => bloc.add(const UtteranceRetryPressed()),
      expect: () => const [UtteranceState(reaskCount: 1)],
      verify: (_) => expect(recorders, isEmpty),
    );
  });

  test('live mode records up to the long limit', () async {
    when(
      () => repository.bypass(any(), latency: any(named: 'latency')),
    ).thenAnswer((_) async => const Success('물'));
    final bloc = build()..add(const UtteranceButtonPressed(SpeakMode.live));
    addTearDown(bloc.close);
    await settle();
    verify(
      () => recorders.single.start(limit: Recorder.liveMaxDuration),
    ).called(1);
  });

  test('accuracy mode keeps the 10 second limit', () async {
    final bloc = build()..add(const UtteranceHoldStarted(SpeakMode.precise));
    addTearDown(bloc.close);
    await settle();
    final limit = verify(
      () => recorders.single.start(limit: captureAny(named: 'limit')),
    ).captured.single;
    expect(limit, Recorder.maxDuration);
  });

  group('live text', () {
    late _MockTranscriber transcriber;
    late StreamController<String> partials;
    late StreamController<Uint8List> chunks;

    setUp(() {
      registerFallbackValue(Uint8List(0));
      transcriber = _MockTranscriber();
      partials = StreamController<String>.broadcast();
      chunks = StreamController<Uint8List>.broadcast();
      addTearDown(partials.close);
      addTearDown(chunks.close);
      when(() => transcriber.partials).thenAnswer((_) => partials.stream);
      when(transcriber.stop).thenAnswer((_) async {});
      when(
        () => repository.bypass(any(), latency: any(named: 'latency')),
      ).thenAnswer((_) async => const Success('물 좀 주세요'));
    });

    UtteranceBloc buildLive() => UtteranceBloc(
      repository: repository,
      createRecorder: () {
        final recorder = newRecorder() as _MockRecorder;
        when(() => recorder.chunks).thenAnswer((_) => chunks.stream);
        return recorder;
      },
      createTranscriber: () => transcriber,
      haptics: haptics,
    );

    test('feeds recorder chunks and shows partial text', () async {
      when(transcriber.start).thenAnswer((_) async => true);
      final bloc = buildLive();
      addTearDown(bloc.close);
      bloc.add(const UtteranceButtonPressed(SpeakMode.live));
      await settle();
      expect(bloc.state.liveTextAvailable, isTrue);

      final pcm = Uint8List.fromList([1, 2, 3, 4]);
      chunks.add(pcm);
      partials.add(' 물 ');
      await settle();
      verify(() => transcriber.append(pcm)).called(1);
      expect(bloc.state.liveText, '물');

      bloc.add(const UtteranceButtonPressed(SpeakMode.live));
      await settle();
      await settle();
      verify(transcriber.stop).called(1);
      partials.add('물 주세요');
      await settle();
      expect(bloc.state.liveText, isNot('물 주세요'));
    });

    test('records without live text when recognition is unavailable', () async {
      when(transcriber.start).thenAnswer((_) async => false);
      final bloc = buildLive();
      addTearDown(bloc.close);
      bloc.add(const UtteranceButtonPressed(SpeakMode.live));
      await settle();
      expect(bloc.state.phase, UtterancePhase.recording);
      expect(bloc.state.liveTextAvailable, isFalse);
      chunks.add(Uint8List(4));
      await settle();
      verifyNever(() => transcriber.append(any()));
    });

    test('cancel stops recognition', () async {
      when(transcriber.start).thenAnswer((_) async => true);
      final bloc = buildLive();
      addTearDown(bloc.close);
      bloc.add(const UtteranceButtonPressed(SpeakMode.live));
      await settle();
      bloc.add(const UtteranceCancelPressed());
      await settle();
      verify(transcriber.stop).called(1);
      expect(bloc.state.liveText, isEmpty);
    });
  });
}
